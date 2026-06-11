/*
  Chi-square tests: numiqo tutorial examples
  Source: https://numiqo.com/tutorial/chi-square-test

  Four examples covering the three main chi-square test types:

  Example 1 — Generic 2×2 with specified expected values
    Two categorical variables (A/B × A/B), expected frequencies given directly.
    Expected: chi_sq≈0.635, df=1 → Retain null (critical value 3.841 at α=0.05)

  Example 2 — Chi-square test of independence: Netflix subscription × gender (2×2)
    H₀: Gender and Netflix subscription are independent.
    Expected computed from marginals: row_total × col_total / N (N=52)
    Expected: chi_sq≈0.349, df=1 → Retain null

  Example 3 — Chi-square goodness-of-fit: streaming service market share
    Observed frequencies from a Berlin survey vs expected from all-Germany distribution.
    Expected: chi_sq≈1.264, df=3 → Retain null (critical value 7.815 at α=0.05)

  Example 4 — Chi-square homogeneity test: streaming services by age group (4×3)
    H₀: Streaming service preferences are the same across all age groups.
    Expected computed from marginals (N=262).
    Expected: chi_sq≈2.934, df=6 → Retain null (critical value 12.592 at α=0.05)
*/

INSTALL EXTENSION vsql_statistics;

-- ============================================================================
-- Example 1: Generic 2×2 with directly specified expected values
-- ============================================================================
-- Variable 1 (rows): Category A / Category B
-- Variable 2 (cols): Category A / Category B
-- Expected frequencies are given directly (not derived from marginals).
--
--              Cat A  Cat B
--   Var1 A:     10     13    (expected: 9,  11)
--   Var1 B:     13     14    (expected: 12, 13)

DROP TABLE IF EXISTS generic_2x2;

CREATE TABLE generic_2x2 (
    row_cat  CHAR(1) NOT NULL,
    col_cat  CHAR(1) NOT NULL,
    observed DOUBLE  NOT NULL,
    expected DOUBLE  NOT NULL
);

INSERT INTO generic_2x2 VALUES
    ('A', 'A', 10,  9),
    ('A', 'B', 13, 11),
    ('B', 'A', 13, 12),
    ('B', 'B', 14, 13);

WITH indep AS (
    SELECT CAST(STATS_CHISQ_INDEP(observed, expected, 2.0, 2.0) AS CHAR(200)) AS json
    FROM generic_2x2
)
SELECT
    JSON_EXTRACT(json, '$.chi_sq') AS chi_squared,
    JSON_EXTRACT(json, '$.df')     AS degrees_of_freedom,
    JSON_EXTRACT(json, '$.p')      AS p_value,
    IF(JSON_EXTRACT(json, '$.p') < 0.05,
       'Reject H₀ — significant difference from expected frequencies',
       'Retain H₀ — no significant difference from expected frequencies') AS conclusion
FROM indep\G

DROP TABLE generic_2x2;

-- ============================================================================
-- Example 2: Independence test — Netflix subscription × gender (2×2)
-- ============================================================================
-- Survey of 52 people (25 male, 27 female):
--                Male  Female  Total
--   Netflix Yes:   10      13     23
--   Netflix No:    15      14     29
--   Total:         25      27     52
--
-- Expected = (row_total × col_total) / 52

DROP TABLE IF EXISTS netflix_gender;

CREATE TABLE netflix_gender (
    netflix    VARCHAR(5)  NOT NULL,
    gender     VARCHAR(10) NOT NULL,
    observed   DOUBLE      NOT NULL,
    expected   DOUBLE      NOT NULL
);

INSERT INTO netflix_gender VALUES
    ('Yes', 'Male',   10, 23 * 25 / 52),
    ('Yes', 'Female', 13, 23 * 27 / 52),
    ('No',  'Male',   15, 29 * 25 / 52),
    ('No',  'Female', 14, 29 * 27 / 52);

WITH indep AS (
    SELECT CAST(STATS_CHISQ_INDEP(observed, expected, 2.0, 2.0) AS CHAR(200)) AS json
    FROM netflix_gender
)
SELECT
    JSON_EXTRACT(json, '$.chi_sq') AS chi_squared,
    JSON_EXTRACT(json, '$.df')     AS degrees_of_freedom,
    JSON_EXTRACT(json, '$.p')      AS p_value,
    IF(JSON_EXTRACT(json, '$.p') < 0.05,
       'Reject H₀ — gender IS associated with Netflix subscription',
       'Retain H₀ — gender and Netflix subscription are independent') AS conclusion
FROM indep\G

DROP TABLE netflix_gender;

-- ============================================================================
-- Example 3: Goodness-of-fit — streaming service market share, Berlin vs Germany
-- ============================================================================
-- Research question: Does streaming service market share in Berlin differ from
-- the national (all-Germany) distribution?
--
-- Observed (Berlin survey):  Netflix=25, Amazon=29, Disney=13, Other/None=20
-- Expected (all Germany):    Netflix=23, Amazon=26, Disney=16, Other/None=22

DROP TABLE IF EXISTS streaming_market;

CREATE TABLE streaming_market (
    service  VARCHAR(12) NOT NULL,
    observed DOUBLE      NOT NULL,
    expected DOUBLE      NOT NULL
);

INSERT INTO streaming_market VALUES
    ('Netflix',    25, 23),
    ('Amazon',     29, 26),
    ('Disney',     13, 16),
    ('Other/None', 20, 22);

WITH gof AS (
    SELECT CAST(STATS_CHISQ_GOF(observed, expected) AS CHAR(200)) AS json
    FROM streaming_market
)
SELECT
    JSON_EXTRACT(json, '$.chi_sq') AS chi_squared,
    JSON_EXTRACT(json, '$.df')     AS degrees_of_freedom,
    JSON_EXTRACT(json, '$.p')      AS p_value,
    IF(JSON_EXTRACT(json, '$.p') < 0.05,
       'Reject H₀ — Berlin streaming share differs from all-Germany distribution',
       'Retain H₀ — Berlin streaming share matches all-Germany distribution') AS conclusion
FROM gof\G

DROP TABLE streaming_market;

-- ============================================================================
-- Example 4: Homogeneity test — streaming services by age group (4×3)
-- ============================================================================
-- Research question: Do streaming service preferences differ across age groups?
-- Survey of 262 people across three age bands and four service categories.
--
--              15-25  25-35  35-45  Total
--   Netflix:     25     23     20     68
--   Amazon:      29     30     33     92
--   Disney:      11     13     12     36
--   Other/None:  16     24     26     66
--   Total:       81     90     91    262
--
-- Expected = (row_total × col_total) / 262

DROP TABLE IF EXISTS streaming_by_age;

CREATE TABLE streaming_by_age (
    service    VARCHAR(12) NOT NULL,
    age_group  VARCHAR(10) NOT NULL,
    observed   DOUBLE      NOT NULL,
    expected   DOUBLE      NOT NULL
);

INSERT INTO streaming_by_age VALUES
    ('Netflix',    '15-25', 25, 68 *  81 / 262),
    ('Netflix',    '25-35', 23, 68 *  90 / 262),
    ('Netflix',    '35-45', 20, 68 *  91 / 262),
    ('Amazon',     '15-25', 29, 92 *  81 / 262),
    ('Amazon',     '25-35', 30, 92 *  90 / 262),
    ('Amazon',     '35-45', 33, 92 *  91 / 262),
    ('Disney',     '15-25', 11, 36 *  81 / 262),
    ('Disney',     '25-35', 13, 36 *  90 / 262),
    ('Disney',     '35-45', 12, 36 *  91 / 262),
    ('Other/None', '15-25', 16, 66 *  81 / 262),
    ('Other/None', '25-35', 24, 66 *  90 / 262),
    ('Other/None', '35-45', 26, 66 *  91 / 262);

WITH indep AS (
    SELECT CAST(STATS_CHISQ_INDEP(observed, expected, 4.0, 3.0) AS CHAR(200)) AS json
    FROM streaming_by_age
)
SELECT
    JSON_EXTRACT(json, '$.chi_sq') AS chi_squared,
    JSON_EXTRACT(json, '$.df')     AS degrees_of_freedom,
    JSON_EXTRACT(json, '$.p')      AS p_value,
    IF(JSON_EXTRACT(json, '$.p') < 0.05,
       'Reject H₀ — streaming preferences differ significantly across age groups',
       'Retain H₀ — streaming preferences are homogeneous across age groups') AS conclusion
FROM indep\G

DROP TABLE streaming_by_age;

UNINSTALL EXTENSION vsql_statistics;
