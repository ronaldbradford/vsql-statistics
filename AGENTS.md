# AGENTS.md

This file provides guidance to AI coding assistants when working with code in this repository.

**Note**: Also check `AGENTS.local.md` for additional local development instructions when present.

## Project Overview

`vsql-statistics` is a VillageSQL extension that provides statistical aggregate functions for data scientists. It implements two families of functions:

- **IQR family (6 functions):** `STATS_IQR`, `STATS_Q1`, `STATS_Q3`, `STATS_MEDIAN`, `STATS_IQR_LOWER_FENCE`, `STATS_IQR_UPPER_FENCE`
- **Two-sample t-test family (7 functions):** `STATS_TTEST_T`, `STATS_TTEST_DF`, `STATS_TTEST_POOLED_VAR`, `STATS_TTEST_P_ONE_TAIL`, `STATS_TTEST_P_TWO_TAIL`, `STATS_TTEST_T_CRIT_ONE_TAIL`, `STATS_TTEST_T_CRIT_TWO_TAIL`
- **Mode family (3 functions):** `STATS_MODE`, `STATS_MODE_MIN`, `STATS_MODE_MAX`
- **Skewness family (2 functions):** `STATS_SKEWNESS`, `STATS_SKEWNESS_PEARSON`
- **Z-test family (3 functions):** `STATS_ZTEST_Z`, `STATS_ZTEST_P_ONE_TAIL`, `STATS_ZTEST_P_TWO_TAIL`
- **Chi-squared family (5 functions):** `STATS_CHISQ_GOF`, `STATS_CHISQ_GOF_DF`, `STATS_CHISQ_GOF_P`, `STATS_CHISQ_INDEP`, `STATS_CHISQ_INDEP_P`
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

The t-test family (7 functions) uses `TTestState` with separate `group1`/`group2` vectors and a stored `alpha`. Group membership is passed as the second argument (1 = group 1, 2 = group 2). The 3-parameter critical-value functions also accept alpha directly.

The mode family (3 functions) uses `ModeState` with `std::unordered_map<double, size_t>` for frequency counting. `STATS_MODE` returns a JSON STRING; `STATS_MODE_MIN` and `STATS_MODE_MAX` return REAL. All three return NULL when no value appears more than once. NaN inputs are skipped alongside NULLs.

The skewness family (2 functions) uses two separate states. `STATS_SKEWNESS` uses `SkewState` — a streaming accumulator of n, Σx, Σx², Σx³ (shifted by the first observed value to reduce floating-point cancellation); no vector storage, O(1) memory per group. `STATS_SKEWNESS_PEARSON` reuses `StatsState` (vector of doubles) for median access. Both return NULL when variance is zero or n < 2.

The z-test family (3 functions) uses `ZTestState` — streaming accumulator of n and Σx, plus stored `mu` and `sigma` constants (last non-null wins per row; sigma defaults to 0.0 so all-null sigma returns NULL). `STATS_ZTEST_P_ONE_TAIL` returns the upper-tail probability P(Z > z), which is > 0.5 when the sample mean is below μ. All three return NULL when n=0, sigma≤0, or sigma is NaN.

The means family (4 functions — beta) uses three states. `MeanTrimState` (vector + trim_pct) serves both `STATS_MEAN_TRIMMED` and `STATS_MEAN_WINSORIZED` (2-param functions). `MeanGeoState` (n, sum_log) is a streaming accumulator for `STATS_MEAN_GEOMETRIC`: accumulates Σln(xi) for positive values, then returns exp(sum_log/n). `MeanHarmState` (n, sum_recip) is a streaming accumulator for `STATS_MEAN_HARMONIC`: accumulates Σ(1/xi) for positive values, then returns n/sum_recip. Non-positive inputs are silently skipped for both geometric and harmonic.

The chi-squared family (5 functions) uses two states. `ChiSqGofState` (chi_sq, k) serves the three GoF functions and also `STATS_CHISQ_INDEP` (same formula, no n_rows/n_cols needed). `ChiSqIndepState` (chi_sq, k, n_rows, n_cols) serves `STATS_CHISQ_INDEP_P`, which accepts the number of rows and columns as constant parameters per row. The p-value is the regularized upper incomplete gamma Q(df/2, χ²/2); computed via series expansion (x < a+1) or Lentz's continued fraction (x ≥ a+1). Rows where expected ≤ 0 are skipped. All five functions return NULL when no valid (O, E) pairs exist.

**Quartile algorithm:** Tukey's hinges (exclusive median). For a sorted vector of n values:
- Lower half: indices [0, n/2)
- Upper half: indices [n/2+1, n) for odd n, [n/2, n) for even n
- Q1 = median of lower half, Q3 = median of upper half
- NULL inputs are skipped; all-NULL group returns NULL
- n=1: Q1=Q3=value, IQR=0

**Function registration:** `make_aggregate_func<StatsState, &result_fn>(name).returns(REAL).param(REAL).clear<&stats_clear>().accumulate<&stats_accumulate>().build()`

**Key files:**
- `src/vsql_statistics.cc` — all 30 aggregate functions (6 IQR + 7 t-test + 3 mode + 2 skewness + 3 z-test + 5 chi-squared + 4 means)
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
- Result wrapper: `RealResult` — `set(double)`, `set_null()`
- Type constants: `vsql::REAL`
- Entry point macro: `VEF_GENERATE_ENTRY_POINTS`

## Installation

```sql
INSTALL EXTENSION vsql_statistics;
SELECT STATS_IQR(CAST(col AS DOUBLE)) FROM t GROUP BY group_col;
SELECT STATS_TTEST_T(value, grp) FROM t;
SELECT STATS_MODE(CAST(col AS DOUBLE)) FROM t;
SELECT STATS_SKEWNESS(col) FROM t;
SELECT STATS_SKEWNESS_PEARSON(col) FROM t;
SELECT STATS_ZTEST_Z(col, 500.0, 40.0) FROM t;
SELECT STATS_ZTEST_P_TWO_TAIL(col, 500.0, 40.0) FROM t;
SELECT STATS_CHISQ_GOF(observed, expected) FROM t;
SELECT STATS_CHISQ_GOF_P(observed, expected) FROM t;
SELECT STATS_CHISQ_INDEP_P(observed, expected, 2.0, 3.0) FROM t;
UNINSTALL EXTENSION vsql_statistics;
```

## Known Limitations

- **STATS_MODE hex display:** VEF 0.0.4 `STRING` return type has no charset metadata; the mysql CLI shows results as hex. Workaround: `mysql --skip-binary-as-hex` or `CAST(STATS_MODE(...) AS CHAR)` in SQL.

## Conventions

- All entry points wrapped in `try/catch (...)`
- NULL check before any field access inside every VDF
- No global mutable state (re-entrant)
- C++17 required
