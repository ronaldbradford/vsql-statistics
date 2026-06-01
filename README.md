# VillageSQL Statistics Extension

Statistical aggregate functions for data scientists — IQR, quartiles, outlier detection, two-sample t-tests, one-sample z-tests, mode, skewness, kurtosis, covariance, chi-squared tests, robust/ratio means, and one-way ANOVA.

## Summary

| Family | Count | Functions |
|--------|------:|-----------|
| **IQR** | 6 | `STATS_IQR`, `STATS_Q1`, `STATS_Q3`, `STATS_MEDIAN`, `STATS_IQR_LOWER_FENCE`, `STATS_IQR_UPPER_FENCE` |
| **T-test** | 7 | `STATS_TTEST_T`, `STATS_TTEST_DF`, `STATS_TTEST_POOLED_VAR`, `STATS_TTEST_P_ONE_TAIL`, `STATS_TTEST_P_TWO_TAIL`, `STATS_TTEST_T_CRIT_ONE_TAIL`, `STATS_TTEST_T_CRIT_TWO_TAIL` |
| **Mode** | 3 | `STATS_MODE`, `STATS_MODE_MIN`, `STATS_MODE_MAX` |
| **Skewness** | 2 | `STATS_SKEWNESS`, `STATS_SKEWNESS_PEARSON` |
| **Z-test** | 3 | `STATS_ZTEST_Z`, `STATS_ZTEST_P_ONE_TAIL`, `STATS_ZTEST_P_TWO_TAIL` |
| **Chi-squared** | 5 | `STATS_CHISQ_GOF`, `STATS_CHISQ_GOF_DF`, `STATS_CHISQ_GOF_P`, `STATS_CHISQ_INDEP`, `STATS_CHISQ_INDEP_P` |
| **Kurtosis** | 2 | `STATS_KURTOSIS`, `STATS_KURTOSIS_EXCESS` |
| **Covariance** | 2 | `STATS_COVARIANCE_POP`, `STATS_COVARIANCE_SAMP` |
| **Means** | 4 | `STATS_MEAN_TRIMMED`, `STATS_MEAN_WINSORIZED`, `STATS_MEAN_GEOMETRIC`, `STATS_MEAN_HARMONIC` |
| **ANOVA** | 9 | `STATS_ANOVA_F`, `STATS_ANOVA_P`, `STATS_ANOVA_SSB`, `STATS_ANOVA_SSW`, `STATS_ANOVA_SST`, `STATS_ANOVA_MSB`, `STATS_ANOVA_MSW`, `STATS_ANOVA_DFB`, `STATS_ANOVA_DFW` |
| **Total** | **43** | |

> **Beta notice:** All functions in this extension (`STATS_IQR`, `STATS_TTEST_*`, `STATS_MODE`, `STATS_SKEWNESS`, `STATS_ZTEST_*`, `STATS_CHISQ_*`, `STATS_KURTOSIS*`, `STATS_COVARIANCE_*`, `STATS_MEAN_*`, `STATS_ANOVA_*`) are beta quality. They are functionally correct on the tested datasets but have not been validated at production scale. Use with caution in high-volume or precision-critical workloads and report any anomalies.


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

-- Kurtosis: measure tail heaviness of a distribution
SELECT
  STATS_KURTOSIS(return_pct)        AS pop_kurtosis,
  STATS_KURTOSIS_EXCESS(return_pct) AS excess_kurtosis
FROM asset_returns;

-- Trimmed mean: reduce outlier influence by discarding extremes
SELECT STATS_MEAN_TRIMMED(sale_amount, 0.1) AS robust_mean FROM daily_sales;

-- Geometric mean: average growth rate across periods
SELECT STATS_MEAN_GEOMETRIC(growth_factor) AS avg_growth FROM quarterly_returns;

-- Harmonic mean: true average for rates and ratios
SELECT STATS_MEAN_HARMONIC(speed_mph) AS avg_speed FROM journey_legs;

-- Chi-squared goodness of fit: do observed counts match expected proportions?
SELECT
  STATS_CHISQ_GOF(observed, expected)    AS chi_sq,
  STATS_CHISQ_GOF_DF(observed, expected) AS df,
  STATS_CHISQ_GOF_P(observed, expected)  AS p_value
FROM category_counts;

-- Chi-squared test of independence: are two categorical variables related?
SELECT
  STATS_CHISQ_INDEP(observed, expected)              AS chi_sq,
  STATS_CHISQ_INDEP_P(observed, expected, 2.0, 3.0)  AS p_value
FROM contingency_table;

-- One-way ANOVA: do three or more groups have the same population mean?
SELECT
  STATS_ANOVA_F(score, treatment_group)  AS f_stat,
  STATS_ANOVA_P(score, treatment_group)  AS p_value,
  STATS_ANOVA_SSB(score, treatment_group) AS ss_between,
  STATS_ANOVA_SSW(score, treatment_group) AS ss_within
FROM clinical_trial;
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

### Kurtosis Family

| Function | Returns | Description |
|---|---|---|
| `STATS_KURTOSIS(col)` | `DOUBLE` | Population kurtosis β₂ = μ₄/σ⁴ (normal distribution = 3) |
| `STATS_KURTOSIS_EXCESS(col)` | `DOUBLE` | Fisher-Pearson sample excess kurtosis g₂ = β₂ − 3 (unbiased; normal distribution = 0) |

Both kurtosis functions:
- Use a streaming accumulator — O(1) memory regardless of group size
- Skip NULL values; return NULL for an all-NULL group
- Return NULL when all values are equal (zero variance)
- Work with `GROUP BY`

`STATS_KURTOSIS` requires n ≥ 2. `STATS_KURTOSIS_EXCESS` requires n ≥ 4 (the unbiased correction factor has (n−2)(n−3) in the denominator).

Interpretation of excess kurtosis: zero = normal (mesokurtic); positive = heavy-tailed (leptokurtic); negative = light-tailed (platykurtic).

### Covariance Family

Both functions accept `(x, y)` — one row per paired observation.

| Function | Returns | Description |
|---|---|---|
| `STATS_COVARIANCE_POP(x, y)` | `DOUBLE` | Population covariance σ_xy = Σ(xi−μx)(yi−μy) / N |
| `STATS_COVARIANCE_SAMP(x, y)` | `DOUBLE` | Sample covariance s_xy = Σ(xi−x̄)(yi−ȳ) / (n−1) (Bessel-corrected) |

Both functions:
- Use Welford's single-pass streaming algorithm — O(1) memory, numerically stable
- Skip rows where either `x` or `y` is NULL (concurrent-pair discard)
- Return NULL when all pairs are NULL
- Work with `GROUP BY`

`STATS_COVARIANCE_POP` requires N ≥ 1 and returns 0.0 for a single pair. `STATS_COVARIANCE_SAMP` requires n ≥ 2 and returns NULL otherwise.

Interpretation: positive covariance means x and y increase together; negative means they move in opposite directions; zero indicates no linear relationship.

### Means Family *(beta)*

> These functions are beta quality — see the notice at the top of this document.

#### Trimmed and Winsorized Means

Both functions accept `(col, trim_pct)` where `trim_pct` is the fraction to remove or replace from each end (e.g., `0.2` for 20%). Pass the same constant on every row.

| Function | Returns | Description |
|---|---|---|
| `STATS_MEAN_TRIMMED(col, trim_pct)` | `DOUBLE` | Arithmetic mean after removing the bottom and top `trim_pct` fraction |
| `STATS_MEAN_WINSORIZED(col, trim_pct)` | `DOUBLE` | Arithmetic mean after replacing extremes with the boundary values |

Both functions:
- Return NULL for an all-NULL group or when trimming removes all values (trim_pct ≥ 0.5)
- Work with `GROUP BY`

#### Geometric and Harmonic Means

| Function | Returns | Description |
|---|---|---|
| `STATS_MEAN_GEOMETRIC(col)` | `DOUBLE` | nth root of the product of all values; use for growth rates and ratios |
| `STATS_MEAN_HARMONIC(col)` | `DOUBLE` | n / Σ(1/xᵢ); use for rates such as speed or throughput |

Both functions:
- Skip non-positive values (log and reciprocal are undefined at zero or below)
- Return NULL when no positive values exist in the group
- Work with `GROUP BY`

### Chi-Squared Family

Two families of chi-squared functions share a common formula — χ² = Σ[(O − E)² / E] — applied to rows where expected > 0.

#### Goodness of Fit

Tests whether observed counts match expected proportions across k categories (df = k − 1).

| Function | Returns | Description |
|---|---|---|
| `STATS_CHISQ_GOF(observed, expected)` | `DOUBLE` | Chi-squared statistic |
| `STATS_CHISQ_GOF_DF(observed, expected)` | `DOUBLE` | Degrees of freedom: k − 1 |
| `STATS_CHISQ_GOF_P(observed, expected)` | `DOUBLE` | P-value: P(χ²_{k-1} > stat) |

#### Test of Independence

Tests whether two categorical variables in a contingency table are independent (df = (r − 1)(c − 1)).

| Function | Returns | Description |
|---|---|---|
| `STATS_CHISQ_INDEP(observed, expected)` | `DOUBLE` | Chi-squared statistic |
| `STATS_CHISQ_INDEP_P(observed, expected, n_rows, n_cols)` | `DOUBLE` | P-value: P(χ²_{(r-1)(c-1)} > stat) |

`n_rows` and `n_cols` are the number of rows and columns in the contingency table — pass them as constants repeated on every row.

All chi-squared functions:
- Skip rows where `expected` is NULL, zero, or negative
- Return NULL when no valid (observed, expected) pairs exist
- Return NULL for `STATS_CHISQ_GOF_P` and `STATS_CHISQ_INDEP_P` when df ≤ 0
- Work with `GROUP BY`, computing the statistic independently per group

### One-Way ANOVA Family

Tests whether three or more independent groups share the same population mean by partitioning total variance into between-group (treatment) and within-group (error) components.

All functions accept `(value, group)` where the group column identifies which group each row belongs to (any distinct numeric value).

| Function | Returns | Description |
|---|---|---|
| `STATS_ANOVA_F(value, group)` | `DOUBLE` | F-statistic: MSB / MSW |
| `STATS_ANOVA_P(value, group)` | `DOUBLE` | P-value: P(F_{dfB,dfW} > F) |
| `STATS_ANOVA_SSB(value, group)` | `DOUBLE` | Between-group sum of squares |
| `STATS_ANOVA_SSW(value, group)` | `DOUBLE` | Within-group sum of squares (error) |
| `STATS_ANOVA_SST(value, group)` | `DOUBLE` | Total sum of squares (SSB + SSW) |
| `STATS_ANOVA_MSB(value, group)` | `DOUBLE` | Mean square between: SSB / (k − 1) |
| `STATS_ANOVA_MSW(value, group)` | `DOUBLE` | Mean square within: SSW / (N − k) |
| `STATS_ANOVA_DFB(value, group)` | `DOUBLE` | Between-group degrees of freedom: k − 1 |
| `STATS_ANOVA_DFW(value, group)` | `DOUBLE` | Within-group degrees of freedom: N − k |

All ANOVA functions:
- Use Welford's online algorithm for numerically stable within-group variance (O(1) memory per group)
- Skip NULL values in the `value` or `group` column
- Return NULL when fewer than 2 distinct groups are present
- Return NULL when any group has fewer than 2 non-NULL observations
- Return NULL when within-group variance is zero (MSW = 0)
- Work with `GROUP BY`, computing an independent ANOVA per partition

The spec requires k ≥ 3 groups for a valid one-way ANOVA. k = 2 is mathematically equivalent to a t-test — use `STATS_TTEST_T` for two-group comparisons.

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
