# VillageSQL Statistics Extension

Statistical aggregate functions for data scientists — IQR, quartiles, outlier detection, two-sample t-tests, one-sample z-tests, mode, skewness, kurtosis, covariance, chi-squared tests, robust/ratio means, and one-way ANOVA.

## Summary

| Family | Functions |
|--------|-----------|
| [**IQR**](https://en.wikipedia.org/wiki/Interquartile_range) | `STATS_IQR` |
| [**T-test**](https://en.wikipedia.org/wiki/Student%27s_t-test) | `STATS_TTEST`, `STATS_TTEST_GROUPS` |
| [**Mode**](https://en.wikipedia.org/wiki/Mode_(statistics)) | `STATS_MODE` |
| [**Skewness**](https://en.wikipedia.org/wiki/Skewness) | `STATS_SKEWNESS` |
| [**Z-test**](https://en.wikipedia.org/wiki/Z-test) | `STATS_ZTEST` |
| [**Chi-squared**](https://en.wikipedia.org/wiki/Chi-squared_test) | `STATS_CHISQ_GOF`, `STATS_CHISQ_INDEP` |
| [**Kurtosis**](https://en.wikipedia.org/wiki/Kurtosis) | `STATS_KURTOSIS` |
| [**Covariance**](https://en.wikipedia.org/wiki/Covariance) | `STATS_COVARIANCE` |
| [**Means**](https://en.wikipedia.org/wiki/Truncated_mean) | `STATS_MEAN` |
| [**ANOVA**](https://en.wikipedia.org/wiki/One-way_analysis_of_variance) | `STATS_ANOVA` |

> **Beta notice:** Functions in this extension (`STATS_IQR`, `STATS_TTEST`, `STATS_TTEST_GROUPS`, `STATS_MODE`, `STATS_SKEWNESS`, `STATS_ZTEST`, `STATS_CHISQ_*`, `STATS_KURTOSIS`, `STATS_COVARIANCE`, `STATS_MEAN`, `STATS_ANOVA`) are beta quality. They are functionally correct on the tested datasets but have not been validated at production scale. Use with caution in high-volume or precision-critical workloads and report any anomalies.


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
WITH i AS (SELECT region, CAST(STATS_IQR(CAST(sale_amount AS DOUBLE)) AS CHAR(300)) AS json
           FROM daily_sales GROUP BY region)
SELECT region,
       JSON_EXTRACT(json, '$.lower_fence') AS lower_fence,
       JSON_EXTRACT(json, '$.upper_fence') AS upper_fence
FROM i;

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
WITH z AS (SELECT CAST(STATS_ZTEST(measurement, 500.0, 40.0) AS CHAR(200)) AS json FROM quality_checks)
SELECT JSON_EXTRACT(json, '$.z')           AS z_stat,
       JSON_EXTRACT(json, '$.p_two_tail')  AS p_value
FROM z;

-- Kurtosis: measure tail heaviness (kurtosis=β₂, excess=g₂ Fisher-Pearson)
WITH k AS (SELECT CAST(STATS_KURTOSIS(return_pct) AS CHAR(200)) AS json FROM asset_returns)
SELECT JSON_EXTRACT(json, '$.kurtosis') AS pop_kurtosis,
       JSON_EXTRACT(json, '$.excess')   AS excess_kurtosis
FROM k;

-- Covariance: do advertising spend and revenue move together?
WITH c AS (SELECT CAST(STATS_COVARIANCE(ad_spend, revenue) AS CHAR(200)) AS json FROM monthly_results)
SELECT JSON_EXTRACT(json, '$.pop')  AS cov_pop,
       JSON_EXTRACT(json, '$.samp') AS cov_samp
FROM c;

-- Robust means: trimmed/winsorized reduce outlier influence; geometric/harmonic for rates
-- Pass NULL for trim_pct when only geometric/harmonic are needed
WITH m AS (SELECT CAST(STATS_MEAN(sale_amount, 0.1) AS CHAR(300)) AS json FROM daily_sales)
SELECT JSON_EXTRACT(json, '$.trimmed')    AS trimmed_mean,
       JSON_EXTRACT(json, '$.winsorized') AS winsorized_mean,
       JSON_EXTRACT(json, '$.geometric')  AS geo_mean,
       JSON_EXTRACT(json, '$.harmonic')   AS harm_mean
FROM m;

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
WITH a AS (SELECT CAST(STATS_ANOVA(score, treatment_group) AS CHAR(400)) AS json FROM clinical_trial)
SELECT JSON_EXTRACT(json, '$.f')   AS f_stat,
       JSON_EXTRACT(json, '$.p')   AS p_value,
       JSON_EXTRACT(json, '$.ssb') AS ss_between,
       JSON_EXTRACT(json, '$.ssw') AS ss_within
FROM a;
```

## Function Reference

### IQR Family

`STATS_IQR(col)` sorts the group once and returns a JSON STRING with all distribution summary fields:

| Field | Description |
|---|---|
| `q1` | 25th percentile (Tukey's lower hinge) |
| `median` | 50th percentile |
| `q3` | 75th percentile (Tukey's upper hinge) |
| `iqr` | Interquartile range: Q3 − Q1 |
| `lower_fence` | Q1 − 1.5 × IQR (outlier lower bound) |
| `upper_fence` | Q3 + 1.5 × IQR (outlier upper bound) |

`STATS_IQR`:
- Accepts any numeric column (`INT`, `DOUBLE`, etc.)
- Skips NULL values; returns NULL for an all-NULL group
- Uses Tukey's hinges (exclusive median) for quartile computation
- Works with `GROUP BY`

Use `CAST(STATS_IQR(...) AS CHAR)` to read results in the mysql CLI.

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

`STATS_ZTEST(value, mu, sigma)` takes the known population mean `mu` and standard deviation `sigma`, and returns a JSON STRING with three fields:

| Field | Description |
|---|---|
| `z` | Z-statistic: (x̄ − μ) / (σ / √n) |
| `p_one_tail` | Upper-tail probability: P(Z > z) |
| `p_two_tail` | Two-tail probability: P(\|Z\| > \|z\|) |

`STATS_ZTEST`:
- Skips NULL values in the `value` column; returns NULL for an all-NULL group
- Returns NULL when `sigma` ≤ 0 or was never supplied (all-NULL sigma column)
- Returns NULL when `sigma` is NaN
- Works with `GROUP BY`

`p_one_tail` is the upper-tail probability P(Z > z). When the sample mean is below μ (z < 0), this returns a value > 0.5 — indicating evidence against the upper-tail alternative. Use `p_two_tail` when you are testing for any deviation from μ rather than a directional hypothesis.

Use `CAST(STATS_ZTEST(...) AS CHAR)` to read results in the mysql CLI.

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

`STATS_COVARIANCE(x, y)` accepts one row per paired observation and returns a JSON STRING with two fields:

| Field | Description |
|---|---|
| `pop` | Population covariance σ_xy = C/n; 0.0 for n=1 |
| `samp` | Sample covariance s_xy = C/(n−1) (Bessel-corrected); null when n < 2 |

`STATS_COVARIANCE`:
- Uses Welford's single-pass streaming algorithm — O(1) memory, numerically stable
- Skips rows where either `x` or `y` is NULL (concurrent-pair discard)
- Returns NULL when all pairs are NULL
- Works with `GROUP BY`

Interpretation: positive covariance means x and y increase together; negative means they move in opposite directions; zero indicates no linear relationship.

Use `CAST(STATS_COVARIANCE(...) AS CHAR)` to read results in the mysql CLI.

### Means Family

`STATS_MEAN(value, trim_pct)` computes all four robust/ratio means in one pass and returns a JSON STRING:

| Field | Description |
|---|---|
| `trimmed` | Arithmetic mean after removing the bottom and top `trim_pct` fraction |
| `winsorized` | Arithmetic mean after replacing extremes with the boundary values |
| `geometric` | nth root of the product of all positive values; use for growth rates |
| `harmonic` | n / Σ(1/xᵢ); use for rates such as speed or throughput |

`STATS_MEAN`:
- `trimmed` and `winsorized` are null when `trim_pct` was never set (pass NULL), is invalid (< 0 or ≥ 0.5), or trims away all values
- `geometric` and `harmonic` are null when no positive values exist (non-positives are silently skipped)
- Returns NULL when no values were accumulated (all-NULL input)
- Works with `GROUP BY`

Pass `NULL` for `trim_pct` when only `geometric` and `harmonic` are needed.

Use `CAST(STATS_MEAN(...) AS CHAR)` to read results in the mysql CLI.

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

`STATS_ANOVA(value, group)` accepts any distinct numeric group label and returns a JSON STRING with all ANOVA table fields:

| Field | Description |
|---|---|
| `f` | F-statistic: MSB / MSW |
| `p` | P-value: P(F_{df_b,df_w} > F) |
| `ssb` | Between-group sum of squares |
| `ssw` | Within-group sum of squares (error) |
| `sst` | Total sum of squares (SSB + SSW) |
| `msb` | Mean square between: SSB / (k − 1) |
| `msw` | Mean square within: SSW / (N − k) |
| `df_b` | Between-group degrees of freedom: k − 1 |
| `df_w` | Within-group degrees of freedom: N − k |

`STATS_ANOVA`:
- Uses Welford's online algorithm for numerically stable within-group variance (O(1) memory per group)
- Skips NULL values in the `value` or `group` column
- Returns NULL when fewer than 2 distinct groups are present
- Returns NULL when any group has fewer than 2 non-NULL observations
- Returns NULL when within-group variance is zero (MSW = 0)
- Works with `GROUP BY`, computing an independent ANOVA per partition

The spec requires k ≥ 3 groups for a valid one-way ANOVA. k = 2 is mathematically equivalent to a t-test — use `STATS_TTEST` for two-group comparisons.

Use `CAST(STATS_ANOVA(...) AS CHAR)` to read results in the mysql CLI.

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
