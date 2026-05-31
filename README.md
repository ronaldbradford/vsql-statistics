# VillageSQL Statistics Extension

Statistical aggregate functions for data scientists — IQR, quartiles, outlier detection, two-sample t-tests, one-sample z-tests, mode, and skewness.

## Installing

Build and install the extension:

```bash
VillageSQL_BUILD_DIR=~/.villagesql bash build.sh
cp build/vsql_statistics.veb <veb_dir>/
```

Enable in a session:

```sql
INSTALL EXTENSION vsql_statistics;
```

## Quick Start

```sql
-- Detect outliers by region
SELECT
  region,
  STATS_IQR_LOWER_FENCE(CAST(sale_amount AS DOUBLE)) AS lower_fence,
  STATS_IQR_UPPER_FENCE(CAST(sale_amount AS DOUBLE)) AS upper_fence
FROM daily_sales
GROUP BY region;

-- Test whether two groups differ (group column holds 1 or 2)
SELECT
  STATS_TTEST_T(value, grp)          AS t_stat,
  STATS_TTEST_P_TWO_TAIL(value, grp) AS p_value
FROM experiment_results;

-- Find the most common value(s) in a column
SELECT
  STATS_MODE(CAST(score AS DOUBLE))     AS all_modes,
  STATS_MODE_MIN(CAST(score AS DOUBLE)) AS lowest_mode,
  STATS_MODE_MAX(CAST(score AS DOUBLE)) AS highest_mode
FROM survey_responses;

-- Measure distribution asymmetry
SELECT
  STATS_SKEWNESS(salary)         AS skewness,
  STATS_SKEWNESS_PEARSON(salary) AS skewness_pearson
FROM employee_compensation;

-- One-sample z-test: is this batch's mean consistent with the known population?
SELECT
  STATS_ZTEST_Z(measurement, 500.0, 40.0)            AS z_stat,
  STATS_ZTEST_P_TWO_TAIL(measurement, 500.0, 40.0)   AS p_value
FROM quality_checks;
```

## Function Reference

### IQR Family

| Function | Returns | Description |
|---|---|---|
| `STATS_IQR(col)` | `DOUBLE` | Interquartile range: Q3 − Q1 |
| `STATS_Q1(col)` | `DOUBLE` | 25th percentile (Tukey's lower hinge) |
| `STATS_Q3(col)` | `DOUBLE` | 75th percentile (Tukey's upper hinge) |
| `STATS_MEDIAN(col)` | `DOUBLE` | 50th percentile |
| `STATS_IQR_LOWER_FENCE(col)` | `DOUBLE` | Q1 − 1.5 × IQR (outlier lower bound) |
| `STATS_IQR_UPPER_FENCE(col)` | `DOUBLE` | Q3 + 1.5 × IQR (outlier upper bound) |

All IQR functions:
- Accept any numeric column (`INT`, `DOUBLE`, etc.)
- Skip NULL values; return NULL for an all-NULL group
- Use Tukey's hinges (exclusive median) for quartile computation
- Work with `GROUP BY`

### Two-Sample t-Test Family (equal variances / pooled variance)

The group column must contain the value `1` or `2`; other values are silently ignored.

| Function | Returns | Description |
|---|---|---|
| `STATS_TTEST_T(value, grp)` | `DOUBLE` | t-statistic |
| `STATS_TTEST_DF(value, grp)` | `DOUBLE` | Degrees of freedom (n1 + n2 − 2) |
| `STATS_TTEST_POOLED_VAR(value, grp)` | `DOUBLE` | Pooled variance |
| `STATS_TTEST_P_ONE_TAIL(value, grp)` | `DOUBLE` | One-tail p-value |
| `STATS_TTEST_P_TWO_TAIL(value, grp)` | `DOUBLE` | Two-tail p-value |
| `STATS_TTEST_T_CRIT_ONE_TAIL(value, grp, alpha)` | `DOUBLE` | One-tail critical value at significance level alpha |
| `STATS_TTEST_T_CRIT_TWO_TAIL(value, grp, alpha)` | `DOUBLE` | Two-tail critical value at significance level alpha |

All t-test functions return NULL when either group has fewer than 2 non-NULL observations.

### Mode Family

| Function | Returns | Description |
|---|---|---|
| `STATS_MODE(col)` | `STRING` | JSON array of all values tied for the highest frequency, sorted ascending |
| `STATS_MODE_MIN(col)` | `DOUBLE` | Smallest value with the highest frequency |
| `STATS_MODE_MAX(col)` | `DOUBLE` | Largest value with the highest frequency |

All mode functions:
- Skip NULL and NaN inputs
- Return NULL when no value appears more than once (including single-row groups and all-unique groups)
- For unimodal data, `STATS_MODE_MIN` and `STATS_MODE_MAX` return the same value
- Work with `GROUP BY`

`STATS_MODE` returns a JSON string (e.g. `[24, 29]` for a bimodal dataset). Use `CAST(col AS DOUBLE)` on INT columns — without it the JSON values will be integer-rounded.

### One-Sample Z-Test Family (known population mean and standard deviation)

All three functions take `(value, mu, sigma)` where `mu` and `sigma` are the known population mean and standard deviation respectively.

| Function | Returns | Description |
|---|---|---|
| `STATS_ZTEST_Z(value, mu, sigma)` | `DOUBLE` | Z-statistic: (x̄ − μ) / (σ / √n) |
| `STATS_ZTEST_P_ONE_TAIL(value, mu, sigma)` | `DOUBLE` | Upper-tail probability: P(Z > z) |
| `STATS_ZTEST_P_TWO_TAIL(value, mu, sigma)` | `DOUBLE` | Two-tail probability: P(\|Z\| > \|z\|) |

All z-test functions:
- Skip NULL values in the `value` column; return NULL for an all-NULL group
- Return NULL when `sigma` ≤ 0 or was never supplied (all-NULL sigma column)
- Return NULL when `sigma` is NaN
- Work with `GROUP BY`

`STATS_ZTEST_P_ONE_TAIL` returns the upper-tail probability P(Z > z). When the sample mean is below μ (z < 0), this returns a value > 0.5 — indicating evidence against the upper-tail alternative. Use `STATS_ZTEST_P_TWO_TAIL` when you are testing for any deviation from μ rather than a directional hypothesis.

### Skewness Family

| Function | Returns | Description |
|---|---|---|
| `STATS_SKEWNESS(col)` | `DOUBLE` | Population skewness: third standardized moment g₁ = m₃ / m₂^(3/2) |
| `STATS_SKEWNESS_PEARSON(col)` | `DOUBLE` | Pearson's median skewness: 3 × (mean − median) / σ |

Both skewness functions:
- Skip NULL values; return NULL for an all-NULL group
- Return NULL for a single-row group or when all values are equal (zero variance)
- Work with `GROUP BY`

`STATS_SKEWNESS` uses a streaming accumulator (no value storage) — memory cost is O(1) per group regardless of group size. `STATS_SKEWNESS_PEARSON` requires storing all values to compute the median — memory cost is O(n) per group.

Positive values indicate right-skewed distributions (long right tail); negative values indicate left-skewed (long left tail); zero indicates symmetry.

## Building

**Prerequisites:** CMake 3.18+, C++17 compiler, VillageSQL Extension SDK 0.0.4+

```bash
VillageSQL_BUILD_DIR=/path/to/sdk bash build.sh
```

The `.veb` bundle is written to `build/vsql_statistics.veb`. Copy it to the directory shown by `SHOW VARIABLES LIKE 'veb_dir'`.

## Known Limitations

**INT column rounding.** When the input column is an `INT` type, VEF inherits the column type for result display, causing decimal values to be rounded (e.g. `STATS_IQR` on an INT column returns `8` instead of `7.5`). The underlying computation is correct.

Workaround: wrap the column in `CAST(col AS DOUBLE)`:

```sql
SELECT STATS_IQR(CAST(daily_count AS DOUBLE)) FROM espresso_sales;
-- Returns 7.5 (correct)

SELECT STATS_IQR(daily_count) FROM espresso_sales;
-- Returns 8 (rounded — INT column without CAST)
```

**Memory usage for large groups.** Exact quartile computation requires accumulating and sorting all values per group. For groups with millions of rows, memory and CPU cost will be proportional to group size. There is no streaming approximation within VEF.

**STATS_MODE displays as hex in the mysql CLI.** VEF 0.0.4's `STRING` return type carries no character set metadata, so the MySQL client treats the value as binary and displays it as hex (e.g. `0x5B31355D` instead of `[15]`). The data is correct.

Workarounds:

```bash
# Interactive mysql client — suppress hex display:
mysql --skip-binary-as-hex
```

```sql
-- Or cast in SQL (works in all clients):
SELECT CAST(STATS_MODE(CAST(val AS DOUBLE)) AS CHAR) AS modes FROM t;
```

**No in-place upgrade.** Upgrading the extension requires two separate steps:

```sql
UNINSTALL EXTENSION vsql_statistics;
INSTALL EXTENSION vsql_statistics;
```

## Testing

See `TESTING.md`.

## Reporting Bugs and Requesting Features

Open an issue at: https://github.com/villagesql/villagesql-server/issues

## Contact

- Discord: https://discord.gg/KSr6whd3Fr
- GitHub Issues: https://github.com/villagesql/villagesql-server/issues

## License

GPL-2.0. See `LICENSE`.
