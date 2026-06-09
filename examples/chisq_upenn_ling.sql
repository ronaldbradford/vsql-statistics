/*
  Chi-squared tests of independence: UPenn Linguistics 300 tutorial examples
  Source: https://www.ling.upenn.edu/~clight/chisquared.htm
  Tutorial: Pearson's Chi-square Test for Independence (Ling 300, Fall 2008)

  Example 1 — Gender × Party affiliation (2×2 table)
    H₀: Party affiliation is independent of gender
    Observed: Male/Dem=20, Male/Rep=30, Female/Dem=30, Female/Rep=20
    Expected (row×col/grand): all cells = 50*50/100 = 25
    Expected: chi_sq=4, df=1, p≈0.0455 → borderline, not conclusive at α=0.05

  Example 2 — Class attendance × Exam outcome (2×2 table)
    H₀: Exam outcome is independent of class attendance
    Observed: Attended/Pass=25, Attended/Fail=6, Skipped/Pass=8, Skipped/Fail=15
    Row totals: Attended=31, Skipped=23; Col totals: Pass=33, Fail=21; Grand=54
    Expected (row×col/grand): 18.94, 12.06, 14.06, 8.94
    Expected: chi_sq≈11.686, df=1, p≈0.0006 → Reject null at α=0.05
*/

INSTALL EXTENSION vsql_statistics;

-- ============================================================================
-- Example 1: Gender × Party affiliation (2 rows × 2 cols)
-- ============================================================================
-- Survey of 100 individuals:
--             Democrat  Republican  Total
--   Male            20          30     50
--   Female          30          20     50
--   Total           50          50    100
--
-- Expected = (row_total × col_total) / grand_total = 50*50/100 = 25 for all cells

DROP TABLE IF EXISTS gender_party;

CREATE TABLE gender_party (
    gender  VARCHAR(10) NOT NULL,
    party   VARCHAR(12) NOT NULL,
    observed DOUBLE     NOT NULL,
    expected DOUBLE     NOT NULL
);

INSERT INTO gender_party VALUES
    ('Male',   'Democrat',   20, 50 * 50 / 100),
    ('Male',   'Republican', 30, 50 * 50 / 100),
    ('Female', 'Democrat',   30, 50 * 50 / 100),
    ('Female', 'Republican', 20, 50 * 50 / 100);

WITH indep AS (
    SELECT CAST(STATS_CHISQ_INDEP(observed, expected, 2.0, 2.0) AS CHAR(200)) AS json
    FROM gender_party
)
SELECT
    JSON_EXTRACT(json, '$.chi_sq') AS chi_squared,
    JSON_EXTRACT(json, '$.df')     AS degrees_of_freedom,
    JSON_EXTRACT(json, '$.p')      AS p_value,
    IF(JSON_EXTRACT(json, '$.p') < 0.05,
       'Reject Null — party affiliation IS associated with gender',
       'Retain Null — no significant association between gender and party affiliation') AS conclusion
FROM indep\G

DROP TABLE gender_party;

-- ============================================================================
-- Example 2: Class attendance × Exam outcome (2 rows × 2 cols)
-- ============================================================================
-- Survey of 54 students:
--              Pass  Fail  Total
--   Attended     25     6     31
--   Skipped       8    15     23
--   Total        33    21     54
--
-- Expected = (row_total × col_total) / grand_total

DROP TABLE IF EXISTS attendance_exam;

CREATE TABLE attendance_exam (
    attendance VARCHAR(10) NOT NULL,
    outcome    VARCHAR(10) NOT NULL,
    observed   DOUBLE      NOT NULL,
    expected   DOUBLE      NOT NULL
);

INSERT INTO attendance_exam VALUES
    ('Attended', 'Pass', 25, 31 * 33 / 54),
    ('Attended', 'Fail',  6, 31 * 21 / 54),
    ('Skipped',  'Pass',  8, 23 * 33 / 54),
    ('Skipped',  'Fail', 15, 23 * 21 / 54);

WITH indep AS (
    SELECT CAST(STATS_CHISQ_INDEP(observed, expected, 2.0, 2.0) AS CHAR(200)) AS json
    FROM attendance_exam
)
SELECT
    JSON_EXTRACT(json, '$.chi_sq') AS chi_squared,
    JSON_EXTRACT(json, '$.df')     AS degrees_of_freedom,
    JSON_EXTRACT(json, '$.p')      AS p_value,
    IF(JSON_EXTRACT(json, '$.p') < 0.05,
       'Reject Null — exam outcome IS associated with class attendance',
       'Retain Null — exam outcome is independent of class attendance') AS conclusion
FROM indep\G

DROP TABLE attendance_exam;

UNINSTALL EXTENSION vsql_statistics;
