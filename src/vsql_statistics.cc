/* Copyright (c) 2026 VillageSQL Contributors
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, see <https://www.gnu.org/licenses/>.
 */

#include <villagesql/vsql.h>

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <limits>
#include <numeric>
#include <string>
#include <optional>
#include <unordered_map>
#include <vector>

using vsql::RealArg;
using vsql::RealResult;
using vsql::StringResult;

// =============================================================================
// Shared utilities
// =============================================================================

// Convergence parameters shared by the series / continued-fraction evaluators
// (incomplete beta and incomplete gamma).
static constexpr int    max_series_iter = 500;
static constexpr double lentz_tiny      = 1e-30;  // Lentz floor to avoid division by zero
static constexpr double converge_eps    = 1e-12;

// Returns the argument's value when it is non-NULL and finite. Filters NULL,
// NaN, and ±Inf in one place so downstream arithmetic can never produce
// "nan"/"inf" tokens, which are invalid JSON.
static std::optional<double> finite_value(RealArg v) {
  if (v.is_null() || !std::isfinite(v.value())) return std::nullopt;
  return v.value();
}

// Format a double without scientific notation. Uses fixed notation (trimmed) for
// values where %g would emit an exponent (|val| < 1e-4), and %g otherwise.
// Magnitudes below ~5e-16 flush to "0.0" — a deliberate trade-off to keep
// fixed-notation output; see mysql-test/t/stats_ztest.test for the pinned case.
static std::string fmt_no_exp(double val) {
  char buf[64];
  if (val != 0.0 && std::fabs(val) < 1e-4) {
    std::snprintf(buf, sizeof(buf), "%.15f", val);
    // Trim trailing zeros, but keep at least one decimal digit.
    std::string s(buf);
    const size_t dot = s.find('.');
    if (dot != std::string::npos) {
      size_t last = s.find_last_not_of('0');
      if (last != std::string::npos && last > dot) s.erase(last + 1);
      else if (last == dot)                         s.erase(dot + 2);
    }
    return s;
  }
  std::snprintf(buf, sizeof(buf), "%.15g", val);
  return std::string(buf);
}

// Appends "key":<value> to json (no surrounding braces or separators).
static void append_field(std::string &json, const char *key, double val) {
  json += '"'; json += key; json += "\":";
  json += fmt_no_exp(val);
}

// Nullable variant: emits the JSON literal null when val is empty.
static void append_field(std::string &json, const char *key,
                         const std::optional<double> &val) {
  json += '"'; json += key; json += "\":";
  json += val ? fmt_no_exp(*val) : "null";
}

// =============================================================================
// IQR family
// =============================================================================

struct StatsState {
  std::vector<double> values;
  bool oom = false;  // allocation failed during accumulate; result reports error
};

static void stats_clear(StatsState &s) {
  s.values.clear();
  s.oom = false;
}

static void stats_accumulate(StatsState &s, RealArg v) try {
  if (const auto x = finite_value(v)) s.values.push_back(*x);
} catch (...) { s.oom = true; }

// Median of a sorted sub-range [lo, hi).
static double range_median(const std::vector<double> &v, size_t lo, size_t hi) {
  assert(lo < hi);
  const size_t n = hi - lo;
  const size_t mid = lo + n / 2;
  return (n % 2 == 1) ? v[mid] : (v[mid - 1] + v[mid]) / 2.0;
}

struct Quartiles { double q1, median, q3; };

// Computes the median and Q1/Q3 using Tukey's hinges (exclusive median).
// Precondition: sorted is non-empty and in ascending order.
static Quartiles compute_quartiles(const std::vector<double> &sorted) {
  const size_t n = sorted.size();
  const double median = range_median(sorted, 0, n);
  if (n == 1) return Quartiles{sorted[0], median, sorted[0]};
  const size_t lower_end   = n / 2;
  const size_t upper_start = (n % 2 == 1) ? lower_end + 1 : lower_end;
  return Quartiles{range_median(sorted, 0, lower_end), median,
                   range_median(sorted, upper_start, n)};
}

static void stats_iqr_json_result(const StatsState &s, StringResult out) try {
  if (s.oom) { out.error("STATS_IQR: out of memory"); return; }
  if (s.values.empty()) { out.set_null(); return; }

  std::vector<double> sorted(s.values);
  std::sort(sorted.begin(), sorted.end());
  const Quartiles q = compute_quartiles(sorted);
  const double iqr = q.q3 - q.q1;
  constexpr double fence_mult = 1.5;  // Tukey's standard fence multiplier

  std::string json;
  json.reserve(200);
  json += '{';
  append_field(json, "q1",          q.q1);                json += ',';
  append_field(json, "median",      q.median);            json += ',';
  append_field(json, "q3",          q.q3);                json += ',';
  append_field(json, "iqr",         iqr);                 json += ',';
  append_field(json, "lower_fence", q.q1 - fence_mult * iqr); json += ',';
  append_field(json, "upper_fence", q.q3 + fence_mult * iqr);
  json += '}';
  out.set(json);
} catch (...) { out.error("STATS_IQR: unexpected error"); }

static constexpr auto make_iqr_json_func(const char *name) {
  return vsql::make_aggregate_func<StatsState, &stats_iqr_json_result>(name)
    .returns(vsql::STRING)
    .param(vsql::REAL)
    .template clear<&stats_clear>()
    .template accumulate<&stats_accumulate>()
    .build();
}

// =============================================================================
// Two-sample t-test assuming equal variances (pooled-variance t-test)
// =============================================================================

struct TTestState {
  std::vector<double> group1;
  std::vector<double> group2;
  double alpha{0.05};
  bool oom = false;
};

static void ttest_clear(TTestState &s) {
  s = TTestState{};
}

// Accumulate for 2-parameter functions (value, group).
// group == 1.0 → group1, group == 2.0 → group2; other values are ignored.
static void ttest_accumulate(TTestState &s, RealArg value, RealArg group) try {
  const auto v = finite_value(value);
  const auto g = finite_value(group);
  if (!v || !g) return;
  if (*g == 1.0)      s.group1.push_back(*v);
  else if (*g == 2.0) s.group2.push_back(*v);
} catch (...) { s.oom = true; }

// Accumulate for 3-parameter functions (value, group, alpha).
// alpha: last non-NULL finite value wins (constant per group in practice).
static void ttest_crit_accumulate(TTestState &s, RealArg value, RealArg group,
                                   RealArg alpha) {
  ttest_accumulate(s, value, group);
  if (const auto a = finite_value(alpha)) s.alpha = *a;
}

// Continued fraction core for the regularized incomplete beta function.
// Uses Lentz's algorithm (Numerical Recipes §6.4); the multi-statement lines
// below are the canonical NR formulation. Precondition: x < (a+1)/(a+b+2).
static double betacf(double x, double a, double b) {
  const double qab = a + b;
  const double qap = a + 1.0;
  const double qam = a - 1.0;
  double c = 1.0;
  double d = 1.0 - qab * x / qap;
  if (std::fabs(d) < lentz_tiny) d = lentz_tiny;
  d = 1.0 / d;
  double h = d;

  for (int m = 1; m <= max_series_iter; m++) {
    const int m2 = 2 * m;
    // Even step
    double aa = static_cast<double>(m) * (b - static_cast<double>(m)) * x
                / ((qam + m2) * (a + m2));
    d = 1.0 + aa * d; if (std::fabs(d) < lentz_tiny) d = lentz_tiny; d = 1.0 / d;
    c = 1.0 + aa / c; if (std::fabs(c) < lentz_tiny) c = lentz_tiny;
    h *= d * c;
    // Odd step
    aa = -(a + static_cast<double>(m)) * (qab + static_cast<double>(m)) * x
         / ((a + m2) * (qap + m2));
    d = 1.0 + aa * d; if (std::fabs(d) < lentz_tiny) d = lentz_tiny; d = 1.0 / d;
    c = 1.0 + aa / c; if (std::fabs(c) < lentz_tiny) c = lentz_tiny;
    const double del = d * c;
    h *= del;
    if (std::fabs(del - 1.0) < converge_eps) break;
  }
  // If max_series_iter is reached without convergence the current estimate is
  // returned; for the df ranges reachable through SQL this does not occur.
  return h;
}

// Regularized incomplete beta function I_x(a, b).
static double betai(double x, double a, double b) {
  if (x <= 0.0) return 0.0;
  if (x >= 1.0) return 1.0;
  // Use symmetry I_x(a,b) = 1 - I_{1-x}(b,a) when x is large for convergence.
  if (x > (a + 1.0) / (a + b + 2.0)) return 1.0 - betai(1.0 - x, b, a);
  const double lbeta_ab = std::lgamma(a) + std::lgamma(b) - std::lgamma(a + b);
  const double front = std::exp(a * std::log(x) + b * std::log(1.0 - x) - lbeta_ab) / a;
  return front * betacf(x, a, b);
}

// Two-tail p-value: P(|T_df| > |t|) using the incomplete beta function.
static double t_two_tail_p(double t, double df) {
  const double x = df / (df + t * t);
  return betai(x, df / 2.0, 0.5);
}

// One-tail critical value: largest t > 0 such that P(T_df > t) >= alpha.
// Uses bisection on t_two_tail_p; 200 iterations gives ~12 significant figures.
static double t_critical(double alpha, double df) {
  double lo = 0.0;
  double hi = 10.0;
  while (t_two_tail_p(hi, df) / 2.0 > alpha && hi < 1e10) {
    lo = hi;
    hi *= 2.0;
  }
  for (int i = 0; i < 200; i++) {
    const double mid = (lo + hi) / 2.0;
    if (t_two_tail_p(mid, df) / 2.0 > alpha) lo = mid;
    else                                       hi = mid;
  }
  return (lo + hi) / 2.0;
}

// All t-test statistics including per-group descriptives (matches Excel output).
struct TTestResult {
  double mean1, mean2;
  double var1, var2;    // sample variance: ssq / (n-1)
  double n1, n2;
  double pooled_var;
  double df;
  double t_stat;
};

// Returns nullopt if either group has fewer than 2 observations (df ≤ 0)
// or if pooled variance is zero and means differ (t would be ±inf).
static std::optional<TTestResult> compute_ttest(const TTestState &s) {
  const size_t n1 = s.group1.size();
  const size_t n2 = s.group2.size();
  if (n1 < 2 || n2 < 2) return std::nullopt;

  double sum1 = 0.0;
  double sum2 = 0.0;
  for (const double v : s.group1) sum1 += v;
  for (const double v : s.group2) sum2 += v;
  const double mean1 = sum1 / static_cast<double>(n1);
  const double mean2 = sum2 / static_cast<double>(n2);

  double ssq1 = 0.0;
  double ssq2 = 0.0;
  for (const double v : s.group1) ssq1 += (v - mean1) * (v - mean1);
  for (const double v : s.group2) ssq2 += (v - mean2) * (v - mean2);

  const double df         = static_cast<double>(n1 + n2 - 2);
  const double pooled_var = (ssq1 + ssq2) / df;

  if (pooled_var == 0.0) {
    if (mean1 == mean2) return TTestResult{mean1, mean2, 0.0, 0.0,
                                           static_cast<double>(n1), static_cast<double>(n2),
                                           0.0, df, 0.0};
    return std::nullopt;
  }

  const double t    = (mean1 - mean2) / std::sqrt(pooled_var * (1.0 / static_cast<double>(n1)
                                                               + 1.0 / static_cast<double>(n2)));
  const double var1 = ssq1 / static_cast<double>(n1 - 1);
  const double var2 = ssq2 / static_cast<double>(n2 - 1);
  return TTestResult{mean1, mean2, var1, var2,
                     static_cast<double>(n1), static_cast<double>(n2),
                     pooled_var, df, t};
}

// Inference statistics only: pooled_var, df, t, p_one_tail, t_crit_one_tail,
// p_two_tail, t_crit_two_tail. t_crit_* are null when alpha is out of range.
// Kept separate from per-group descriptives to stay within the VEF 255-byte
// STRING limit (see villagesql/villagesql-server#641).
static void stats_ttest_result(const TTestState &s, StringResult out) try {
  if (s.oom) { out.error("STATS_TTEST: out of memory"); return; }
  const auto r = compute_ttest(s);
  if (!r) { out.set_null(); return; }

  const double p_one = t_two_tail_p(r->t_stat, r->df) / 2.0;
  const double p_two = t_two_tail_p(r->t_stat, r->df);
  const double alpha = s.alpha;
  // alpha ∈ (0,1) also guarantees alpha/2 ∈ (0,0.5), so one check covers both
  // critical values.
  const bool crit_ok = alpha > 0.0 && alpha < 1.0;
  const std::optional<double> crit_one = crit_ok
    ? std::optional<double>(t_critical(alpha, r->df)) : std::nullopt;
  const std::optional<double> crit_two = crit_ok
    ? std::optional<double>(t_critical(alpha / 2.0, r->df)) : std::nullopt;

  std::string json;
  json.reserve(256);
  json += '{';
  append_field(json, "pooled_var",      r->pooled_var); json += ',';
  append_field(json, "df",              r->df);         json += ',';
  append_field(json, "t",               r->t_stat);     json += ',';
  append_field(json, "p_one_tail",      p_one);         json += ',';
  append_field(json, "t_crit_one_tail", crit_one);      json += ',';
  append_field(json, "p_two_tail",      p_two);         json += ',';
  append_field(json, "t_crit_two_tail", crit_two);
  json += '}';

  out.set(json);
} catch (...) { out.error("STATS_TTEST: unexpected error"); }

// Per-group descriptives: mean, sample variance, and observation count for
// each group. Complements STATS_TTEST — use both together for a full picture.
static void stats_ttest_groups_result(const TTestState &s, StringResult out) try {
  if (s.oom) { out.error("STATS_TTEST_GROUPS: out of memory"); return; }
  const auto r = compute_ttest(s);
  if (!r) { out.set_null(); return; }

  std::string json;
  json.reserve(200);
  json += '{';
  append_field(json, "mean_1",     r->mean1); json += ',';
  append_field(json, "mean_2",     r->mean2); json += ',';
  append_field(json, "variance_1", r->var1);  json += ',';
  append_field(json, "variance_2", r->var2);  json += ',';
  append_field(json, "n_1",        r->n1);    json += ',';
  append_field(json, "n_2",        r->n2);
  json += '}';

  out.set(json);
} catch (...) { out.error("STATS_TTEST_GROUPS: unexpected error"); }

static constexpr auto make_ttest_func(const char *name) {
  return vsql::make_aggregate_func<TTestState, &stats_ttest_result>(name)
    .returns(vsql::STRING)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .template clear<&ttest_clear>()
    .template accumulate<&ttest_crit_accumulate>()
    .build();
}

static constexpr auto make_ttest_groups_func(const char *name) {
  return vsql::make_aggregate_func<TTestState, &stats_ttest_groups_result>(name)
    .returns(vsql::STRING)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .template clear<&ttest_clear>()
    .template accumulate<&ttest_accumulate>()
    .build();
}

// =============================================================================
// Mode family
// =============================================================================

struct ModeState {
  std::unordered_map<double, size_t> freq;
  bool oom = false;
};

static void mode_clear(ModeState &s) {
  s.freq.clear();
  s.oom = false;
}

static void mode_accumulate(ModeState &s, RealArg v) try {
  if (const auto x = finite_value(v)) s.freq[*x]++;
} catch (...) { s.oom = true; }

// Returns empty if all-NULL input or no value repeats (max freq == 1).
static std::vector<double> compute_modes(const ModeState &s) {
  if (s.freq.empty()) return {};
  size_t max_freq = 0;
  std::vector<double> modes;
  for (const auto &kv : s.freq) {
    if (kv.second > max_freq) {
      max_freq = kv.second;
      modes.clear();
      modes.push_back(kv.first);
    } else if (kv.second == max_freq) {
      modes.push_back(kv.first);
    }
  }
  if (max_freq <= 1) return {};
  std::sort(modes.begin(), modes.end());
  return modes;
}

// values: sorted array of all mode values. min/max: first and last for convenience.
// NULL when no value repeats (max frequency == 1) or all inputs are NULL/NaN.
static void stats_mode_json_result(const ModeState &s, StringResult out) try {
  if (s.oom) { out.error("STATS_MODE: out of memory"); return; }
  const auto modes = compute_modes(s);
  if (modes.empty()) { out.set_null(); return; }

  std::string json;
  json.reserve(modes.size() * 24 + 48);
  json += "{\"values\":[";
  for (size_t i = 0; i < modes.size(); ++i) {
    if (i > 0) json += ',';
    json += fmt_no_exp(modes[i]);
  }
  json += "],\"min\":";
  json += fmt_no_exp(modes.front());
  json += ",\"max\":";
  json += fmt_no_exp(modes.back());
  json += '}';
  out.set(json);
} catch (...) { out.error("STATS_MODE: unexpected error"); }

static constexpr auto make_mode_json_func(const char *name) {
  return vsql::make_aggregate_func<ModeState, &stats_mode_json_result>(name)
    .returns(vsql::STRING)
    .param(vsql::REAL)
    .template clear<&mode_clear>()
    .template accumulate<&mode_accumulate>()
    .build();
}

// =============================================================================
// Skewness family
// =============================================================================

// JSON object with both skewness measures.
// moment: population skewness g₁ = m₃/m₂^(3/2) (third standardized moment).
// pearson: 3 × (mean − median) / population_stddev.
// Both are null when variance is zero; the whole result is null when n < 2.
static void stats_skewness_json_result(const StatsState &s, StringResult out) try {
  if (s.oom) { out.error("STATS_SKEWNESS: out of memory"); return; }
  const size_t n = s.values.size();
  if (n < 2) { out.set_null(); return; }

  const double dn = static_cast<double>(n);
  const double mean = std::accumulate(s.values.begin(), s.values.end(), 0.0) / dn;

  double sum2 = 0.0, sum3 = 0.0;
  for (const double v : s.values) {
    const double d = v - mean;
    sum2 += d * d;
    sum3 += d * d * d;
  }
  const double m2 = sum2 / dn;

  std::optional<double> moment;
  std::optional<double> pearson;
  if (m2 > 0.0) {
    std::vector<double> sorted(s.values);
    std::sort(sorted.begin(), sorted.end());
    const double stddev = std::sqrt(m2);
    moment  = (sum3 / dn) / std::pow(m2, 1.5);
    pearson = 3.0 * (mean - range_median(sorted, 0, n)) / stddev;
  }

  std::string json;
  json.reserve(128);
  json += '{';
  append_field(json, "moment",  moment);  json += ',';
  append_field(json, "pearson", pearson);
  json += '}';
  out.set(json);
} catch (...) { out.error("STATS_SKEWNESS: unexpected error"); }

static constexpr auto make_skewness_json_func(const char *name) {
  return vsql::make_aggregate_func<StatsState, &stats_skewness_json_result>(name)
    .returns(vsql::STRING)
    .param(vsql::REAL)
    .template clear<&stats_clear>()
    .template accumulate<&stats_accumulate>()
    .build();
}

// =============================================================================
// One-sample Z-test (known population mean and standard deviation)
// =============================================================================

struct ZTestState {
  size_t n = 0;
  double sum = 0.0;
  double mu = 0.0;    // population mean (constant; last non-null finite wins)
  double sigma = 0.0; // population std dev (last non-null finite wins; 0 = never set → NULL)
};

static void ztest_clear(ZTestState &s) { s = ZTestState{}; }

static void ztest_accumulate(ZTestState &s, RealArg value, RealArg mu, RealArg sigma) {
  if (const auto m = finite_value(mu))     s.mu    = *m;
  if (const auto sd = finite_value(sigma)) s.sigma = *sd;
  const auto v = finite_value(value);
  if (!v) return;
  s.n++;
  s.sum += *v;
}

// Returns nullopt when no values accumulated or sigma was never set (0.0) /
// is non-positive. mu and sigma are always finite here — see ztest_accumulate.
static std::optional<double> compute_ztest(const ZTestState &s) {
  if (s.n == 0 || !(s.sigma > 0.0)) return std::nullopt;
  const double mean = s.sum / static_cast<double>(s.n);
  return (mean - s.mu) / (s.sigma / std::sqrt(static_cast<double>(s.n)));
}

// p_one_tail: P(Z > z) = 0.5×erfc(z/√2) — upper-tail; > 0.5 when sample mean < μ.
// p_two_tail: P(|Z| > z) = erfc(|z|/√2).
static void stats_ztest_json_result(const ZTestState &s, StringResult out) try {
  const auto z = compute_ztest(s);
  if (!z) { out.set_null(); return; }

  std::string json;
  json.reserve(128);
  json += '{';
  append_field(json, "z",          *z);
  json += ',';
  append_field(json, "p_one_tail", 0.5 * std::erfc(*z / std::sqrt(2.0)));
  json += ',';
  append_field(json, "p_two_tail", std::erfc(std::fabs(*z) / std::sqrt(2.0)));
  json += '}';

  out.set(json);
} catch (...) { out.error("STATS_ZTEST: unexpected error"); }

static constexpr auto make_ztest_json_func(const char *name) {
  return vsql::make_aggregate_func<ZTestState, &stats_ztest_json_result>(name)
    .returns(vsql::STRING)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .template clear<&ztest_clear>()
    .template accumulate<&ztest_accumulate>()
    .build();
}

// =============================================================================
// Chi-squared family (Goodness of Fit and Test of Independence)
// =============================================================================

// Shared log-gamma normalisation factor used by both series and continued fraction.
static double gamma_prefix(double a, double x) {
  return std::exp(-x + a * std::log(x) - std::lgamma(a));
}

// Series expansion of the regularized lower incomplete gamma P(a, x) = γ(a,x)/Γ(a).
// Converges for x < a+1.
static double gammap_series(double a, double x) {
  double ap  = a;
  double del = 1.0 / a;
  double sum = del;
  for (int i = 0; i < max_series_iter; i++) {
    ap  += 1.0;
    del *= x / ap;
    sum += del;
    if (std::fabs(del) < std::fabs(sum) * converge_eps) break;
  }
  return sum * gamma_prefix(a, x);
}

// Continued fraction representation of the upper incomplete gamma Q(a, x) = Γ(a,x)/Γ(a).
// Converges for x >= a+1. Uses Lentz's algorithm (Numerical Recipes §6.2).
static double gammacf(double a, double x) {
  double b = x + 1.0 - a;
  double c = 1.0 / lentz_tiny;
  double d = 1.0 / b;
  double h = d;
  for (int i = 1; i <= max_series_iter; i++) {
    const double an = -static_cast<double>(i) * (static_cast<double>(i) - a);
    b += 2.0;
    d = an * d + b; if (std::fabs(d) < lentz_tiny) d = lentz_tiny; d = 1.0 / d;
    c = b + an / c; if (std::fabs(c) < lentz_tiny) c = lentz_tiny;
    const double del = d * c;
    h *= del;
    if (std::fabs(del - 1.0) < converge_eps) break;
  }
  return gamma_prefix(a, x) * h;
}

// Regularized upper incomplete gamma Q(a, x) = 1 - P(a, x).
// P(χ²_df > stat) = Q(df/2, stat/2) — the chi-squared survival function.
static double gammaq(double a, double x) {
  if (x <= 0.0) return 1.0;
  if (x < a + 1.0) return 1.0 - gammap_series(a, x);
  return gammacf(a, x);
}

struct ChiSqGofState {
  double chi_sq = 0.0;
  size_t k = 0;
};

static void chisq_gof_clear(ChiSqGofState &s) { s = ChiSqGofState{}; }

// Shared cell accumulation: (O-E)²/E; skips rows where O or E is NULL/non-finite,
// or E is zero or negative.
static void chisq_accumulate_cell(double &chi_sq, size_t &k, RealArg observed, RealArg expected) {
  const auto obs = finite_value(observed);
  const auto e   = finite_value(expected);
  if (!obs || !e || !(*e > 0.0)) return;
  const double diff = *obs - *e;
  chi_sq += (diff * diff) / *e;
  k++;
}

static void chisq_gof_accumulate(ChiSqGofState &s, RealArg observed, RealArg expected) {
  chisq_accumulate_cell(s.chi_sq, s.k, observed, expected);
}

// chi_sq, df, p — p is null when df=0 (k=1 category).
static void stats_chisq_gof_json_result(const ChiSqGofState &s, StringResult out) try {
  if (s.k == 0) { out.set_null(); return; }
  const double df = static_cast<double>(s.k - 1);
  const std::optional<double> p = (s.k > 1)
    ? std::optional<double>(gammaq(df / 2.0, s.chi_sq / 2.0)) : std::nullopt;

  std::string json;
  json.reserve(128);
  json += '{';
  append_field(json, "chi_sq", s.chi_sq); json += ',';
  append_field(json, "df",     df);       json += ',';
  append_field(json, "p",      p);
  json += '}';

  out.set(json);
} catch (...) { out.error("STATS_CHISQ_GOF: unexpected error"); }

static constexpr auto make_chisq_gof_json_func(const char *name) {
  return vsql::make_aggregate_func<ChiSqGofState, &stats_chisq_gof_json_result>(name)
    .returns(vsql::STRING)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .template clear<&chisq_gof_clear>()
    .template accumulate<&chisq_gof_accumulate>()
    .build();
}

struct ChiSqIndepState {
  double chi_sq = 0.0;
  size_t k = 0;        // count of valid (O,E) pairs; 0 → NULL result
  double n_rows = 0.0; // last non-null; (n_rows-1)*(n_cols-1) gives df
  double n_cols = 0.0;
};

static void chisq_indep_clear(ChiSqIndepState &s) { s = ChiSqIndepState{}; }

static void chisq_indep_accumulate(ChiSqIndepState &s, RealArg observed,
                                   RealArg expected, RealArg n_rows, RealArg n_cols) {
  if (const auto r = finite_value(n_rows)) s.n_rows = *r;
  if (const auto c = finite_value(n_cols)) s.n_cols = *c;
  chisq_accumulate_cell(s.chi_sq, s.k, observed, expected);
}

// chi_sq, df, p — df/p are null when either dimension floors below 1 (missing
// or fractional < 1, which would otherwise yield a negative df); p is also
// null when df = 0 (1×N tables).
static void stats_chisq_indep_json_result(const ChiSqIndepState &s, StringResult out) try {
  if (s.k == 0) { out.set_null(); return; }

  std::optional<double> df;
  if (std::floor(s.n_rows) >= 1.0 && std::floor(s.n_cols) >= 1.0)
    df = (std::floor(s.n_rows) - 1.0) * (std::floor(s.n_cols) - 1.0);
  const std::optional<double> p = (df && *df > 0.0)
    ? std::optional<double>(gammaq(*df / 2.0, s.chi_sq / 2.0)) : std::nullopt;

  std::string json;
  json.reserve(128);
  json += '{';
  append_field(json, "chi_sq", s.chi_sq); json += ',';
  append_field(json, "df",     df);       json += ',';
  append_field(json, "p",      p);
  json += '}';

  out.set(json);
} catch (...) { out.error("STATS_CHISQ_INDEP: unexpected error"); }

static constexpr auto make_chisq_indep_json_func(const char *name) {
  return vsql::make_aggregate_func<ChiSqIndepState, &stats_chisq_indep_json_result>(name)
    .returns(vsql::STRING)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .template clear<&chisq_indep_clear>()
    .template accumulate<&chisq_indep_accumulate>()
    .build();
}

// =============================================================================
// Kurtosis family
// =============================================================================

struct KurtState {
  size_t n = 0;
  double ref = 0.0;   // first observed value; centering reduces floating-point cancellation
  double sum1 = 0.0;  // Σ(xi - ref)
  double sum2 = 0.0;  // Σ(xi - ref)²
  double sum3 = 0.0;  // Σ(xi - ref)³
  double sum4 = 0.0;  // Σ(xi - ref)⁴
};

static void kurt_clear(KurtState &s) { s = KurtState{}; }

static void kurt_accumulate(KurtState &s, RealArg v) {
  const auto x = finite_value(v);
  if (!x) return;
  if (s.n == 0) s.ref = *x;
  const double d = *x - s.ref;
  const double d2 = d * d;
  s.n++;
  s.sum1 += d;
  s.sum2 += d2;
  s.sum3 += d2 * d;
  s.sum4 += d2 * d2;
}

struct KurtMoments { double ssq2, ssq4; };

// Derives Σ(xi−mean)² and Σ(xi−mean)⁴ from the shifted accumulators.
// Returns nullopt when all values are equal (zero variance).
static std::optional<KurtMoments> compute_kurt_moments(const KurtState &s) {
  const double c  = s.sum1 / static_cast<double>(s.n);
  const double c2 = c * c;
  const double n  = static_cast<double>(s.n);
  const double ssq2 = s.sum2 - n * c2;
  if (!(ssq2 > 0.0)) return std::nullopt;
  const double ssq4 = s.sum4 - 4.0*c*s.sum3 + 6.0*c2*s.sum2 - 3.0*n*c2*c2;
  return KurtMoments{ssq2, ssq4};
}

// kurtosis: β₂ = μ₄/m₂² (population, n≥2). excess: g₂ Fisher-Pearson (n≥4).
// kurtosis/excess both null when variance is zero; excess null when n < 4.
// Whole result is null when n < 2.
static void stats_kurtosis_json_result(const KurtState &s, StringResult out) try {
  if (s.n < 2) { out.set_null(); return; }

  const auto km = compute_kurt_moments(s);
  const double n = static_cast<double>(s.n);

  std::optional<double> kurtosis;
  std::optional<double> excess;
  if (km) {
    kurtosis = km->ssq4 * n / (km->ssq2 * km->ssq2);
    if (s.n >= 4) {
      const double a = (n - 1.0) / ((n - 2.0) * (n - 3.0));
      excess = a * (n * (n + 1.0) * km->ssq4 / (km->ssq2 * km->ssq2) - 3.0 * (n - 1.0));
    }
  }

  std::string json;
  json.reserve(128);
  json += '{';
  append_field(json, "kurtosis", kurtosis); json += ',';
  append_field(json, "excess",   excess);
  json += '}';
  out.set(json);
} catch (...) { out.error("STATS_KURTOSIS: unexpected error"); }

static constexpr auto make_kurtosis_json_func(const char *name) {
  return vsql::make_aggregate_func<KurtState, &stats_kurtosis_json_result>(name)
    .returns(vsql::STRING)
    .param(vsql::REAL)
    .template clear<&kurt_clear>()
    .template accumulate<&kurt_accumulate>()
    .build();
}

// =============================================================================
// Covariance family
// =============================================================================

// Welford's online algorithm for co-moments; skips any row where either
// argument is NULL (concurrent-pair discard per spec).
struct CovState {
  size_t n = 0;
  double mean_x = 0.0;
  double mean_y = 0.0;
  double co_moment = 0.0;  // converges to Σ(xi−x̄)(yi−ȳ)
};

static void cov_clear(CovState &s) { s = CovState{}; }

static void cov_accumulate(CovState &s, RealArg x, RealArg y) {
  const auto xv = finite_value(x);
  const auto yv = finite_value(y);
  if (!xv || !yv) return;
  s.n++;
  const double dx = *xv - s.mean_x;
  s.mean_x += dx / static_cast<double>(s.n);
  s.mean_y += (*yv - s.mean_y) / static_cast<double>(s.n);
  s.co_moment += dx * (*yv - s.mean_y);  // uses updated mean_y — Welford's co-moment form
}

// pop = C/n (0.0 for n=1); samp = C/(n-1) (null for n<2); whole result NULL for n=0.
static void stats_cov_json_result(const CovState &s, StringResult out) try {
  if (s.n == 0) { out.set_null(); return; }
  const double dn = static_cast<double>(s.n);
  const std::optional<double> samp = (s.n >= 2)
    ? std::optional<double>(s.co_moment / (dn - 1.0)) : std::nullopt;

  std::string json;
  json.reserve(64);
  json += '{';
  append_field(json, "pop",  s.co_moment / dn); json += ',';
  append_field(json, "samp", samp);
  json += '}';
  out.set(json);
} catch (...) { out.error("STATS_COVARIANCE: unexpected error"); }

static constexpr auto make_cov_json_func(const char *name) {
  return vsql::make_aggregate_func<CovState, &stats_cov_json_result>(name)
    .returns(vsql::STRING)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .template clear<&cov_clear>()
    .template accumulate<&cov_accumulate>()
    .build();
}

// =============================================================================
// Means family (trimmed, Winsorized, geometric, harmonic)
// =============================================================================

// trim_pct = NaN sentinel means "never set" → trimmed/winsorized fields are null.
struct MeanState {
  std::vector<double> values;
  double trim_pct = std::numeric_limits<double>::quiet_NaN();
  size_t n_pos = 0;
  double sum_log = 0.0;   // Σ ln(xi) for positive values
  double sum_recip = 0.0; // Σ(1/xi) for positive values
  bool oom = false;
};

static void mean_clear(MeanState &s) { s = MeanState{}; }

static void mean_accumulate(MeanState &s, RealArg v, RealArg trim_pct) try {
  if (const auto p = finite_value(trim_pct)) s.trim_pct = *p;
  const auto x = finite_value(v);
  if (!x) return;
  s.values.push_back(*x);
  if (*x > 0.0) {
    s.n_pos++;
    s.sum_log += std::log(*x);
    s.sum_recip += 1.0 / *x;
  }
} catch (...) { s.oom = true; }

// trimmed/winsorized are null when trim_pct was never set, invalid, or all values removed.
// geometric/harmonic are null when no positive values exist.
// Whole result is NULL when no values were accumulated.
static void stats_mean_json_result(const MeanState &s, StringResult out) try {
  if (s.oom) { out.error("STATS_MEAN: out of memory"); return; }
  if (s.values.empty()) { out.set_null(); return; }

  const size_t n = s.values.size();
  const double p = s.trim_pct;
  std::optional<double> trimmed;
  std::optional<double> winsorized;

  if (!std::isnan(p) && p >= 0.0 && p < 0.5) {
    std::vector<double> sorted(s.values);
    std::sort(sorted.begin(), sorted.end());
    const size_t k = static_cast<size_t>(std::floor(p * static_cast<double>(n)));
    if (2 * k < n) {
      double tsum = 0.0;
      for (size_t i = k; i < n - k; ++i) tsum += sorted[i];
      trimmed = tsum / static_cast<double>(n - 2 * k);

      const double lo = sorted[k];
      const double hi = sorted[n - 1 - k];
      double wsum = static_cast<double>(k) * lo;
      for (size_t i = k; i < n - k; ++i) wsum += sorted[i];
      wsum += static_cast<double>(k) * hi;
      winsorized = wsum / static_cast<double>(n);
    }
  }

  const std::optional<double> geometric = (s.n_pos > 0)
    ? std::optional<double>(std::exp(s.sum_log / static_cast<double>(s.n_pos)))
    : std::nullopt;
  const std::optional<double> harmonic = (s.n_pos > 0)
    ? std::optional<double>(static_cast<double>(s.n_pos) / s.sum_recip)
    : std::nullopt;

  std::string json;
  json.reserve(160);
  json += '{';
  append_field(json, "trimmed",    trimmed);    json += ',';
  append_field(json, "winsorized", winsorized); json += ',';
  append_field(json, "geometric",  geometric);  json += ',';
  append_field(json, "harmonic",   harmonic);
  json += '}';
  out.set(json);
} catch (...) { out.error("STATS_MEAN: unexpected error"); }

static constexpr auto make_mean_json_func(const char *name) {
  return vsql::make_aggregate_func<MeanState, &stats_mean_json_result>(name)
    .returns(vsql::STRING)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .template clear<&mean_clear>()
    .template accumulate<&mean_accumulate>()
    .build();
}

// =============================================================================
// One-way ANOVA family (One-Way Analysis of Variance)
// =============================================================================

struct AnovaGroupStats {
  size_t n = 0;
  double sum = 0.0;  // Σ yij — used for grand mean and SSB
  double mean = 0.0; // running mean (Welford)
  double ss = 0.0;   // Σ(yij − mean)² via Welford's online M2
};

struct AnovaState {
  std::unordered_map<double, AnovaGroupStats> groups;
  bool oom = false;
};

static void anova_clear(AnovaState &s) {
  s.groups.clear();
  s.oom = false;
}

static void anova_accumulate(AnovaState &s, RealArg value, RealArg group) try {
  const auto v = finite_value(value);
  const auto g = finite_value(group);
  if (!v || !g) return;
  auto &gs = s.groups[*g];
  gs.n++;
  gs.sum += *v;
  const double delta = *v - gs.mean;
  gs.mean += delta / static_cast<double>(gs.n);
  gs.ss += delta * (*v - gs.mean);
} catch (...) { s.oom = true; }

struct AnovaResult {
  double ssb;
  double ssw;
  double sst;
  double msb;
  double msw;
  double f;
  double df_b;
  double df_w;
};

// Returns nullopt when k < 2, any group has n < 2, or MSW is zero.
// k = 2 is permitted; it is mathematically equivalent to a pooled two-sample
// t-test (F = t²) — see STATS_TTEST for two-group comparisons.
static std::optional<AnovaResult> compute_anova(const AnovaState &s) {
  const size_t k = s.groups.size();
  if (k < 2) return std::nullopt;

  size_t N = 0;
  double grand_sum = 0.0;
  for (const auto &[label, g] : s.groups) {
    if (g.n < 2) return std::nullopt;
    N += g.n;
    grand_sum += g.sum;
  }

  const double grand_mean = grand_sum / static_cast<double>(N);

  double ssb = 0.0;
  double ssw = 0.0;
  for (const auto &[label, g] : s.groups) {
    const double diff = g.mean - grand_mean;
    ssb += static_cast<double>(g.n) * diff * diff;
    ssw += g.ss;
  }

  const double df_b = static_cast<double>(k - 1);
  const double df_w = static_cast<double>(N - k);
  if (!(df_w > 0.0)) return std::nullopt;

  const double msw = ssw / df_w;
  if (!(msw > 0.0)) return std::nullopt;
  const double msb = ssb / df_b;
  const double f   = msb / msw;

  return AnovaResult{ssb, ssw, ssb + ssw, msb, msw, f, df_b, df_w};
}

// P(F_{dfB,dfW} > F) = I_{dfW/(dfW + dfB·F)}(dfW/2, dfB/2)
static void stats_anova_json_result(const AnovaState &s, StringResult out) try {
  if (s.oom) { out.error("STATS_ANOVA: out of memory"); return; }
  const auto r = compute_anova(s);
  if (!r) { out.set_null(); return; }

  const double p = betai(r->df_w / (r->df_w + r->df_b * r->f), r->df_w / 2.0, r->df_b / 2.0);

  std::string json;
  json.reserve(256);
  json += '{';
  append_field(json, "f",    r->f);    json += ',';
  append_field(json, "p",    p);       json += ',';
  append_field(json, "ssb",  r->ssb);  json += ',';
  append_field(json, "ssw",  r->ssw);  json += ',';
  append_field(json, "sst",  r->sst);  json += ',';
  append_field(json, "msb",  r->msb);  json += ',';
  append_field(json, "msw",  r->msw);  json += ',';
  append_field(json, "df_b", r->df_b); json += ',';
  append_field(json, "df_w", r->df_w);
  json += '}';

  out.set(json);
} catch (...) { out.error("STATS_ANOVA: unexpected error"); }

static constexpr auto make_anova_json_func(const char *name) {
  return vsql::make_aggregate_func<AnovaState, &stats_anova_json_result>(name)
    .returns(vsql::STRING)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .template clear<&anova_clear>()
    .template accumulate<&anova_accumulate>()
    .build();
}

// =============================================================================
// Registration
// =============================================================================

VEF_GENERATE_ENTRY_POINTS(
  vsql::make_extension()
    .func(make_iqr_json_func("STATS_IQR"))
    .func(make_ttest_func("STATS_TTEST"))
    .func(make_ttest_groups_func("STATS_TTEST_GROUPS"))
    .func(make_mode_json_func("STATS_MODE"))
    .func(make_skewness_json_func("STATS_SKEWNESS"))
    .func(make_ztest_json_func("STATS_ZTEST"))
    .func(make_chisq_gof_json_func("STATS_CHISQ_GOF"))
    .func(make_chisq_indep_json_func("STATS_CHISQ_INDEP"))
    .func(make_kurtosis_json_func("STATS_KURTOSIS"))
    .func(make_cov_json_func("STATS_COVARIANCE"))
    .func(make_mean_json_func("STATS_MEAN"))
    .func(make_anova_json_func("STATS_ANOVA"))
)
