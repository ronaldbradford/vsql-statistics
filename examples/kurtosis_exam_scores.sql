/*
  Kurtosis: leptokurtic, mesokurtic, and platykurtic distributions
  Function: STATS_KURTOSIS returns JSON {"kurtosis": β₂, "excess": g₂}

  Context: exam scores (0–100) from three class sections, each with 10 students.
  All three sections have the same mean (50) and the same n (10), but their score
  distributions have very different shapes — demonstrating the three kurtosis types.

  Kurtosis measures the "tailedness" of a distribution:
    β₂ > 3  → leptokurtic: sharp peak, heavy tails (more extreme scores than normal)
    β₂ ≈ 3  → mesokurtic:  normal-like distribution (bell-shaped)
    β₂ < 3  → platykurtic: flat peak, light tails (scores spread evenly)

  STATS_KURTOSIS returns a JSON object with two fields:
    kurtosis — population kurtosis β₂ = m₄ / m₂²  (normal distribution = 3.0)
    excess   — Fisher-Pearson sample excess kurtosis g₂ ≈ β₂ − 3
               (normal distribution = 0; negative → platykurtic; null when n < 4)

  Datasets (all: n=10, mean=50):

    Section A — Leptokurtic (β₂ ≈ 4.54, g₂ ≈ 3.69)
      Scores cluster tightly around 50 with two outliers at 40 and 60.
      High peak, heavy tails: most students scored near the mean, a few far away.

    Section B — Mesokurtic (β₂ ≈ 3.02, g₂ ≈ 1.01)
      Scores taper symmetrically away from 50 in even steps of 4.
      Normal-like bell shape: moderate peak, moderate tails.

    Section C — Platykurtic (β₂ ≈ 1.78, g₂ ≈ −1.20)
      Scores evenly spaced from 32 to 68 (arithmetic progression, step=4).
      Flat, uniform-like shape: no dominant peak, light tails.
*/

INSTALL EXTENSION vsql_statistics;

DROP TABLE IF EXISTS exam_scores;

CREATE TABLE exam_scores (
    section CHAR(1) NOT NULL,   -- 'A', 'B', or 'C'
    score   DOUBLE  NOT NULL
);

-- Section A: leptokurtic — concentrated near 50 with two outliers
INSERT INTO exam_scores VALUES
    ('A', 40), ('A', 48), ('A', 49), ('A', 50), ('A', 50),
    ('A', 50), ('A', 50), ('A', 51), ('A', 52), ('A', 60);

-- Section B: mesokurtic — symmetric steps of 4, 8, 16 from centre
INSERT INTO exam_scores VALUES
    ('B', 34), ('B', 42), ('B', 46), ('B', 48), ('B', 50),
    ('B', 50), ('B', 52), ('B', 54), ('B', 58), ('B', 66);

-- Section C: platykurtic — uniform arithmetic progression 32..68 step 4
INSERT INTO exam_scores VALUES
    ('C', 32), ('C', 36), ('C', 40), ('C', 44), ('C', 48),
    ('C', 52), ('C', 56), ('C', 60), ('C', 64), ('C', 68);

-- ============================================================================
-- Kurtosis results by section
-- ============================================================================

WITH kurt AS (
    SELECT section,
           COUNT(*)                                    AS n,
           AVG(score)                                  AS mean,
           CAST(STATS_KURTOSIS(score) AS CHAR(200))    AS json
    FROM exam_scores
    GROUP BY section
)
SELECT
    section,
    n,
    ROUND(mean, 1)                                              AS mean,
    ROUND(JSON_EXTRACT(json, '$.kurtosis'), 4)                  AS kurtosis_beta2,
    ROUND(JSON_EXTRACT(json, '$.excess'),   4)                  AS excess_kurtosis_g2,
    CASE
        WHEN JSON_EXTRACT(json, '$.kurtosis') > 3 THEN 'Leptokurtic — sharp peak, heavy tails'
        WHEN JSON_EXTRACT(json, '$.kurtosis') < 3 THEN 'Platykurtic — flat peak, light tails'
        ELSE                                           'Mesokurtic  — normal-like distribution'
    END                                                         AS shape
FROM kurt
ORDER BY section;

-- ============================================================================
-- Supporting descriptives: spread and quartiles per section
-- ============================================================================

WITH iqr AS (
    SELECT section, CAST(STATS_IQR(score) AS CHAR(300)) AS json
    FROM exam_scores
    GROUP BY section
)
SELECT
    section,
    ROUND(JSON_EXTRACT(json, '$.median'),      2) AS median,
    ROUND(JSON_EXTRACT(json, '$.q1'),          2) AS q1,
    ROUND(JSON_EXTRACT(json, '$.q3'),          2) AS q3,
    ROUND(JSON_EXTRACT(json, '$.iqr'),         2) AS iqr,
    ROUND(JSON_EXTRACT(json, '$.lower_fence'), 2) AS lower_fence,
    ROUND(JSON_EXTRACT(json, '$.upper_fence'), 2) AS upper_fence
FROM iqr
ORDER BY section;

DROP TABLE exam_scores;

UNINSTALL EXTENSION vsql_statistics;
