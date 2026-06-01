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
#include <unordered_map>
#include <vector>

using vsql::RealArg;
using vsql::RealResult;
using vsql::StringResult;

// =============================================================================
// IQR family
// =============================================================================

struct StatsState {
  std::vector<double> values;
};

static void stats_clear(StatsState &s) {
  s.values.clear();
}

static void stats_accumulate(StatsState &s, RealArg v) {
  if (!v.is_null()) s.values.push_back(v.value());
}

// Median of a sorted sub-range [lo, hi).
static double range_median(const std::vector<double> &v, size_t lo, size_t hi) {
  assert(lo < hi);
  size_t n = hi - lo;
  size_t mid = lo + n / 2;
  return (n % 2 == 1) ? v[mid] : (v[mid - 1] + v[mid]) / 2.0;
}

// Sorts values and computes Q1, Q3 using Tukey's hinges (exclusive median).
// Returns false if the group is empty (all-NULL input).
static bool compute_quartiles(const std::vector<double> &vals_in, double &q1, double &q3) {
  if (vals_in.empty()) return false;
  std::vector<double> vals(vals_in);
  std::sort(vals.begin(), vals.end());
  size_t n = vals.size();
  if (n == 1) {
    q1 = q3 = vals[0];
    return true;
  }
  size_t lower_end = n / 2;
  size_t upper_start = (n % 2 == 1) ? lower_end + 1 : lower_end;
  q1 = range_median(vals, 0, lower_end);
  q3 = range_median(vals, upper_start, n);
  return true;
}

static void stats_iqr_result(const StatsState &s, RealResult out) try {
  double q1, q3;
  if (!compute_quartiles(s.values, q1, q3)) { out.set_null(); return; }
  out.set(q3 - q1);
} catch (...) { out.error("STATS_IQR: unexpected error"); }

static void stats_q1_result(const StatsState &s, RealResult out) try {
  double q1, q3;
  if (!compute_quartiles(s.values, q1, q3)) { out.set_null(); return; }
  out.set(q1);
} catch (...) { out.error("STATS_Q1: unexpected error"); }

static void stats_q3_result(const StatsState &s, RealResult out) try {
  double q1, q3;
  if (!compute_quartiles(s.values, q1, q3)) { out.set_null(); return; }
  out.set(q3);
} catch (...) { out.error("STATS_Q3: unexpected error"); }

static void stats_median_result(const StatsState &s, RealResult out) try {
  if (s.values.empty()) { out.set_null(); return; }
  auto vals = s.values;
  std::sort(vals.begin(), vals.end());
  out.set(range_median(vals, 0, vals.size()));
} catch (...) { out.error("STATS_MEDIAN: unexpected error"); }

static void stats_iqr_lower_fence_result(const StatsState &s, RealResult out) try {
  double q1, q3;
  if (!compute_quartiles(s.values, q1, q3)) { out.set_null(); return; }
  out.set(q1 - 1.5 * (q3 - q1));
} catch (...) { out.error("STATS_IQR_LOWER_FENCE: unexpected error"); }

static void stats_iqr_upper_fence_result(const StatsState &s, RealResult out) try {
  double q1, q3;
  if (!compute_quartiles(s.values, q1, q3)) { out.set_null(); return; }
  out.set(q3 + 1.5 * (q3 - q1));
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
  double g = group.value();
  if (g == 1.0)      s.group1.push_back(value.value());
  else if (g == 2.0) s.group2.push_back(value.value());
}

// Accumulate for 3-parameter functions (value, group, alpha).
static void ttest_crit_accumulate(TTestState &s, RealArg value, RealArg group,
                                   RealArg alpha) {
  ttest_accumulate(s, value, group);
  if (!alpha.is_null()) s.alpha = alpha.value();
}

// Continued fraction core for the regularized incomplete beta function.
// Uses Lentz's algorithm. Precondition: x < (a+1)/(a+b+2).
static double betacf(double x, double a, double b) {
  const int    MAX_ITER = 500;
  const double TINY     = 1e-30;
  const double EPS      = 1e-12;

  double qab = a + b, qap = a + 1.0, qam = a - 1.0;
  double c = 1.0;
  double d = 1.0 - qab * x / qap;
  if (std::fabs(d) < TINY) d = TINY;
  d = 1.0 / d;
  double h = d;

  for (int m = 1; m <= MAX_ITER; m++) {
    int m2 = 2 * m;
    // Even step
    double aa = (double)m * (b - (double)m) * x
                / ((qam + m2) * (a + m2));
    d = 1.0 + aa * d; if (std::fabs(d) < TINY) d = TINY; d = 1.0 / d;
    c = 1.0 + aa / c; if (std::fabs(c) < TINY) c = TINY;
    h *= d * c;
    // Odd step
    aa = -(a + (double)m) * (qab + (double)m) * x
         / ((a + m2) * (qap + m2));
    d = 1.0 + aa * d; if (std::fabs(d) < TINY) d = TINY; d = 1.0 / d;
    c = 1.0 + aa / c; if (std::fabs(c) < TINY) c = TINY;
    double del = d * c;
    h *= del;
    if (std::fabs(del - 1.0) < EPS) break;
  }
  return h;
}

// Regularized incomplete beta function I_x(a, b).
static double betai(double x, double a, double b) {
  if (x <= 0.0) return 0.0;
  if (x >= 1.0) return 1.0;
  // Use symmetry I_x(a,b) = 1 - I_{1-x}(b,a) when x is large for convergence.
  if (x > (a + 1.0) / (a + b + 2.0)) return 1.0 - betai(1.0 - x, b, a);
  double lbeta_ab = std::lgamma(a) + std::lgamma(b) - std::lgamma(a + b);
  double front = std::exp(a * std::log(x) + b * std::log(1.0 - x) - lbeta_ab) / a;
  return front * betacf(x, a, b);
}

// Two-tail p-value: P(|T_df| > |t|) using the incomplete beta function.
static double t_two_tail_p(double t, double df) {
  double x = df / (df + t * t);
  return betai(x, df / 2.0, 0.5);
}

// One-tail critical value: largest t > 0 such that P(T_df > t) >= alpha.
// Uses bisection on t_two_tail_p; 200 iterations gives ~12 significant figures.
static double t_critical(double alpha, double df) {
  double lo = 0.0, hi = 1000.0;
  for (int i = 0; i < 200; i++) {
    double mid = (lo + hi) / 2.0;
    if (t_two_tail_p(mid, df) / 2.0 > alpha) lo = mid;
    else                                       hi = mid;
  }
  return (lo + hi) / 2.0;
}

// Pooled-variance t-test statistics computed once and shared by all result fns.
struct TTestResult {
  double t_stat;
  double df;
  double pooled_var;
};

// Returns false if either group has fewer than 2 observations (df ≤ 0)
// or if pooled variance is zero and means differ (t would be ±inf).
static bool compute_ttest(const TTestState &s, TTestResult &r) {
  size_t n1 = s.group1.size(), n2 = s.group2.size();
  if (n1 < 2 || n2 < 2) return false;

  double sum1 = 0.0, sum2 = 0.0;
  for (double v : s.group1) sum1 += v;
  for (double v : s.group2) sum2 += v;
  double mean1 = sum1 / (double)n1, mean2 = sum2 / (double)n2;

  double ssq1 = 0.0, ssq2 = 0.0;
  for (double v : s.group1) ssq1 += (v - mean1) * (v - mean1);
  for (double v : s.group2) ssq2 += (v - mean2) * (v - mean2);

  double df         = (double)(n1 + n2 - 2);
  double pooled_var = (ssq1 + ssq2) / df;

  if (pooled_var == 0.0) {
    // Both groups have zero variance; t is 0 iff means are equal, else undefined.
    if (mean1 == mean2) { r = {0.0, df, 0.0}; return true; }
    return false;
  }

  double t = (mean1 - mean2) / std::sqrt(pooled_var * (1.0 / (double)n1
                                                      + 1.0 / (double)n2));
  r = {t, df, pooled_var};
  return true;
}

static void ttest_t_result(const TTestState &s, RealResult out) try {
  TTestResult r;
  if (!compute_ttest(s, r)) { out.set_null(); return; }
  out.set(r.t_stat);
} catch (...) { out.error("STATS_TTEST_T: unexpected error"); }

static void ttest_df_result(const TTestState &s, RealResult out) try {
  TTestResult r;
  if (!compute_ttest(s, r)) { out.set_null(); return; }
  out.set(r.df);
} catch (...) { out.error("STATS_TTEST_DF: unexpected error"); }

static void ttest_pooled_var_result(const TTestState &s, RealResult out) try {
  TTestResult r;
  if (!compute_ttest(s, r)) { out.set_null(); return; }
  out.set(r.pooled_var);
} catch (...) { out.error("STATS_TTEST_POOLED_VAR: unexpected error"); }

static void ttest_p_one_tail_result(const TTestState &s, RealResult out) try {
  TTestResult r;
  if (!compute_ttest(s, r)) { out.set_null(); return; }
  out.set(t_two_tail_p(r.t_stat, r.df) / 2.0);
} catch (...) { out.error("STATS_TTEST_P_ONE_TAIL: unexpected error"); }

static void ttest_p_two_tail_result(const TTestState &s, RealResult out) try {
  TTestResult r;
  if (!compute_ttest(s, r)) { out.set_null(); return; }
  out.set(t_two_tail_p(r.t_stat, r.df));
} catch (...) { out.error("STATS_TTEST_P_TWO_TAIL: unexpected error"); }

static void ttest_t_crit_one_tail_result(const TTestState &s, RealResult out) try {
  TTestResult r;
  if (!compute_ttest(s, r)) { out.set_null(); return; }
  out.set(t_critical(s.alpha, r.df));
} catch (...) { out.error("STATS_TTEST_T_CRIT_ONE_TAIL: unexpected error"); }

// Two-tail critical value splits alpha across both tails.
static void ttest_t_crit_two_tail_result(const TTestState &s, RealResult out) try {
  TTestResult r;
  if (!compute_ttest(s, r)) { out.set_null(); return; }
  out.set(t_critical(s.alpha / 2.0, r.df));
} catch (...) { out.error("STATS_TTEST_T_CRIT_TWO_TAIL: unexpected error"); }

template<auto ResultFn>
static constexpr auto make_ttest_func(const char *name) {
  return vsql::make_aggregate_func<TTestState, ResultFn>(name)
    .returns(vsql::REAL)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .template clear<&ttest_clear>()
    .template accumulate<&ttest_accumulate>()
    .build();
}

template<auto ResultFn>
static constexpr auto make_ttest_crit_func(const char *name) {
  return vsql::make_aggregate_func<TTestState, ResultFn>(name)
    .returns(vsql::REAL)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .param(vsql::REAL)
    .template clear<&ttest_clear>()
    .template accumulate<&ttest_crit_accumulate>()
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
  auto modes = compute_modes(s);
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
  for (const auto &kv : s.freq) if (kv.second > max_freq) max_freq = kv.second;
  if (max_freq <= 1) { out.set_null(); return; }
  double result = std::numeric_limits<double>::infinity();
  for (const auto &kv : s.freq) if (kv.second == max_freq) result = std::min(result, kv.first);
  out.set(result);
} catch (...) { out.error("STATS_MODE_MIN: unexpected error"); }

static void stats_mode_max_result(const ModeState &s, RealResult out) try {
  if (s.freq.empty()) { out.set_null(); return; }
  size_t max_freq = 0;
  for (const auto &kv : s.freq) if (kv.second > max_freq) max_freq = kv.second;
  if (max_freq <= 1) { out.set_null(); return; }
  double result = -std::numeric_limits<double>::infinity();
  for (const auto &kv : s.freq) if (kv.second == max_freq) result = std::max(result, kv.first);
  out.set(result);
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

struct SkewState {
  size_t n = 0;
  double ref = 0.0;  // first observed value; centering reduces floating-point cancellation
  double sum = 0.0;
  double sum_sq = 0.0;
  double sum_cu = 0.0;
};

static void skew_clear(SkewState &s) { s = SkewState{}; }

static void skew_accumulate(SkewState &s, RealArg v) {
  if (v.is_null()) return;
  if (s.n == 0) s.ref = v.value();
  double x = v.value() - s.ref;
  double x2 = x * x;
  s.n++;
  s.sum += x;
  s.sum_sq += x2;
  s.sum_cu += x2 * x;
}

// Population skewness: third standardized moment g₁ = m₃ / m₂^(3/2).
// Uses the expanded-moment identities to avoid storing individual values.
static void stats_skewness_result(const SkewState &s, RealResult out) try {
  if (s.n < 2) { out.set_null(); return; }
  double mean = s.sum / (double)s.n;
  double m2 = s.sum_sq / (double)s.n - mean * mean;
  if (m2 <= 0.0) { out.set_null(); return; }
  double m3 = s.sum_cu / (double)s.n
              - 3.0 * mean * s.sum_sq / (double)s.n
              + 2.0 * mean * mean * mean;
  out.set(m3 / std::pow(m2, 1.5));
} catch (...) { out.error("STATS_SKEWNESS: unexpected error"); }

// Pearson's median skewness: 3 × (mean − median) / population_stddev.
// Requires value storage for median; reuses StatsState/stats_accumulate.
static void stats_skewness_pearson_result(const StatsState &s, RealResult out) try {
  size_t n = s.values.size();
  if (n < 2) { out.set_null(); return; }
  double mean = std::accumulate(s.values.begin(), s.values.end(), 0.0) / (double)n;
  double variance = 0.0;
  for (double v : s.values) variance += (v - mean) * (v - mean);
  variance /= (double)n;
  double stddev = std::sqrt(variance);
  if (stddev == 0.0) { out.set_null(); return; }
  auto vals = s.values;
  std::sort(vals.begin(), vals.end());
  out.set(3.0 * (mean - range_median(vals, 0, n)) / stddev);
} catch (...) { out.error("STATS_SKEWNESS_PEARSON: unexpected error"); }

template<auto ResultFn>
static constexpr auto make_moment_skew_func(const char *name) {
  return vsql::make_aggregate_func<SkewState, ResultFn>(name)
    .returns(vsql::REAL)
    .param(vsql::REAL)
    .template clear<&skew_clear>()
    .template accumulate<&skew_accumulate>()
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
  if (!mu.is_null())    s.mu    = mu.value();
  if (!sigma.is_null()) s.sigma = sigma.value();
  if (value.is_null()) return;
  s.n++;
  s.sum += value.value();
}

// Returns NULL when sigma was never set (0.0), is non-positive, or NaN.
static bool compute_ztest(const ZTestState &s, double &z) {
  if (s.n == 0 || !(s.sigma > 0.0)) return false;
  double mean = s.sum / (double)s.n;
  z = (mean - s.mu) / (s.sigma / std::sqrt((double)s.n));
  return true;
}

static void stats_ztest_z_result(const ZTestState &s, RealResult out) try {
  double z = 0.0;
  if (!compute_ztest(s, z)) { out.set_null(); return; }
  out.set(z);
} catch (...) { out.error("STATS_ZTEST_Z: unexpected error"); }

// Upper-tail probability: P(Z > z) = 0.5 × erfc(z/√2).
// Returns values in (0.5, 1] when z < 0 (sample mean below μ).
static void stats_ztest_p_one_tail_result(const ZTestState &s, RealResult out) try {
  double z = 0.0;
  if (!compute_ztest(s, z)) { out.set_null(); return; }
  out.set(0.5 * std::erfc(z / std::sqrt(2.0)));
} catch (...) { out.error("STATS_ZTEST_P_ONE_TAIL: unexpected error"); }

static void stats_ztest_p_two_tail_result(const ZTestState &s, RealResult out) try {
  double z = 0.0;
  if (!compute_ztest(s, z)) { out.set_null(); return; }
  out.set(std::erfc(std::fabs(z) / std::sqrt(2.0)));
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
  const int    MAX_ITER = 500;
  const double EPS      = 1e-12;

  double ap  = a;
  double del = 1.0 / a;
  double sum = del;
  for (int i = 0; i < MAX_ITER; i++) {
    ap  += 1.0;
    del *= x / ap;
    sum += del;
    if (std::fabs(del) < std::fabs(sum) * EPS) break;
  }
  return sum * gamma_prefix(a, x);
}

// Continued fraction representation of the upper incomplete gamma Q(a, x) = Γ(a,x)/Γ(a).
// Converges for x >= a+1. Uses Lentz's algorithm.
static double gammacf(double a, double x) {
  const int    MAX_ITER = 500;
  const double TINY     = 1e-30;
  const double EPS      = 1e-12;

  double b = x + 1.0 - a;
  double c = 1.0 / TINY;
  double d = 1.0 / b;
  double h = d;
  for (int i = 1; i <= MAX_ITER; i++) {
    double an = -(double)i * ((double)i - a);
    b += 2.0;
    d = an * d + b; if (std::fabs(d) < TINY) d = TINY; d = 1.0 / d;
    c = b + an / c; if (std::fabs(c) < TINY) c = TINY;
    double del = d * c;
    h *= del;
    if (std::fabs(del - 1.0) < EPS) break;
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
  double e = expected.value();
  if (!(e > 0.0)) return;
  double diff = observed.value() - e;
  chi_sq += (diff * diff) / e;
  k++;
}

static void chisq_gof_accumulate(ChiSqGofState &s, RealArg observed, RealArg expected) {
  chisq_accumulate_cell(s.chi_sq, s.k, observed, expected);
}

static void stats_chisq_gof_result(const ChiSqGofState &s, RealResult out) try {
  if (s.k == 0) { out.set_null(); return; }
  out.set(s.chi_sq);
} catch (...) { out.error("STATS_CHISQ_GOF: unexpected error"); }

static void stats_chisq_gof_df_result(const ChiSqGofState &s, RealResult out) try {
  if (s.k == 0) { out.set_null(); return; }
  out.set((double)(s.k - 1));
} catch (...) { out.error("STATS_CHISQ_GOF_DF: unexpected error"); }

// P(χ²_{k-1} > stat); returns NULL when df = 0 (k = 1).
static void stats_chisq_gof_p_result(const ChiSqGofState &s, RealResult out) try {
  if (s.k == 0 || s.k == 1) { out.set_null(); return; }
  double df = (double)(s.k - 1);
  out.set(gammaq(df / 2.0, s.chi_sq / 2.0));
} catch (...) { out.error("STATS_CHISQ_GOF_P: unexpected error"); }

template<auto ResultFn>
static constexpr auto make_chisq_gof_func(const char *name) {
  return vsql::make_aggregate_func<ChiSqGofState, ResultFn>(name)
    .returns(vsql::REAL)
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
  if (!n_rows.is_null()) s.n_rows = n_rows.value();
  if (!n_cols.is_null()) s.n_cols = n_cols.value();
  chisq_accumulate_cell(s.chi_sq, s.k, observed, expected);
}

// STATS_CHISQ_INDEP uses ChiSqGofState (same formula as GoF, no n_rows/n_cols needed).
static void stats_chisq_indep_result(const ChiSqGofState &s, RealResult out) try {
  if (s.k == 0) { out.set_null(); return; }
  out.set(s.chi_sq);
} catch (...) { out.error("STATS_CHISQ_INDEP: unexpected error"); }

// P(χ²_{(r-1)(c-1)} > stat); returns NULL when no valid data, dimensions are
// non-positive/NaN, or df <= 0.
static void stats_chisq_indep_p_result(const ChiSqIndepState &s, RealResult out) try {
  if (s.k == 0) { out.set_null(); return; }
  if (!(s.n_rows > 0.0) || !(s.n_cols > 0.0)) { out.set_null(); return; }
  double df = (std::floor(s.n_rows) - 1.0) * (std::floor(s.n_cols) - 1.0);
  if (!(df > 0.0)) { out.set_null(); return; }
  out.set(gammaq(df / 2.0, s.chi_sq / 2.0));
} catch (...) { out.error("STATS_CHISQ_INDEP_P: unexpected error"); }

template<auto ResultFn>
static constexpr auto make_chisq_indep_func(const char *name) {
  return vsql::make_aggregate_func<ChiSqIndepState, ResultFn>(name)
    .returns(vsql::REAL)
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
  if (v.is_null()) return;
  if (s.n == 0) s.ref = v.value();
  double d = v.value() - s.ref;
  double d2 = d * d;
  s.n++;
  s.sum1 += d;
  s.sum2 += d2;
  s.sum3 += d2 * d;
  s.sum4 += d2 * d2;
}

// Derives Σ(xi−mean)² and Σ(xi−mean)⁴ from the shifted accumulators.
// Returns false when fewer than 2 values or all values are equal (zero variance).
static bool compute_kurt_moments(const KurtState &s, double &ssq2, double &ssq4) {
  double c  = s.sum1 / (double)s.n;
  double c2 = c * c;
  double n  = (double)s.n;
  ssq2 = s.sum2 - n * c2;
  ssq4 = s.sum4 - 4.0*c*s.sum3 + 6.0*c2*s.sum2 - 3.0*n*c2*c2;
  return ssq2 > 0.0;
}

// Population kurtosis β₂ = μ₄/m₂² where μ₄ = Σ(xi−μ)⁴/n, m₂ = Σ(xi−μ)²/n.
// Returns NULL for n < 2 or zero variance.
static void stats_kurtosis_result(const KurtState &s, RealResult out) try {
  if (s.n < 2) { out.set_null(); return; }
  double ssq2, ssq4;
  if (!compute_kurt_moments(s, ssq2, ssq4)) { out.set_null(); return; }
  out.set(ssq4 * (double)s.n / (ssq2 * ssq2));
} catch (...) { out.error("STATS_KURTOSIS: unexpected error"); }

// Fisher-Pearson sample excess kurtosis g₂ (unbiased estimator):
// g₂ = [n(n+1)/((n−1)(n−2)(n−3))] × Σ[(xi−x̄)⁴/s⁴] − [3(n−1)²/((n−2)(n−3))]
// Equivalently: g₂ = (n−1)/((n−2)(n−3)) × [n(n+1)·Σ(xi−x̄)⁴/Σ(xi−x̄)² − 3(n−1)]
// Returns NULL for n < 4 or zero variance.
static void stats_kurtosis_excess_result(const KurtState &s, RealResult out) try {
  if (s.n < 4) { out.set_null(); return; }
  double ssq2, ssq4;
  if (!compute_kurt_moments(s, ssq2, ssq4)) { out.set_null(); return; }
  double n  = (double)s.n;
  double a  = (n - 1.0) / ((n - 2.0) * (n - 3.0));
  out.set(a * (n * (n + 1.0) * ssq4 / (ssq2 * ssq2) - 3.0 * (n - 1.0)));
} catch (...) { out.error("STATS_KURTOSIS_EXCESS: unexpected error"); }

template<auto ResultFn>
static constexpr auto make_kurt_func(const char *name) {
  return vsql::make_aggregate_func<KurtState, ResultFn>(name)
    .returns(vsql::REAL)
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
  double xv = x.value(), yv = y.value();
  s.n++;
  double dx = xv - s.mean_x;
  s.mean_x += dx / (double)s.n;
  s.mean_y += (yv - s.mean_y) / (double)s.n;
  s.C += dx * (yv - s.mean_y);  // uses updated mean_y — Welford's co-moment form
}

// Population covariance σ_xy = C/n. N=1 yields 0.0; N=0 yields NULL.
static void stats_cov_pop_result(const CovState &s, RealResult out) try {
  if (s.n == 0) { out.set_null(); return; }
  out.set(s.C / (double)s.n);
} catch (...) { out.error("STATS_COVARIANCE_POP: unexpected error"); }

// Sample covariance s_xy = C/(n−1). Returns NULL for n < 2.
static void stats_cov_samp_result(const CovState &s, RealResult out) try {
  if (s.n < 2) { out.set_null(); return; }
  out.set(s.C / (double)(s.n - 1));
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
  std::vector<double> values;
  double trim_pct = 0.0; // fraction to trim/winsorize from each end (last non-null wins)
};

static void mean_trim_clear(MeanTrimState &s) { s = MeanTrimState{}; }

static void mean_trim_accumulate(MeanTrimState &s, RealArg v, RealArg trim_pct) {
  if (!trim_pct.is_null()) s.trim_pct = trim_pct.value();
  if (!v.is_null()) s.values.push_back(v.value());
}

static void stats_mean_trimmed_result(const MeanTrimState &s, RealResult out) try {
  if (s.values.empty()) { out.set_null(); return; }
  double p = s.trim_pct;
  if (!(p >= 0.0)) { out.set_null(); return; }
  auto vals = s.values;
  std::sort(vals.begin(), vals.end());
  size_t n = vals.size();
  size_t k = (size_t)std::floor(p * (double)n);
  if (2 * k >= n) { out.set_null(); return; }
  double sum = 0.0;
  for (size_t i = k; i < n - k; ++i) sum += vals[i];
  out.set(sum / (double)(n - 2 * k));
} catch (...) { out.error("STATS_MEAN_TRIMMED: unexpected error"); }

static void stats_mean_winsorized_result(const MeanTrimState &s, RealResult out) try {
  if (s.values.empty()) { out.set_null(); return; }
  double p = s.trim_pct;
  if (!(p >= 0.0)) { out.set_null(); return; }
  auto vals = s.values;
  std::sort(vals.begin(), vals.end());
  size_t n = vals.size();
  size_t k = (size_t)std::floor(p * (double)n);
  if (2 * k >= n) { out.set_null(); return; }
  double lo = vals[k];
  double hi = vals[n - 1 - k];
  double sum = (double)k * lo;
  for (size_t i = k; i < n - k; ++i) sum += vals[i];
  sum += (double)k * hi;
  out.set(sum / (double)n);
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
  if (v.is_null()) return;
  double x = v.value();
  if (!(x > 0.0)) return;
  s.n++;
  s.sum_log += std::log(x);
}

static void stats_mean_geometric_result(const MeanGeoState &s, RealResult out) try {
  if (s.n == 0) { out.set_null(); return; }
  out.set(std::exp(s.sum_log / (double)s.n));
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
  if (v.is_null()) return;
  double x = v.value();
  if (!(x > 0.0)) return;
  s.n++;
  s.sum_recip += 1.0 / x;
}

static void stats_mean_harmonic_result(const MeanHarmState &s, RealResult out) try {
  if (s.n == 0) { out.set_null(); return; }
  out.set((double)s.n / s.sum_recip);
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
    .func(make_ttest_func<&ttest_t_result>("STATS_TTEST_T"))
    .func(make_ttest_func<&ttest_df_result>("STATS_TTEST_DF"))
    .func(make_ttest_func<&ttest_pooled_var_result>("STATS_TTEST_POOLED_VAR"))
    .func(make_ttest_func<&ttest_p_one_tail_result>("STATS_TTEST_P_ONE_TAIL"))
    .func(make_ttest_func<&ttest_p_two_tail_result>("STATS_TTEST_P_TWO_TAIL"))
    .func(make_ttest_crit_func<&ttest_t_crit_one_tail_result>("STATS_TTEST_T_CRIT_ONE_TAIL"))
    .func(make_ttest_crit_func<&ttest_t_crit_two_tail_result>("STATS_TTEST_T_CRIT_TWO_TAIL"))
    .func(make_mode_str_func<&stats_mode_result>("STATS_MODE"))
    .func(make_mode_real_func<&stats_mode_min_result>("STATS_MODE_MIN"))
    .func(make_mode_real_func<&stats_mode_max_result>("STATS_MODE_MAX"))
    .func(make_moment_skew_func<&stats_skewness_result>("STATS_SKEWNESS"))
    .func(make_stats_func<&stats_skewness_pearson_result>("STATS_SKEWNESS_PEARSON"))
    .func(make_ztest_func<&stats_ztest_z_result>("STATS_ZTEST_Z"))
    .func(make_ztest_func<&stats_ztest_p_one_tail_result>("STATS_ZTEST_P_ONE_TAIL"))
    .func(make_ztest_func<&stats_ztest_p_two_tail_result>("STATS_ZTEST_P_TWO_TAIL"))
    .func(make_chisq_gof_func<&stats_chisq_gof_result>("STATS_CHISQ_GOF"))
    .func(make_chisq_gof_func<&stats_chisq_gof_df_result>("STATS_CHISQ_GOF_DF"))
    .func(make_chisq_gof_func<&stats_chisq_gof_p_result>("STATS_CHISQ_GOF_P"))
    .func(make_chisq_gof_func<&stats_chisq_indep_result>("STATS_CHISQ_INDEP"))
    .func(make_chisq_indep_func<&stats_chisq_indep_p_result>("STATS_CHISQ_INDEP_P"))
    .func(make_kurt_func<&stats_kurtosis_result>("STATS_KURTOSIS"))
    .func(make_kurt_func<&stats_kurtosis_excess_result>("STATS_KURTOSIS_EXCESS"))
    .func(make_cov_func<&stats_cov_pop_result>("STATS_COVARIANCE_POP"))
    .func(make_cov_func<&stats_cov_samp_result>("STATS_COVARIANCE_SAMP"))
    .func(make_mean_trim_func<&stats_mean_trimmed_result>("STATS_MEAN_TRIMMED"))
    .func(make_mean_trim_func<&stats_mean_winsorized_result>("STATS_MEAN_WINSORIZED"))
    .func(make_mean_geo_func<&stats_mean_geometric_result>("STATS_MEAN_GEOMETRIC"))
    .func(make_mean_harm_func<&stats_mean_harmonic_result>("STATS_MEAN_HARMONIC"))
)
