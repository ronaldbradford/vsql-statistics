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
// IQR family
// =============================================================================

struct StatsState {
  mutable std::vector<double> values;
};

static void stats_clear(StatsState &s) {
  s.values.clear();
}

static void stats_accumulate(StatsState &s, RealArg v) {
  if (!v.is_null() && !std::isnan(v.value())) s.values.push_back(v.value());
}

// Median of a sorted sub-range [lo, hi).
static double range_median(const std::vector<double> &v, size_t lo, size_t hi) {
  assert(lo < hi);
  const size_t n = hi - lo;
  const size_t mid = lo + n / 2;
  return (n % 2 == 1) ? v[mid] : (v[mid - 1] + v[mid]) / 2.0;
}

struct Quartiles { double q1, q3; };

// Sorts values and computes Q1, Q3 using Tukey's hinges (exclusive median).
static std::optional<Quartiles> compute_quartiles(const StatsState &s) {
  if (s.values.empty()) return std::nullopt;
  std::sort(s.values.begin(), s.values.end());
  const size_t n = s.values.size();
  if (n == 1) return Quartiles{s.values[0], s.values[0]};
  const size_t lower_end = n / 2;
  const size_t upper_start = (n % 2 == 1) ? lower_end + 1 : lower_end;
  return Quartiles{range_median(s.values, 0, lower_end),
                   range_median(s.values, upper_start, n)};
}

static void stats_iqr_result(const StatsState &s, RealResult out) try {
  const auto qr = compute_quartiles(s);
  if (!qr) { out.set_null(); return; }
  out.set(qr->q3 - qr->q1);
} catch (...) { out.error("STATS_IQR: unexpected error"); }

static void stats_q1_result(const StatsState &s, RealResult out) try {
  const auto qr = compute_quartiles(s);
  if (!qr) { out.set_null(); return; }
  out.set(qr->q1);
} catch (...) { out.error("STATS_Q1: unexpected error"); }

static void stats_q3_result(const StatsState &s, RealResult out) try {
  const auto qr = compute_quartiles(s);
  if (!qr) { out.set_null(); return; }
  out.set(qr->q3);
} catch (...) { out.error("STATS_Q3: unexpected error"); }

static void stats_median_result(const StatsState &s, RealResult out) try {
  if (s.values.empty()) { out.set_null(); return; }
  std::sort(s.values.begin(), s.values.end());
  out.set(range_median(s.values, 0, s.values.size()));
} catch (...) { out.error("STATS_MEDIAN: unexpected error"); }

static void stats_iqr_lower_fence_result(const StatsState &s, RealResult out) try {
  const auto qr = compute_quartiles(s);
  if (!qr) { out.set_null(); return; }
  out.set(qr->q1 - 1.5 * (qr->q3 - qr->q1));
} catch (...) { out.error("STATS_IQR_LOWER_FENCE: unexpected error"); }

static void stats_iqr_upper_fence_result(const StatsState &s, RealResult out) try {
  const auto qr = compute_quartiles(s);
  if (!qr) { out.set_null(); return; }
  out.set(qr->q3 + 1.5 * (qr->q3 - qr->q1));
} catch (...) { out.error("STATS_IQR_UPPER_FENCE: unexpected error"); }

template<auto ResultFn>
static constexpr auto make_stats_func(const char *name) {
  return vsql::make_aggregate_func<StatsState, ResultFn>(name)
    .returns(vsql::REAL)
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
};

static void ttest_clear(TTestState &s) {
  s = TTestState{};
}

// Accumulate for 2-parameter functions (value, group).
// group == 1.0 → group1, group == 2.0 → group2; other values are ignored.
static void ttest_accumulate(TTestState &s, RealArg value, RealArg group) {
  if (value.is_null() || group.is_null()) return;
  const double v = value.value();
  const double g = group.value();
  if (std::isnan(v) || std::isnan(g)) return;
  if (g == 1.0)      s.group1.push_back(v);
  else if (g == 2.0) s.group2.push_back(v);
}

// Accumulate for 3-parameter functions (value, group, alpha).
static void ttest_crit_accumulate(TTestState &s, RealArg value, RealArg group,
                                   RealArg alpha) {
  ttest_accumulate(s, value, group);
  if (!alpha.is_null() && !std::isnan(alpha.value())) s.alpha = alpha.value();
}

// Continued fraction core for the regularized incomplete beta function.
// Uses Lentz's algorithm. Precondition: x < (a+1)/(a+b+2).
static double betacf(double x, double a, double b) {
  constexpr int    max_iter = 500;
  constexpr double tiny     = 1e-30;
  constexpr double eps      = 1e-12;

  const double qab = a + b;
  const double qap = a + 1.0;
  const double qam = a - 1.0;
  double c = 1.0;
  double d = 1.0 - qab * x / qap;
  if (std::fabs(d) < tiny) d = tiny;
  d = 1.0 / d;
  double h = d;

  for (int m = 1; m <= max_iter; m++) {
    const int m2 = 2 * m;
    // Even step
    double aa = static_cast<double>(m) * (b - static_cast<double>(m)) * x
                / ((qam + m2) * (a + m2));
    d = 1.0 + aa * d; if (std::fabs(d) < tiny) d = tiny; d = 1.0 / d;
    c = 1.0 + aa / c; if (std::fabs(c) < tiny) c = tiny;
    h *= d * c;
    // Odd step
    aa = -(a + static_cast<double>(m)) * (qab + static_cast<double>(m)) * x
         / ((a + m2) * (qap + m2));
    d = 1.0 + aa * d; if (std::fabs(d) < tiny) d = tiny; d = 1.0 / d;
    c = 1.0 + aa / c; if (std::fabs(c) < tiny) c = tiny;
    const double del = d * c;
    h *= del;
    if (std::fabs(del - 1.0) < eps) break;
  }
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

// Format a double without scientific notation. Uses fixed notation (trimmed) for
// values where %g would emit an exponent (|val| < 1e-4), and %g otherwise.
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

// Inference statistics only: pooled_var, df, t, p_one_tail, t_crit_one_tail,
// p_two_tail, t_crit_two_tail. t_crit_* are null when alpha is out of range.
// Kept separate from per-group descriptives to stay within the VEF 255-byte
// STRING limit (see villagesql/villagesql-server#641).
static void stats_ttest_result(const TTestState &s, StringResult out) try {
  const auto r = compute_ttest(s);
  if (!r) { out.set_null(); return; }

  const double p_one    = t_two_tail_p(r->t_stat, r->df) / 2.0;
  const double p_two    = t_two_tail_p(r->t_stat, r->df);
  const double alpha    = s.alpha;
  const double alpha_h  = alpha / 2.0;
  const bool   crit_ok  = !std::isnan(alpha) && alpha > 0.0 && alpha < 1.0;
  const bool   crit2_ok = !std::isnan(alpha_h) && alpha_h > 0.0 && alpha_h < 0.5;

  std::string json;
  json.reserve(256);

  auto append = [&](const char *key, double val) {
    json += '"'; json += key; json += "\":";
    json += fmt_no_exp(val);
  };

  json += '{';
  append("pooled_var",  r->pooled_var); json += ',';
  append("df",          r->df);         json += ',';
  append("t",           r->t_stat);     json += ',';
  append("p_one_tail",  p_one);         json += ',';
  json += "\"t_crit_one_tail\":";
  json += crit_ok  ? fmt_no_exp(t_critical(alpha,   r->df)) : "null";
  json += ',';
  append("p_two_tail",  p_two);         json += ',';
  json += "\"t_crit_two_tail\":";
  json += crit2_ok ? fmt_no_exp(t_critical(alpha_h, r->df)) : "null";
  json += '}';

  out.set(json);
} catch (...) { out.error("STATS_TTEST: unexpected error"); }

// Per-group descriptives: mean, sample variance, and observation count for
// each group. Complements STATS_TTEST — use both together for a full picture.
static void stats_ttest_groups_result(const TTestState &s, StringResult out) try {
  const auto r = compute_ttest(s);
  if (!r) { out.set_null(); return; }

  std::string json;
  json.reserve(200);

  auto append = [&](const char *key, double val) {
    json += '"'; json += key; json += "\":";
    json += fmt_no_exp(val);
  };

  json += '{';
  append("mean_1",     r->mean1); json += ',';
  append("mean_2",     r->mean2); json += ',';
  append("variance_1", r->var1);  json += ',';
  append("variance_2", r->var2);  json += ',';
  append("n_1",        r->n1);    json += ',';
  append("n_2",        r->n2);
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
};

static void mode_clear(ModeState &s) {
  s.freq.clear();
}

static void mode_accumulate(ModeState &s, RealArg v) {
  if (!v.is_null() && !std::isnan(v.value())) s.freq[v.value()]++;
}

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

static void stats_mode_result(const ModeState &s, StringResult out) try {
  const auto modes = compute_modes(s);
  if (modes.empty()) { out.set_null(); return; }
  std::string json;
  json.reserve(modes.size() * 8 + 2);
  json += '[';
  for (size_t i = 0; i < modes.size(); ++i) {
    if (i > 0) json += ", ";
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%g", modes[i]);
    json += buf;
  }
  json += ']';
  out.set(json);
} catch (...) { out.error("STATS_MODE: unexpected error"); }

static void stats_mode_min_result(const ModeState &s, RealResult out) try {
  if (s.freq.empty()) { out.set_null(); return; }
  size_t max_freq = 0;
  double min_val = std::numeric_limits<double>::infinity();
  for (const auto &kv : s.freq) {
    if (kv.second > max_freq) {
      max_freq = kv.second;
      min_val = kv.first;
    } else if (kv.second == max_freq) {
      min_val = std::min(min_val, kv.first);
    }
  }
  if (max_freq <= 1) { out.set_null(); return; }
  out.set(min_val);
} catch (...) { out.error("STATS_MODE_MIN: unexpected error"); }

static void stats_mode_max_result(const ModeState &s, RealResult out) try {
  if (s.freq.empty()) { out.set_null(); return; }
  size_t max_freq = 0;
  double max_val = -std::numeric_limits<double>::infinity();
  for (const auto &kv : s.freq) {
    if (kv.second > max_freq) {
      max_freq = kv.second;
      max_val = kv.first;
    } else if (kv.second == max_freq) {
      max_val = std::max(max_val, kv.first);
    }
  }
  if (max_freq <= 1) { out.set_null(); return; }
  out.set(max_val);
} catch (...) { out.error("STATS_MODE_MAX: unexpected error"); }

template<auto ResultFn>
static constexpr auto make_mode_real_func(const char *name) {
  return vsql::make_aggregate_func<ModeState, ResultFn>(name)
    .returns(vsql::REAL)
    .param(vsql::REAL)
    .template clear<&mode_clear>()
    .template accumulate<&mode_accumulate>()
    .build();
}

template<auto ResultFn>
static constexpr auto make_mode_str_func(const char *name) {
  return vsql::make_aggregate_func<ModeState, ResultFn>(name)
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

  std::string json;
  json.reserve(128);
  json += '{';

  if (m2 <= 0.0) {
    json += "\"moment\":null,\"pearson\":null";
  } else {
    std::sort(s.values.begin(), s.values.end());
    const double stddev = std::sqrt(m2);
    json += "\"moment\":";
    json += fmt_no_exp((sum3 / dn) / std::pow(m2, 1.5));
    json += ",\"pearson\":";
    json += fmt_no_exp(3.0 * (mean - range_median(s.values, 0, n)) / stddev);
  }

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
  double mu = 0.0;    // population mean (constant; last non-null wins)
  double sigma = 0.0; // population std dev (constant; last non-null wins; 0 = never set → NULL)
};

static void ztest_clear(ZTestState &s) { s = ZTestState{}; }

static void ztest_accumulate(ZTestState &s, RealArg value, RealArg mu, RealArg sigma) {
  if (!mu.is_null() && !std::isnan(mu.value()))    s.mu    = mu.value();
  if (!sigma.is_null() && !std::isnan(sigma.value())) s.sigma = sigma.value();
  if (value.is_null() || std::isnan(value.value())) return;
  s.n++;
  s.sum += value.value();
}

// Returns nullopt when sigma was never set (0.0), is non-positive, or NaN.
static std::optional<double> compute_ztest(const ZTestState &s) {
  if (s.n == 0 || !(s.sigma > 0.0) || std::isnan(s.sigma) || std::isnan(s.mu)) return std::nullopt;
  const double mean = s.sum / static_cast<double>(s.n);
  return (mean - s.mu) / (s.sigma / std::sqrt(static_cast<double>(s.n)));
}

static void stats_ztest_z_result(const ZTestState &s, RealResult out) try {
  const auto z = compute_ztest(s);
  if (!z) { out.set_null(); return; }
  out.set(*z);
} catch (...) { out.error("STATS_ZTEST_Z: unexpected error"); }

// Upper-tail probability: P(Z > z) = 0.5 × erfc(z/√2).
// Returns values in (0.5, 1] when z < 0 (sample mean below μ).
static void stats_ztest_p_one_tail_result(const ZTestState &s, RealResult out) try {
  const auto z = compute_ztest(s);
  if (!z) { out.set_null(); return; }
  out.set(0.5 * std::erfc(*z / std::sqrt(2.0)));
} catch (...) { out.error("STATS_ZTEST_P_ONE_TAIL: unexpected error"); }

static void stats_ztest_p_two_tail_result(const ZTestState &s, RealResult out) try {
  const auto z = compute_ztest(s);
  if (!z) { out.set_null(); return; }
  out.set(std::erfc(std::fabs(*z) / std::sqrt(2.0)));
} catch (...) { out.error("STATS_ZTEST_P_TWO_TAIL: unexpected error"); }

template<auto ResultFn>
static constexpr auto make_ztest_func(const char *name) {
  return vsql::make_aggregate_func<ZTestState, ResultFn>(name)
    .returns(vsql::REAL)
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
  constexpr int    max_iter = 500;
  constexpr double eps      = 1e-12;

  double ap  = a;
  double del = 1.0 / a;
  double sum = del;
  for (int i = 0; i < max_iter; i++) {
    ap  += 1.0;
    del *= x / ap;
    sum += del;
    if (std::fabs(del) < std::fabs(sum) * eps) break;
  }
  return sum * gamma_prefix(a, x);
}

// Continued fraction representation of the upper incomplete gamma Q(a, x) = Γ(a,x)/Γ(a).
// Converges for x >= a+1. Uses Lentz's algorithm.
static double gammacf(double a, double x) {
  constexpr int    max_iter = 500;
  constexpr double tiny     = 1e-30;
  constexpr double eps      = 1e-12;

  double b = x + 1.0 - a;
  double c = 1.0 / tiny;
  double d = 1.0 / b;
  double h = d;
  for (int i = 1; i <= max_iter; i++) {
    const double an = -static_cast<double>(i) * (static_cast<double>(i) - a);
    b += 2.0;
    d = an * d + b; if (std::fabs(d) < tiny) d = tiny; d = 1.0 / d;
    c = b + an / c; if (std::fabs(c) < tiny) c = tiny;
    const double del = d * c;
    h *= del;
    if (std::fabs(del - 1.0) < eps) break;
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

// Shared cell accumulation: (O-E)²/E; skips rows where E is NULL, zero, or negative.
static void chisq_accumulate_cell(double &chi_sq, size_t &k, RealArg observed, RealArg expected) {
  if (observed.is_null() || expected.is_null()) return;
  const double obs = observed.value();
  const double e = expected.value();
  if (std::isnan(obs) || std::isnan(e)) return;
  if (!(e > 0.0)) return;
  const double diff = obs - e;
  chi_sq += (diff * diff) / e;
  k++;
}

static void chisq_gof_accumulate(ChiSqGofState &s, RealArg observed, RealArg expected) {
  chisq_accumulate_cell(s.chi_sq, s.k, observed, expected);
}

// chi_sq, df, p — p is null when df=0 (k=1 category).
static void stats_chisq_gof_json_result(const ChiSqGofState &s, StringResult out) try {
  if (s.k == 0) { out.set_null(); return; }
  const double df = static_cast<double>(s.k - 1);

  std::string json;
  json.reserve(128);

  auto append = [&](const char *key, double val) {
    json += '"'; json += key; json += "\":";
    json += fmt_no_exp(val);
  };

  json += '{';
  append("chi_sq", s.chi_sq); json += ',';
  append("df", df); json += ',';
  json += "\"p\":";
  json += (s.k > 1) ? fmt_no_exp(gammaq(df / 2.0, s.chi_sq / 2.0)) : "null";
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
  if (!n_rows.is_null() && !std::isnan(n_rows.value())) s.n_rows = n_rows.value();
  if (!n_cols.is_null() && !std::isnan(n_cols.value())) s.n_cols = n_cols.value();
  chisq_accumulate_cell(s.chi_sq, s.k, observed, expected);
}

// chi_sq, df, p — df/p are null when n_rows/n_cols missing or df <= 0.
static void stats_chisq_indep_json_result(const ChiSqIndepState &s, StringResult out) try {
  if (s.k == 0) { out.set_null(); return; }

  const bool has_dims = (s.n_rows > 0.0) && (s.n_cols > 0.0);
  const double df = has_dims
    ? (std::floor(s.n_rows) - 1.0) * (std::floor(s.n_cols) - 1.0)
    : 0.0;

  std::string json;
  json.reserve(128);

  auto append = [&](const char *key, double val) {
    json += '"'; json += key; json += "\":";
    json += fmt_no_exp(val);
  };

  json += '{';
  append("chi_sq", s.chi_sq); json += ',';
  json += "\"df\":";
  json += has_dims ? fmt_no_exp(df) : "null";
  json += ',';
  json += "\"p\":";
  json += (has_dims && df > 0.0) ? fmt_no_exp(gammaq(df / 2.0, s.chi_sq / 2.0)) : "null";
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
  if (v.is_null() || std::isnan(v.value())) return;
  if (s.n == 0) s.ref = v.value();
  const double d = v.value() - s.ref;
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

  std::string json;
  json.reserve(128);
  json += '{';
  json += "\"kurtosis\":";

  if (!km) {
    json += "null,\"excess\":null";
  } else {
    const double beta2 = km->ssq4 * n / (km->ssq2 * km->ssq2);
    json += fmt_no_exp(beta2);
    json += ",\"excess\":";
    if (s.n < 4) {
      json += "null";
    } else {
      const double a = (n - 1.0) / ((n - 2.0) * (n - 3.0));
      json += fmt_no_exp(a * (n * (n + 1.0) * km->ssq4 / (km->ssq2 * km->ssq2) - 3.0 * (n - 1.0)));
    }
  }

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
  double C = 0.0;  // running co-moment: converges to Σ(xi−x̄)(yi−ȳ)
};

static void cov_clear(CovState &s) { s = CovState{}; }

static void cov_accumulate(CovState &s, RealArg x, RealArg y) {
  if (x.is_null() || y.is_null()) return;
  const double xv = x.value();
  const double yv = y.value();
  if (std::isnan(xv) || std::isnan(yv)) return;
  s.n++;
  const double dx = xv - s.mean_x;
  s.mean_x += dx / static_cast<double>(s.n);
  s.mean_y += (yv - s.mean_y) / static_cast<double>(s.n);
  s.C += dx * (yv - s.mean_y);  // uses updated mean_y — Welford's co-moment form
}

// Population covariance σ_xy = C/n. N=1 yields 0.0; N=0 yields NULL.
static void stats_cov_pop_result(const CovState &s, RealResult out) try {
  if (s.n == 0) { out.set_null(); return; }
  out.set(s.C / static_cast<double>(s.n));
} catch (...) { out.error("STATS_COVARIANCE_POP: unexpected error"); }

// Sample covariance s_xy = C/(n−1). Returns NULL for n < 2.
static void stats_cov_samp_result(const CovState &s, RealResult out) try {
  if (s.n < 2) { out.set_null(); return; }
  out.set(s.C / static_cast<double>(s.n - 1));
} catch (...) { out.error("STATS_COVARIANCE_SAMP: unexpected error"); }

template<auto ResultFn>
static constexpr auto make_cov_func(const char *name) {
  return vsql::make_aggregate_func<CovState, ResultFn>(name)
    .returns(vsql::REAL)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .template clear<&cov_clear>()
    .template accumulate<&cov_accumulate>()
    .build();
}

// =============================================================================
// Means family (trimmed, Winsorized, geometric, harmonic)
// =============================================================================

struct MeanTrimState {
  mutable std::vector<double> values;
  double trim_pct = 0.0; // fraction to trim/winsorize from each end (last non-null wins)
};

static void mean_trim_clear(MeanTrimState &s) { s = MeanTrimState{}; }

static void mean_trim_accumulate(MeanTrimState &s, RealArg v, RealArg trim_pct) {
  if (!trim_pct.is_null() && !std::isnan(trim_pct.value())) s.trim_pct = trim_pct.value();
  if (!v.is_null() && !std::isnan(v.value())) s.values.push_back(v.value());
}

static void stats_mean_trimmed_result(const MeanTrimState &s, RealResult out) try {
  if (s.values.empty()) { out.set_null(); return; }
  const double p = s.trim_pct;
  if (std::isnan(p) || p < 0.0 || p >= 0.5) { out.set_null(); return; }
  std::sort(s.values.begin(), s.values.end());
  const size_t n = s.values.size();
  const size_t k = static_cast<size_t>(std::floor(p * static_cast<double>(n)));
  if (2 * k >= n) { out.set_null(); return; }
  double sum = 0.0;
  for (size_t i = k; i < n - k; ++i) sum += s.values[i];
  out.set(sum / static_cast<double>(n - 2 * k));
} catch (...) { out.error("STATS_MEAN_TRIMMED: unexpected error"); }

static void stats_mean_winsorized_result(const MeanTrimState &s, RealResult out) try {
  if (s.values.empty()) { out.set_null(); return; }
  const double p = s.trim_pct;
  if (std::isnan(p) || p < 0.0 || p >= 0.5) { out.set_null(); return; }
  std::sort(s.values.begin(), s.values.end());
  const size_t n = s.values.size();
  const size_t k = static_cast<size_t>(std::floor(p * static_cast<double>(n)));
  if (2 * k >= n) { out.set_null(); return; }
  const double lo = s.values[k];
  const double hi = s.values[n - 1 - k];
  double sum = static_cast<double>(k) * lo;
  for (size_t i = k; i < n - k; ++i) sum += s.values[i];
  sum += static_cast<double>(k) * hi;
  out.set(sum / static_cast<double>(n));
} catch (...) { out.error("STATS_MEAN_WINSORIZED: unexpected error"); }

template<auto ResultFn>
static constexpr auto make_mean_trim_func(const char *name) {
  return vsql::make_aggregate_func<MeanTrimState, ResultFn>(name)
    .returns(vsql::REAL)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .template clear<&mean_trim_clear>()
    .template accumulate<&mean_trim_accumulate>()
    .build();
}

struct MeanGeoState {
  size_t n = 0;
  double sum_log = 0.0; // Σ ln(xi) for positive values only
};

static void mean_geo_clear(MeanGeoState &s) { s = MeanGeoState{}; }

static void mean_geo_accumulate(MeanGeoState &s, RealArg v) {
  if (v.is_null() || std::isnan(v.value())) return;
  const double x = v.value();
  if (!(x > 0.0)) return;
  s.n++;
  s.sum_log += std::log(x);
}

static void stats_mean_geometric_result(const MeanGeoState &s, RealResult out) try {
  if (s.n == 0) { out.set_null(); return; }
  out.set(std::exp(s.sum_log / static_cast<double>(s.n)));
} catch (...) { out.error("STATS_MEAN_GEOMETRIC: unexpected error"); }

template<auto ResultFn>
static constexpr auto make_mean_geo_func(const char *name) {
  return vsql::make_aggregate_func<MeanGeoState, ResultFn>(name)
    .returns(vsql::REAL)
    .param(vsql::REAL)
    .template clear<&mean_geo_clear>()
    .template accumulate<&mean_geo_accumulate>()
    .build();
}

struct MeanHarmState {
  size_t n = 0;
  double sum_recip = 0.0; // Σ(1/xi) for positive values only
};

static void mean_harm_clear(MeanHarmState &s) { s = MeanHarmState{}; }

static void mean_harm_accumulate(MeanHarmState &s, RealArg v) {
  if (v.is_null() || std::isnan(v.value())) return;
  const double x = v.value();
  if (!(x > 0.0)) return;
  s.n++;
  s.sum_recip += 1.0 / x;
}

static void stats_mean_harmonic_result(const MeanHarmState &s, RealResult out) try {
  if (s.n == 0) { out.set_null(); return; }
  out.set(static_cast<double>(s.n) / s.sum_recip);
} catch (...) { out.error("STATS_MEAN_HARMONIC: unexpected error"); }

template<auto ResultFn>
static constexpr auto make_mean_harm_func(const char *name) {
  return vsql::make_aggregate_func<MeanHarmState, ResultFn>(name)
    .returns(vsql::REAL)
    .param(vsql::REAL)
    .template clear<&mean_harm_clear>()
    .template accumulate<&mean_harm_accumulate>()
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
};

static void anova_clear(AnovaState &s) { s.groups.clear(); }

static void anova_accumulate(AnovaState &s, RealArg value, RealArg group) {
  if (value.is_null() || group.is_null()) return;
  const double v = value.value();
  const double g = group.value();
  if (std::isnan(v) || std::isnan(g)) return;
  auto &gs = s.groups[g];
  gs.n++;
  gs.sum += v;
  const double delta = v - gs.mean;
  gs.mean += delta / static_cast<double>(gs.n);
  gs.ss += delta * (v - gs.mean);
}

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
// Spec requires k ≥ 3 for valid one-way ANOVA; k = 2 is mathematically
// equivalent to a t-test — use STATS_TTEST_T for two-group comparisons.
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

static void stats_anova_f_result(const AnovaState &s, RealResult out) try {
  const auto r = compute_anova(s);
  if (!r) { out.set_null(); return; }
  out.set(r->f);
} catch (...) { out.error("STATS_ANOVA_F: unexpected error"); }

// P(F_{dfB,dfW} > F) = I_{dfW/(dfW + dfB·F)}(dfW/2, dfB/2)
static void stats_anova_p_result(const AnovaState &s, RealResult out) try {
  const auto r = compute_anova(s);
  if (!r) { out.set_null(); return; }
  const double x = r->df_w / (r->df_w + r->df_b * r->f);
  out.set(betai(x, r->df_w / 2.0, r->df_b / 2.0));
} catch (...) { out.error("STATS_ANOVA_P: unexpected error"); }

static void stats_anova_ssb_result(const AnovaState &s, RealResult out) try {
  const auto r = compute_anova(s);
  if (!r) { out.set_null(); return; }
  out.set(r->ssb);
} catch (...) { out.error("STATS_ANOVA_SSB: unexpected error"); }

static void stats_anova_ssw_result(const AnovaState &s, RealResult out) try {
  const auto r = compute_anova(s);
  if (!r) { out.set_null(); return; }
  out.set(r->ssw);
} catch (...) { out.error("STATS_ANOVA_SSW: unexpected error"); }

static void stats_anova_sst_result(const AnovaState &s, RealResult out) try {
  const auto r = compute_anova(s);
  if (!r) { out.set_null(); return; }
  out.set(r->sst);
} catch (...) { out.error("STATS_ANOVA_SST: unexpected error"); }

static void stats_anova_msb_result(const AnovaState &s, RealResult out) try {
  const auto r = compute_anova(s);
  if (!r) { out.set_null(); return; }
  out.set(r->msb);
} catch (...) { out.error("STATS_ANOVA_MSB: unexpected error"); }

static void stats_anova_msw_result(const AnovaState &s, RealResult out) try {
  const auto r = compute_anova(s);
  if (!r) { out.set_null(); return; }
  out.set(r->msw);
} catch (...) { out.error("STATS_ANOVA_MSW: unexpected error"); }

static void stats_anova_dfb_result(const AnovaState &s, RealResult out) try {
  const auto r = compute_anova(s);
  if (!r) { out.set_null(); return; }
  out.set(r->df_b);
} catch (...) { out.error("STATS_ANOVA_DFB: unexpected error"); }

static void stats_anova_dfw_result(const AnovaState &s, RealResult out) try {
  const auto r = compute_anova(s);
  if (!r) { out.set_null(); return; }
  out.set(r->df_w);
} catch (...) { out.error("STATS_ANOVA_DFW: unexpected error"); }

template<auto ResultFn>
static constexpr auto make_anova_func(const char *name) {
  return vsql::make_aggregate_func<AnovaState, ResultFn>(name)
    .returns(vsql::REAL)
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
    .func(make_stats_func<&stats_iqr_result>("STATS_IQR"))
    .func(make_stats_func<&stats_q1_result>("STATS_Q1"))
    .func(make_stats_func<&stats_q3_result>("STATS_Q3"))
    .func(make_stats_func<&stats_median_result>("STATS_MEDIAN"))
    .func(make_stats_func<&stats_iqr_lower_fence_result>("STATS_IQR_LOWER_FENCE"))
    .func(make_stats_func<&stats_iqr_upper_fence_result>("STATS_IQR_UPPER_FENCE"))
    .func(make_ttest_func("STATS_TTEST"))
    .func(make_ttest_groups_func("STATS_TTEST_GROUPS"))
    .func(make_mode_str_func<&stats_mode_result>("STATS_MODE"))
    .func(make_mode_real_func<&stats_mode_min_result>("STATS_MODE_MIN"))
    .func(make_mode_real_func<&stats_mode_max_result>("STATS_MODE_MAX"))
    .func(make_skewness_json_func("STATS_SKEWNESS"))
    .func(make_ztest_func<&stats_ztest_z_result>("STATS_ZTEST_Z"))
    .func(make_ztest_func<&stats_ztest_p_one_tail_result>("STATS_ZTEST_P_ONE_TAIL"))
    .func(make_ztest_func<&stats_ztest_p_two_tail_result>("STATS_ZTEST_P_TWO_TAIL"))
    .func(make_chisq_gof_json_func("STATS_CHISQ_GOF"))
    .func(make_chisq_indep_json_func("STATS_CHISQ_INDEP"))
    .func(make_kurtosis_json_func("STATS_KURTOSIS"))
    .func(make_cov_func<&stats_cov_pop_result>("STATS_COVARIANCE_POP"))
    .func(make_cov_func<&stats_cov_samp_result>("STATS_COVARIANCE_SAMP"))
    .func(make_mean_trim_func<&stats_mean_trimmed_result>("STATS_MEAN_TRIMMED"))
    .func(make_mean_trim_func<&stats_mean_winsorized_result>("STATS_MEAN_WINSORIZED"))
    .func(make_mean_geo_func<&stats_mean_geometric_result>("STATS_MEAN_GEOMETRIC"))
    .func(make_mean_harm_func<&stats_mean_harmonic_result>("STATS_MEAN_HARMONIC"))
    .func(make_anova_func<&stats_anova_f_result>("STATS_ANOVA_F"))
    .func(make_anova_func<&stats_anova_p_result>("STATS_ANOVA_P"))
    .func(make_anova_func<&stats_anova_ssb_result>("STATS_ANOVA_SSB"))
    .func(make_anova_func<&stats_anova_ssw_result>("STATS_ANOVA_SSW"))
    .func(make_anova_func<&stats_anova_sst_result>("STATS_ANOVA_SST"))
    .func(make_anova_func<&stats_anova_msb_result>("STATS_ANOVA_MSB"))
    .func(make_anova_func<&stats_anova_msw_result>("STATS_ANOVA_MSW"))
    .func(make_anova_func<&stats_anova_dfb_result>("STATS_ANOVA_DFB"))
    .func(make_anova_func<&stats_anova_dfw_result>("STATS_ANOVA_DFW"))
)
