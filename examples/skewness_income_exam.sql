/*
  Skewness: positive (right-skewed) and negative (left-skewed) distributions
  Function: STATS_SKEWNESS returns JSON {"moment": g1, "pearson": p}

  STATS_SKEWNESS returns two measures:
    moment  — population moment skewness g₁ = m₃ / m₂^(3/2)
                where m₂ and m₃ are the 2nd and 3rd central moments
    pearson — Pearson's second skewness coefficient = 3 × (mean − median) / σ

  Interpretation:
    g₁ > 0 → positive skew: long right tail, most values below the mean
              (mean > median; outliers pull the mean upward)
    g₁ = 0 → symmetric distribution (mean ≈ median)
    g₁ < 0 → negative skew: long left tail, most values above the mean
              (mean < median; outliers pull the mean downward)

  Rule of thumb:
    |g₁| < 0.5   → approximately symmetric
    0.5 ≤ |g₁| < 1 → moderate skew
    |g₁| ≥ 1     → high skew

  Example 1 — Annual household income (£000s), n=15
    Right-skewed: most households earn £25k–£60k, a few high earners reach £80k–£120k.
    The high earners pull the mean above the median.
    Expected: moment g₁ ≈ +1.89, Pearson ≈ +0.97 (high positive skew)

  Example 2 — End-of-term exam scores (/100), n=15
    Left-skewed: most students score 70–98, one student scored only 20.
    The low outlier pulls the mean below the median.
    Expected: moment g₁ ≈ −1.79, Pearson ≈ −0.56 (moderate-high negative skew)
*/

INSTALL EXTENSION vsql_statistics;

DROP TABLE IF EXISTS survey_data;

CREATE TABLE survey_data (
    cohort   VARCHAR(12) NOT NULL,   -- 'income' or 'exam'
    value    DOUBLE      NOT NULL
);

-- Household income in £000s: typical values 25-60 with two high-earning outliers
INSERT INTO survey_data VALUES
    ('income',  25), ('income',  28), ('income',  30), ('income',  32),
    ('income',  35), ('income',  35), ('income',  38), ('income',  40),
    ('income',  42), ('income',  45), ('income',  50), ('income',  55),
    ('income',  60), ('income',  80), ('income', 120);

-- Exam scores /100: most students 70-98 with one very low outlier at 20
INSERT INTO survey_data VALUES
    ('exam',  20), ('exam',  55), ('exam',  70), ('exam',  72),
    ('exam',  75), ('exam',  78), ('exam',  80), ('exam',  82),
    ('exam',  85), ('exam',  88), ('exam',  90), ('exam',  92),
    ('exam',  95), ('exam',  96), ('exam',  98);

-- ============================================================================
-- Skewness: moment g₁ and Pearson coefficient per cohort
-- ============================================================================
-- STATS_SKEWNESS uses StatsState. Do not mix with IQR/median functions
-- in the same SELECT — they share the same accumulator type.

WITH skew AS (
    SELECT
        cohort,
        COUNT(*)                                 AS n,
        ROUND(AVG(value), 3)                     AS mean,
        CAST(STATS_SKEWNESS(value) AS CHAR(200)) AS json
    FROM survey_data
    GROUP BY cohort
)
SELECT
    cohort,
    n,
    mean,
    ROUND(JSON_EXTRACT(json, '$.moment'),  4)  AS moment_skewness_g1,
    ROUND(JSON_EXTRACT(json, '$.pearson'), 4)  AS pearson_skewness,
    CASE
        WHEN JSON_EXTRACT(json, '$.moment') >  0.5 THEN 'Positive skew — long right tail (mean > median)'
        WHEN JSON_EXTRACT(json, '$.moment') < -0.5 THEN 'Negative skew — long left tail  (mean < median)'
        ELSE                                             'Approximately symmetric'
    END                                        AS interpretation
FROM skew
ORDER BY cohort;

-- ============================================================================
-- Supporting descriptives: quartiles per cohort (separate query)
-- ============================================================================
-- Run in a separate SELECT so StatsState is not shared with STATS_SKEWNESS above.

WITH iqr AS (
    SELECT cohort, CAST(STATS_IQR(value) AS CHAR(300)) AS json
    FROM survey_data
    GROUP BY cohort
)
SELECT
    cohort,
    ROUND(JSON_EXTRACT(json, '$.q1'),          2) AS q1,
    ROUND(JSON_EXTRACT(json, '$.median'),      2) AS median,
    ROUND(JSON_EXTRACT(json, '$.q3'),          2) AS q3,
    ROUND(JSON_EXTRACT(json, '$.iqr'),         2) AS iqr,
    ROUND(JSON_EXTRACT(json, '$.lower_fence'), 2) AS lower_fence,
    ROUND(JSON_EXTRACT(json, '$.upper_fence'), 2) AS upper_fence
FROM iqr
ORDER BY cohort;

DROP TABLE survey_data;

UNINSTALL EXTENSION vsql_statistics;
