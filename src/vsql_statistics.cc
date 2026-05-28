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
#include <vector>

using vsql::RealArg;
using vsql::RealResult;

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
static bool compute_quartiles(std::vector<double> vals, double &q1, double &q3) {
  if (vals.empty()) return false;
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

VEF_GENERATE_ENTRY_POINTS(
  vsql::make_extension()
    .func(make_stats_func<&stats_iqr_result>("STATS_IQR"))
    .func(make_stats_func<&stats_q1_result>("STATS_Q1"))
    .func(make_stats_func<&stats_q3_result>("STATS_Q3"))
    .func(make_stats_func<&stats_median_result>("STATS_MEDIAN"))
    .func(make_stats_func<&stats_iqr_lower_fence_result>("STATS_IQR_LOWER_FENCE"))
    .func(make_stats_func<&stats_iqr_upper_fence_result>("STATS_IQR_UPPER_FENCE"))
)
