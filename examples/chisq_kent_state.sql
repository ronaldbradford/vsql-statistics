/*
  Chi-squared tests: Kent State University SPSS examples
  Source: https://libguides.library.kent.edu/spss/chisquare

  Example 1 — Test of independence: smoking behavior by gender (3×2 table)
    H₀: Smoking behavior is independent of gender
    Expected: chi_sq≈3.171, df=2, p≈0.205 → Retain null at α=0.05

  Example 2 — Test of independence: class rank by on-campus living (2×2 table)
    H₀: Class rank is independent of living on campus
    Expected: chi_sq≈138.926, df=1, p<0.001 → Reject null at α=0.05
*/

INSTALL EXTENSION vsql_statistics;

-- ============================================================================
-- Example 1: Smoking behavior by gender (3 rows × 2 cols)
-- ============================================================================
-- Observed counts from the survey:
--                 Male  Female  Total
--   Nonsmoker      149     148    297
--   Past smoker     13      24     37
--   Current smoker  31      37     68
--   Total          193     209    402
--
-- Expected = (row_total × col_total) / grand_total

DROP TABLE IF EXISTS smoking_gender;

CREATE TABLE smoking_gender (
    smoking_status VARCHAR(20) NOT NULL,
    gender         VARCHAR(10) NOT NULL,
    observed       DOUBLE      NOT NULL,
    expected       DOUBLE      NOT NULL
);

INSERT INTO smoking_gender VALUES
    ('Nonsmoker',       'Male',   149, 297 * 193 / 402),
    ('Nonsmoker',       'Female', 148, 297 * 209 / 402),
    ('Past smoker',     'Male',    13,  37 * 193 / 402),
    ('Past smoker',     'Female',  24,  37 * 209 / 402),
    ('Current smoker',  'Male',    31,  68 * 193 / 402),
    ('Current smoker',  'Female',  37,  68 * 209 / 402);

WITH indep AS (
    SELECT CAST(STATS_CHISQ_INDEP(observed, expected, 3.0, 2.0) AS CHAR(200)) AS json
    FROM smoking_gender
)
SELECT
    JSON_EXTRACT(json, '$.chi_sq') AS chi_squared,
    JSON_EXTRACT(json, '$.df')     AS degrees_of_freedom,
    JSON_EXTRACT(json, '$.p')      AS p_value,
    IF(JSON_EXTRACT(json, '$.p') < 0.05,
       'Reject Null — smoking behavior IS associated with gender',
       'Retain Null — no association between smoking behavior and gender') AS conclusion
FROM indep\G

DROP TABLE smoking_gender;

-- ============================================================================
-- Example 2: Class rank by on-campus living (2 rows × 2 cols)
-- ============================================================================
-- Observed counts from the survey:
--                  Off-campus  On-campus  Total
--   Underclassman          79        148    227
--   Upperclassman         152          9    161
--   Total                 231        157    388
--
-- Expected = (row_total × col_total) / grand_total

DROP TABLE IF EXISTS class_rank_living;

CREATE TABLE class_rank_living (
    class_rank  VARCHAR(15) NOT NULL,
    living      VARCHAR(12) NOT NULL,
    observed    DOUBLE      NOT NULL,
    expected    DOUBLE      NOT NULL
);

INSERT INTO class_rank_living VALUES
    ('Underclassman', 'Off-campus', 79,  227 * 231 / 388),
    ('Underclassman', 'On-campus',  148, 227 * 157 / 388),
    ('Upperclassman', 'Off-campus', 152, 161 * 231 / 388),
    ('Upperclassman', 'On-campus',    9, 161 * 157 / 388);

WITH indep AS (
    SELECT CAST(STATS_CHISQ_INDEP(observed, expected, 2.0, 2.0) AS CHAR(200)) AS json
    FROM class_rank_living
)
SELECT
    JSON_EXTRACT(json, '$.chi_sq') AS chi_squared,
    JSON_EXTRACT(json, '$.df')     AS degrees_of_freedom,
    JSON_EXTRACT(json, '$.p')      AS p_value,
    IF(JSON_EXTRACT(json, '$.p') < 0.05,
       'Reject Null — class rank IS associated with living on campus',
       'Retain Null — class rank is independent of living on campus') AS conclusion
FROM indep\G

DROP TABLE class_rank_living;

UNINSTALL EXTENSION vsql_statistics;
