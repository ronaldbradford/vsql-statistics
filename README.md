# VillageSQL Statistics Extension

Statistical aggregate functions for data scientists — IQR, quartiles, outlier detection, two-sample t-tests, one-sample z-tests, mode, skewness, kurtosis, covariance, chi-squared tests, robust/ratio means, and one-way ANOVA.

## Summary

| Family | Count | Functions |
|--------|------:|-----------|
| **IQR** | 6 | `STATS_IQR`, `STATS_Q1`, `STATS_Q3`, `STATS_MEDIAN`, `STATS_IQR_LOWER_FENCE`, `STATS_IQR_UPPER_FENCE` |
| **T-test** | 2 | `STATS_TTEST`, `STATS_TTEST_GROUPS` |
| **Mode** | 1 | `STATS_MODE` |
| **Skewness** | 1 | `STATS_SKEWNESS` |
| **Z-test** | 3 | `STATS_ZTEST_Z`, `STATS_ZTEST_P_ONE_TAIL`, `STATS_ZTEST_P_TWO_TAIL` |
| **Chi-squared** | 2 | `STATS_CHISQ_GOF`, `STATS_CHISQ_INDEP` |
| **Kurtosis** | 1 | `STATS_KURTOSIS` |
| **Covariance** | 2 | `STATS_COVARIANCE_POP`, `STATS_COVARIANCE_SAMP` |
| **Means** | 4 | `STATS_MEAN_TRIMMED`, `STATS_MEAN_WINSORIZED`, `STATS_MEAN_GEOMETRIC`, `STATS_MEAN_HARMONIC` |
| **ANOVA** | 9 | `STATS_ANOVA_F`, `STATS_ANOVA_P`, `STATS_ANOVA_SSB`, `STATS_ANOVA_SSW`, `STATS_ANOVA_SST`, `STATS_ANOVA_MSB`, `STATS_ANOVA_MSW`, `STATS_ANOVA_DFB`, `STATS_ANOVA_DFW` |
| **Total** | **31** | |

> **Beta notice:** All functions in this extension (`STATS_IQR`, `STATS_TTEST`, `STATS_TTEST_GROUPS`, `STATS_MODE`, `STATS_SKEWNESS`, `STATS_ZTEST_*`, `STATS_CHISQ_*`, `STATS_KURTOSIS`, `STATS_COVARIANCE_*`, `STATS_MEAN_*`, `STATS_ANOVA_*`) are beta quality. They are functionally correct on the tested datasets but have not been validated at production scale. Use with caution in high-volume or precision-critical workloads and report any anomalies.


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
-- STATS_TTEST returns inference stats; STATS_TTEST_GROUPS returns per-group descriptives.
-- Use CAST(... AS CHAR(1000)) + JSON_EXTRACT to read individual fields.
WITH groups AS (
  SELECT CAST(STATS_TTEST(value, grp, 0.05)   AS CHAR(1000)) AS ttest_json,
         CAST(STATS_TTEST_GROUPS(value, grp)   AS CHAR(1000)) AS groups_json
  FROM experiment_results
)
SELECT
  JSON_EXTRACT(groups_json, '$.mean_1')     AS mean_group1,
  JSON_EXTRACT(groups_json, '$.mean_2')     AS mean_group2,
  JSON_EXTRACT(ttest_json,  '$.t')          AS t_stat,
  JSON_EXTRACT(ttest_json,  '$.p_two_tail') AS p_value,
  IF(JSON_EXTRACT(ttest_json, '$.p_two_tail') < 0.05, 'Significant', 'Not Significant') AS result
FROM groups;

-- Find the most common value(s) in a column
WITH m AS (SELECT CAST(STATS_MODE(CAST(score AS DOUBLE)) AS CHAR(200)) AS json FROM survey_responses)
SELECT JSON_EXTRACT(json, '$.values') AS all_modes,
       JSON_EXTRACT(json, '$.min')    AS lowest_mode,
       JSON_EXTRACT(json, '$.max')    AS highest_mode
FROM m;

-- Measure distribution asymmetry (moment = third standardized moment, pearson = median-based)
WITH s AS (SELECT CAST(STATS_SKEWNESS(salary) AS CHAR(200)) AS json FROM employee_compensation)
SELECT JSON_EXTRACT(json, '$.moment') AS skewness_moment,
       JSON_EXTRACT(json, '$.pearson') AS skewness_pearson
FROM s;

-- One-sample z-test: is this batch's mean consistent with the known population?
SELECT
  STATS_ZTEST_Z(measurement, 500.0, 40.0)            AS z_stat,
  STATS_ZTEST_P_TWO_TAIL(measurement, 500.0, 40.0)   AS p_value
FROM quality_checks;

-- Kurtosis: measure tail heaviness (kurtosis=β₂, excess=g₂ Fisher-Pearson)
WITH k AS (SELECT CAST(STATS_KURTOSIS(return_pct) AS CHAR(200)) AS json FROM asset_returns)
SELECT JSON_EXTRACT(json, '$.kurtosis') AS pop_kurtosis,
       JSON_EXTRACT(json, '$.excess')   AS excess_kurtosis
FROM k;

-- Trimmed mean: reduce outlier influence by discarding extremes
SELECT STATS_MEAN_TRIMMED(sale_amount, 0.1) AS robust_mean FROM daily_sales;

-- Geometric mean: average growth rate across periods
SELECT STATS_MEAN_GEOMETRIC(growth_factor) AS avg_growth FROM quarterly_returns;

-- Harmonic mean: true average for rates and ratios
SELECT STATS_MEAN_HARMONIC(speed_mph) AS avg_speed FROM journey_legs;

-- Chi-squared goodness of fit: do observed counts match expected proportions?
-- STATS_CHISQ_GOF returns JSON {chi_sq, df, p}; use CAST + JSON_EXTRACT to read fields.
WITH gof AS (
  SELECT CAST(STATS_CHISQ_GOF(observed, expected) AS CHAR(200)) AS json
  FROM category_counts
)
SELECT
  JSON_EXTRACT(json, '$.chi_sq') AS chi_sq,
  JSON_EXTRACT(json, '$.df')     AS df,
  JSON_EXTRACT(json, '$.p')      AS p_value
FROM gof;

-- Chi-squared test of independence: are two categorical variables related?
-- n_rows and n_cols are the contingency table dimensions (constants repeated per row).
WITH indep AS (
  SELECT CAST(STATS_CHISQ_INDEP(observed, expected, 2.0, 3.0) AS CHAR(200)) AS json
  FROM contingency_table
)
SELECT
  JSON_EXTRACT(json, '$.chi_sq') AS chi_sq,
  JSON_EXTRACT(json, '$.df')     AS df,
  JSON_EXTRACT(json, '$.p')      AS p_value
FROM indep;

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

Both functions accept `(value, group)` where the group column identifies observations as belonging to group 1 or group 2. Other group values are silently ignored.

| Function | Returns | Description |
|---|---|---|
| `STATS_TTEST(value, grp, alpha)` | `STRING` | JSON object with inference statistics: `pooled_var`, `df`, `t`, `p_one_tail`, `t_crit_one_tail`, `p_two_tail`, `t_crit_two_tail` |
| `STATS_TTEST_GROUPS(value, grp)` | `STRING` | JSON object with per-group descriptives: `mean_1`, `mean_2`, `variance_1`, `variance_2`, `n_1`, `n_2` |

`alpha` controls the significance level for critical values (pass `0.05` for 95% confidence). `t_crit_*` fields are `null` when alpha is outside (0, 1). Numeric values use fixed decimal notation — no scientific notation.

Both functions return NULL when either group has fewer than 2 non-NULL observations.

Because these functions return JSON strings, use `CAST(... AS CHAR(1000))` and `JSON_EXTRACT` to access individual fields:

```sql
WITH results AS (
  SELECT
    CAST(STATS_TTEST(value, grp, 0.05) AS CHAR(1000)) AS ttest_json,
    CAST(STATS_TTEST_GROUPS(value, grp) AS CHAR(1000)) AS groups_json
  FROM experiment_results
)
SELECT
  JSON_EXTRACT(groups_json, '$.mean_1')          AS mean_group1,
  JSON_EXTRACT(groups_json, '$.mean_2')          AS mean_group2,
  JSON_EXTRACT(groups_json, '$.variance_1')      AS variance_group1,
  JSON_EXTRACT(groups_json, '$.variance_2')      AS variance_group2,
  JSON_EXTRACT(groups_json, '$.n_1')             AS n_group1,
  JSON_EXTRACT(groups_json, '$.n_2')             AS n_group2,
  JSON_EXTRACT(ttest_json,  '$.pooled_var')      AS pooled_variance,
  JSON_EXTRACT(ttest_json,  '$.df')              AS degrees_of_freedom,
  JSON_EXTRACT(ttest_json,  '$.t')               AS t_statistic,
  JSON_EXTRACT(ttest_json,  '$.p_one_tail')      AS p_value_one_tail,
  JSON_EXTRACT(ttest_json,  '$.t_crit_one_tail') AS t_critical_one_tail,
  JSON_EXTRACT(ttest_json,  '$.p_two_tail')      AS p_value_two_tail,
  JSON_EXTRACT(ttest_json,  '$.t_crit_two_tail') AS t_critical_two_tail
FROM results;
```

See `examples/t_test_height.sql` and `examples/t_test_us_draft.sql` for complete worked examples.

### Mode Family

| Function | Returns | Description |
|---|---|---|
| `STATS_MODE(col)` | `STRING` | JSON `{"values":[...], "min":..., "max":...}` — `values` is sorted ascending; `min`/`max` are the first and last elements |

`STATS_MODE`:
- Skips NULL and NaN inputs
- Returns NULL when no value appears more than once (all-unique groups, single-row groups, all-NULL groups)
- Works with `GROUP BY`

Use `CAST(col AS DOUBLE)` on INT columns — without it the JSON values will be integer-rounded. Use `CAST(STATS_MODE(...) AS CHAR)` to read results in the mysql CLI.

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
| `STATS_KURTOSIS(col)` | `STRING` | JSON `{"kurtosis": ..., "excess": ...}` — `excess` is null when n < 4; both null when variance is zero |

`kurtosis` is the population kurtosis β₂ = μ₄/σ⁴. `excess` is the Fisher-Pearson unbiased sample excess kurtosis g₂ (denominator contains (n−2)(n−3), so requires n ≥ 4).

`STATS_KURTOSIS`:
- Uses a streaming accumulator — O(1) memory regardless of group size
- Skips NULL values; returns NULL for an all-NULL group or a single-row group
- Returns `{"kurtosis":null,"excess":null}` when all values are equal (zero variance)
- Works with `GROUP BY`

Interpretation: normal distribution has β₂ = 3 and g₂ = 0. Positive excess = heavy-tailed (leptokurtic); negative = light-tailed (platykurtic).

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

Both functions share a common formula — χ² = Σ[(O − E)² / E] — and return a JSON STRING with fields `chi_sq`, `df`, and `p`. Use `CAST(... AS CHAR(200))` and `JSON_EXTRACT` to access individual fields.

#### Goodness of Fit

Tests whether observed counts match expected proportions across k categories (df = k − 1).

| Function | Returns | Description |
|---|---|---|
| `STATS_CHISQ_GOF(observed, expected)` | `STRING` | JSON `{chi_sq, df, p}` — p is `null` when df = 0 (single category) |

#### Test of Independence

Tests whether two categorical variables in a contingency table are independent (df = (r − 1)(c − 1)).

| Function | Returns | Description |
|---|---|---|
| `STATS_CHISQ_INDEP(observed, expected, n_rows, n_cols)` | `STRING` | JSON `{chi_sq, df, p}` — df and p are `null` when dimensions are missing or df ≤ 0 |

`n_rows` and `n_cols` are the contingency table dimensions — pass them as constants repeated on every row.

Both chi-squared functions:
- Skip rows where `expected` is NULL, zero, or negative
- Return NULL when no valid (observed, expected) pairs exist
- Work with `GROUP BY`, computing the statistic independently per group

See `examples/chisq_support_tickets.sql` for a complete worked example.

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

The spec requires k ≥ 3 groups for a valid one-way ANOVA. k = 2 is mathematically equivalent to a t-test — use `STATS_TTEST` for two-group comparisons.

### Skewness Family

| Function | Returns | Description |
|---|---|---|
| `STATS_SKEWNESS(col)` | `STRING` | JSON `{"moment": ..., "pearson": ...}` — both fields `null` when variance is zero |

`moment` is the population skewness (third standardized moment g₁ = m₃ / m₂^(3/2)). `pearson` is Pearson's median skewness: 3 × (mean − median) / σ.

`STATS_SKEWNESS`:
- Skips NULL values; returns NULL for an all-NULL group or a single-row group
- Returns `{"moment":null,"pearson":null}` when all values are equal (zero variance)
- Works with `GROUP BY`
- Stores all values per group (O(n) memory) to compute the median for Pearson's measure

Positive `moment` indicates right-skewed (long right tail); negative indicates left-skewed; zero indicates symmetry.

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

**JSON STRING functions display as hex in the mysql CLI.** VEF 0.0.4's `STRING` return type carries no character set metadata, so the MySQL client treats the value as binary and displays it as hex. The data is correct.

Workarounds:

```bash
# Interactive mysql client — suppress hex display:
mysql --skip-binary-as-hex
```

```sql
-- Or cast in SQL (works in all clients):
SELECT CAST(STATS_MODE(CAST(val AS DOUBLE)) AS CHAR) AS mode FROM t;
SELECT CAST(STATS_TTEST(value, grp, 0.05) AS CHAR) AS ttest FROM t;
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
