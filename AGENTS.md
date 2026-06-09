# AGENTS.md

This file provides guidance to AI coding assistants when working with code in this repository.

**Note**: Also check `AGENTS.local.md` for additional local development instructions when present.

## Project Overview

`vsql-statistics` is a VillageSQL extension that provides statistical aggregate functions for data scientists. It implements two families of functions:

- **IQR family (6 functions):** `STATS_IQR`, `STATS_Q1`, `STATS_Q3`, `STATS_MEDIAN`, `STATS_IQR_LOWER_FENCE`, `STATS_IQR_UPPER_FENCE`
- **Two-sample t-test family (2 JSON functions):** `STATS_TTEST`, `STATS_TTEST_GROUPS`
- **Mode family (3 functions):** `STATS_MODE`, `STATS_MODE_MIN`, `STATS_MODE_MAX`
- **Skewness family (1 JSON function):** `STATS_SKEWNESS`
- **Z-test family (3 functions):** `STATS_ZTEST_Z`, `STATS_ZTEST_P_ONE_TAIL`, `STATS_ZTEST_P_TWO_TAIL`
- **Chi-squared family (2 JSON functions):** `STATS_CHISQ_GOF`, `STATS_CHISQ_INDEP`
- **Kurtosis family (2 functions):** `STATS_KURTOSIS`, `STATS_KURTOSIS_EXCESS`
- **Covariance family (2 functions):** `STATS_COVARIANCE_POP`, `STATS_COVARIANCE_SAMP`
- **Means family — beta (4 functions):** `STATS_MEAN_TRIMMED`, `STATS_MEAN_WINSORIZED`, `STATS_MEAN_GEOMETRIC`, `STATS_MEAN_HARMONIC`

All functions operate on `DOUBLE` columns and are usable with `GROUP BY`, mirroring statistical primitives found in Python (numpy/scipy) and R.

Install name (underscored): `vsql_statistics`
Repo/directory name (hyphenated): `vsql-statistics`

## Build System

Set `VillageSQL_BUILD_DIR` to the directory containing the extracted SDK (e.g., `~/.villagesql`):

```bash
VillageSQL_BUILD_DIR=~/.villagesql bash build.sh
```

The `build.sh` script runs cmake and cmake --build. The `.veb` bundle is created at `build/vsql_statistics.veb` and installed to `VillageSQL_VEB_INSTALL_DIR` (auto-detected from the server's `veb_dir`).

## Architecture

**Extension type:** Pure VDF — no custom types.

**Shared accumulation state:**
```cpp
struct StatsState {
    std::vector<double> values;
};
```
The IQR family (6 functions) shares one `StatsState` with a single `values` vector, a shared `clear()` and `accumulate()`. Each function has its own `result()` that sorts and computes the statistic.

The t-test family (2 JSON functions) uses `TTestState` with separate `group1`/`group2` vectors and a stored `alpha`. Group membership is passed as the second argument (1 = group 1, 2 = group 2). `STATS_TTEST(value, group, alpha)` returns a JSON STRING with `{pooled_var, df, t, p_one_tail, t_crit_one_tail, p_two_tail, t_crit_two_tail}`; `STATS_TTEST_GROUPS(value, group)` returns `{mean_1, mean_2, variance_1, variance_2, n_1, n_2}`.

The mode family (3 functions) uses `ModeState` with `std::unordered_map<double, size_t>` for frequency counting. `STATS_MODE` returns a JSON STRING; `STATS_MODE_MIN` and `STATS_MODE_MAX` return REAL. All three return NULL when no value appears more than once. NaN inputs are skipped alongside NULLs.

The skewness family (1 JSON function) uses `StatsState` (vector of doubles). `STATS_SKEWNESS(col)` returns a JSON STRING `{"moment": ..., "pearson": ...}` where `moment` is the population skewness g₁ = m₃/m₂^(3/2) and `pearson` is 3×(mean−median)/σ. Both fields are `null` when variance is zero. The function returns NULL when n < 2. Use `CAST(... AS CHAR)` and `JSON_EXTRACT` to access individual fields.

The z-test family (3 functions) uses `ZTestState` — streaming accumulator of n and Σx, plus stored `mu` and `sigma` constants (last non-null wins per row; sigma defaults to 0.0 so all-null sigma returns NULL). `STATS_ZTEST_P_ONE_TAIL` returns the upper-tail probability P(Z > z), which is > 0.5 when the sample mean is below μ. All three return NULL when n=0, sigma≤0, or sigma is NaN.

The kurtosis family (2 functions) uses `KurtState` — a streaming accumulator of n, Σ(xi−ref), Σ(xi−ref)², Σ(xi−ref)³, Σ(xi−ref)⁴ (shifted by the first observed value for numerical stability). `STATS_KURTOSIS` returns the population kurtosis β₂ = Σ(xi−μ)⁴/n / (Σ(xi−μ)²/n)² and requires n ≥ 2. `STATS_KURTOSIS_EXCESS` returns the Fisher-Pearson unbiased sample excess kurtosis g₂ and requires n ≥ 4 (the denominator contains (n−2)(n−3)). Both return NULL for zero variance (all values equal). A normal distribution has β₂ = 3 and g₂ = 0.

The means family (4 functions — beta) uses three states. `MeanTrimState` (vector + trim_pct) serves both `STATS_MEAN_TRIMMED` and `STATS_MEAN_WINSORIZED` (2-param functions). `MeanGeoState` (n, sum_log) is a streaming accumulator for `STATS_MEAN_GEOMETRIC`: accumulates Σln(xi) for positive values, then returns exp(sum_log/n). `MeanHarmState` (n, sum_recip) is a streaming accumulator for `STATS_MEAN_HARMONIC`: accumulates Σ(1/xi) for positive values, then returns n/sum_recip. Non-positive inputs are silently skipped for both geometric and harmonic.

The chi-squared family (2 JSON functions) uses two states. `ChiSqGofState` (chi_sq, k) serves `STATS_CHISQ_GOF(observed, expected)`, which returns a JSON STRING `{chi_sq, df, p}` where df = k−1 and p is null when df = 0. `ChiSqIndepState` (chi_sq, k, n_rows, n_cols) serves `STATS_CHISQ_INDEP(observed, expected, n_rows, n_cols)`, which returns `{chi_sq, df, p}` where df = (n_rows−1)(n_cols−1); df and p are null when dimensions are missing or df ≤ 0. The p-value is the regularized upper incomplete gamma Q(df/2, χ²/2); computed via series expansion (x < a+1) or Lentz's continued fraction (x ≥ a+1). Rows where expected ≤ 0 are skipped. Both functions return NULL when no valid (O, E) pairs exist. Use `CAST(... AS CHAR)` to read results in the mysql CLI.

The covariance family (2 functions) uses `CovState` — a streaming accumulator of n, mean_x, mean_y, and C (Welford's co-moment). Each row passes two REAL arguments (x, y); a row is skipped if either is NULL (concurrent-pair discard). `STATS_COVARIANCE_POP` returns C/n (0.0 for n=1, NULL for n=0). `STATS_COVARIANCE_SAMP` returns C/(n−1) (NULL for n < 2).

**Quartile algorithm:** Tukey's hinges (exclusive median). For a sorted vector of n values:
- Lower half: indices [0, n/2)
- Upper half: indices [n/2+1, n) for odd n, [n/2, n) for even n
- Q1 = median of lower half, Q3 = median of upper half
- NULL inputs are skipped; all-NULL group returns NULL
- n=1: Q1=Q3=value, IQR=0

**Function registration:** `make_aggregate_func<StatsState, &result_fn>(name).returns(REAL).param(REAL).clear<&stats_clear>().accumulate<&stats_accumulate>().build()`

**Key files:**
- `src/vsql_statistics.cc` — all 32 aggregate functions (6 IQR + 2 t-test + 3 mode + 1 skewness + 3 z-test + 2 chi-squared + 2 kurtosis + 2 covariance + 4 means + 9 ANOVA)
- `manifest.json` — extension metadata
- `CMakeLists.txt` — build configuration
- `cmake/FindVillageSQL.cmake` — SDK discovery
- `mysql-test/t/` — MTR test files
- `mysql-test/r/` — expected results

## Testing

```bash
# From the VillageSQL prebuilt mysql-test directory:
perl mysql-test-run.pl --suite=/path/to/vsql-statistics/mysql-test

# Record results:
perl mysql-test-run.pl --suite=/path/to/vsql-statistics/mysql-test --record
```

See `TESTING.md` for full instructions.

## VillageSQL Extension Framework (VEF) API

- Include: `<villagesql/vsql.h>`, `using namespace vsql;`
- Aggregate registration: `make_aggregate_func<State, &result_fn>(name)`
- Input wrapper: `RealArg` — `is_null()`, `value()` → `double`
- Result wrappers: `RealResult` — `set(double)`, `set_null()`; `StringResult` — `set(std::string)`, `set_null()`
- Type constants: `vsql::REAL`, `vsql::STRING`
- Entry point macro: `VEF_GENERATE_ENTRY_POINTS`

## Installation

```sql
INSTALL EXTENSION vsql_statistics;
SELECT STATS_IQR(CAST(col AS DOUBLE)) FROM t GROUP BY group_col;
SELECT CAST(STATS_TTEST(value, grp, 0.05) AS CHAR) FROM t;
SELECT CAST(STATS_TTEST_GROUPS(value, grp) AS CHAR) FROM t;
SELECT STATS_MODE(CAST(col AS DOUBLE)) FROM t;
SELECT CAST(STATS_SKEWNESS(col) AS CHAR) FROM t;
SELECT STATS_ZTEST_Z(col, 500.0, 40.0) FROM t;
SELECT STATS_ZTEST_P_TWO_TAIL(col, 500.0, 40.0) FROM t;
SELECT CAST(STATS_CHISQ_GOF(observed, expected) AS CHAR) FROM t;
SELECT CAST(STATS_CHISQ_INDEP(observed, expected, 2.0, 3.0) AS CHAR) FROM t;
UNINSTALL EXTENSION vsql_statistics;
```

## Known Limitations

- **STATS_MODE hex display:** VEF 0.0.4 `STRING` return type has no charset metadata; the mysql CLI shows results as hex. Workaround: `mysql --skip-binary-as-hex` or `CAST(STATS_MODE(...) AS CHAR)` in SQL.

## Conventions

- All entry points wrapped in `try/catch (...)`
- NULL check before any field access inside every VDF
- No global mutable state (re-entrant)
- C++17 required
