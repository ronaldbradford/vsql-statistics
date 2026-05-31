# Testing vsql_statistics

## Prerequisites

- VillageSQL server running (check with `mysql -e "SELECT 1"`)
- Extension built and VEB copied to `veb_dir`
- MySQL Test Runner (`mysql-test-run.pl`) available in your VillageSQL installation

## Running the Test Suite

From your VillageSQL `mysql-test/` directory:

```bash
# Run all tests
perl mysql-test-run.pl --suite=/path/to/vsql-statistics/mysql-test

# Run a specific test
perl mysql-test-run.pl --suite=/path/to/vsql-statistics/mysql-test stats_iqr
```

## Recording Expected Results

If you add a new test or change an existing one, re-record the result file:

```bash
perl mysql-test-run.pl --suite=/path/to/vsql-statistics/mysql-test --record stats_iqr
```

Commit the updated `.result` file alongside the `.test` file.

## Test Coverage

| Test file | What it covers |
|---|---|
| `stats_iqr.test` | All six IQR functions; INT CAST workaround; single-row, two-row, and all-NULL edge cases; GROUP BY |
| `stats_ttest.test` | All seven t-test functions; reversed-group symmetry; INT CAST workaround; one-group, small-group, and all-NULL edge cases; custom alpha |
| `stats_mode.test` | All three mode functions; unimodal and bimodal datasets; all-unique and single-row NULL cases; all-NULL column; GROUP BY |
| `stats_skewness.test` | Both skewness functions; symmetric, right-skewed, and left-skewed datasets; all-NULL, single-row, and all-equal-value edge cases; GROUP BY; uses `vsql_test` database |
| `stats_ztest.test` | All three z-test functions; spec reference example (n=40); hand-verifiable Z=1.0 case; single-row; all-NULL; sigma=0; negative Z one-tail; GROUP BY; uses `vsql_test` database |

## Manual Spot-Check

```sql
INSTALL EXTENSION vsql_statistics;

CREATE TABLE espresso_sales (daily_count INT NOT NULL CHECK (daily_count >= 0));
INSERT INTO espresso_sales VALUES (7),(12),(15),(11),(4),(18),(14),(11),(30);

SELECT STATS_IQR(CAST(daily_count AS DOUBLE)) AS iqr FROM espresso_sales;
-- Expected: 7.5

SELECT STATS_IQR_LOWER_FENCE(CAST(daily_count AS DOUBLE)) AS lower,
       STATS_IQR_UPPER_FENCE(CAST(daily_count AS DOUBLE)) AS upper
FROM espresso_sales;
-- Expected: -2.25, 27.75

DROP TABLE espresso_sales;

-- t-test: two groups of 5 observations each, hand-verifiable (t=1.0, df=8)
CREATE TABLE ttest_data (value DOUBLE, grp INT);
INSERT INTO ttest_data VALUES
  (100,1),(110,1),(120,1),(130,1),(140,1),
  (90,2),(100,2),(110,2),(120,2),(130,2);

SELECT STATS_TTEST_T(value, grp)          AS t_stat     FROM ttest_data;  -- 1.0
SELECT STATS_TTEST_DF(value, grp)         AS df         FROM ttest_data;  -- 8.0
SELECT STATS_TTEST_P_TWO_TAIL(value, grp) AS p_two_tail FROM ttest_data;  -- 0.3466

DROP TABLE ttest_data;

-- Mode: unimodal returns single-element array; bimodal returns both values
-- Note: STATS_MODE returns a binary STRING in VEF 0.0.4; use CAST AS CHAR or
--       connect with mysql --skip-binary-as-hex to see text instead of hex.
CREATE TABLE mode_data (val INT NOT NULL);
INSERT INTO mode_data VALUES (12),(15),(12),(18),(21),(15),(15),(14);
SELECT CAST(STATS_MODE(CAST(val AS DOUBLE)) AS CHAR) AS modes FROM mode_data;  -- [15]

DELETE FROM mode_data;
INSERT INTO mode_data VALUES (24),(29),(24),(35),(42),(29),(38),(22);
SELECT CAST(STATS_MODE(CAST(val AS DOUBLE)) AS CHAR) AS modes     FROM mode_data;  -- [24, 29]
SELECT STATS_MODE_MIN(CAST(val AS DOUBLE))           AS mode_low  FROM mode_data;  -- 24
SELECT STATS_MODE_MAX(CAST(val AS DOUBLE))           AS mode_high FROM mode_data;  -- 29

DROP TABLE mode_data;

-- Skewness: symmetric returns 0; right-skewed returns positive; Pearson cross-check
CREATE TABLE skew_data (val DOUBLE);
INSERT INTO skew_data VALUES (1),(2),(3),(4),(5);
SELECT STATS_SKEWNESS(val) AS skewness FROM skew_data;          -- 0

DELETE FROM skew_data;
INSERT INTO skew_data VALUES (2),(4),(4),(4),(5),(5),(7),(9);
SELECT STATS_SKEWNESS(val)         AS skewness         FROM skew_data;  -- 0.65625
SELECT STATS_SKEWNESS_PEARSON(val) AS skewness_pearson FROM skew_data;  -- 0.75

DROP TABLE skew_data;

-- Z-test: spec reference example (n=40, mu=500, sigma=40, mean=511.0775 → Z≈1.7515)
CREATE TABLE ztest_data (val DOUBLE);
INSERT INTO ztest_data VALUES
  (511.0775),(511.0775),(511.0775),(511.0775),(511.0775),
  (511.0775),(511.0775),(511.0775),(511.0775),(511.0775),
  (511.0775),(511.0775),(511.0775),(511.0775),(511.0775),
  (511.0775),(511.0775),(511.0775),(511.0775),(511.0775),
  (511.0775),(511.0775),(511.0775),(511.0775),(511.0775),
  (511.0775),(511.0775),(511.0775),(511.0775),(511.0775),
  (511.0775),(511.0775),(511.0775),(511.0775),(511.0775),
  (511.0775),(511.0775),(511.0775),(511.0775),(511.0775);
SELECT ROUND(STATS_ZTEST_Z(val, 500.0, 40.0), 4)          AS z        FROM ztest_data;  -- 1.7515
SELECT ROUND(STATS_ZTEST_P_TWO_TAIL(val, 500.0, 40.0), 4) AS p_two    FROM ztest_data;  -- 0.0799
SELECT ROUND(STATS_ZTEST_P_ONE_TAIL(val, 500.0, 40.0), 4) AS p_one    FROM ztest_data;  -- 0.0399

DROP TABLE ztest_data;
UNINSTALL EXTENSION vsql_statistics;
```
