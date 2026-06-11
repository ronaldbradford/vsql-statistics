/*
  One-sample Z-test examples

  STATS_ZTEST(value, mu, sigma) tests whether a sample mean differs from a
  known population mean (mu) given a known population standard deviation (sigma).
  Pass mu and sigma as constants repeated on every row; the function accumulates
  the sample values and uses the last non-null mu/sigma seen.

  Returns JSON: {"z": ..., "p_one_tail": ..., "p_two_tail": ...}
    z          — (x̄ − μ) / (σ / √n)
    p_one_tail — P(Z > z): upper-tail probability
    p_two_tail — P(|Z| > |z|): two-tail probability

  Directional (one-tailed) testing:
    H₁: μ > μ₀  →  use p_one_tail directly (reject when small)
    H₁: μ < μ₀  →  use 1 − p_one_tail    (reject when small)

  Two examples:

  1. Soft drink fill quality control
     A line targeting 500 ml with σ=8 ml (known from long-run data).
     25 bottles sampled; systematic underfill detected.
     H₀: μ = 500   H₁: μ ≠ 500 (two-tail) and H₁: μ < 500 (one-tail lower)
     Expected: z ≈ −2.75, p_two_tail ≈ 0.0060 → reject H₀ at α=0.05

  2. School reading scores vs national average
     National reading benchmark: μ=72, σ=11 (30 students per school).
     Three schools tested; results range from significantly above to
     significantly below the national average.
     Expected:
       Riverside — z ≈  2.64, p_two ≈ 0.0083 → above average
       Central   — z ≈  0.25, p_two ≈ 0.8034 → no significant difference
       Highland  — z ≈ −3.90, p_two ≈ 0.0001 → below average
*/

INSTALL EXTENSION vsql_statistics;

-- ============================================================================
-- Example 1: Soft drink fill quality control
-- ============================================================================

DROP TABLE IF EXISTS bottle_fill;

CREATE TABLE bottle_fill (
    bottle_id INT    NOT NULL,
    volume_ml DOUBLE NOT NULL
);

-- 25 bottles from a single production run; target 500 ml, process σ=8 ml
-- Sample mean: 495.60 ml
INSERT INTO bottle_fill VALUES
    ( 1, 488), ( 2, 490), ( 3, 491), ( 4, 492), ( 5, 492),
    ( 6, 493), ( 7, 493), ( 8, 494), ( 9, 494), (10, 495),
    (11, 495), (12, 495), (13, 496), (14, 496), (15, 496),
    (16, 496), (17, 497), (18, 497), (19, 498), (20, 498),
    (21, 499), (22, 499), (23, 500), (24, 501), (25, 505);

-- Step 1: sample descriptives
SELECT COUNT(*) AS n, ROUND(AVG(volume_ml), 2) AS sample_mean
FROM bottle_fill;

-- Step 2: Z-test against fill target
WITH ztest AS (
    SELECT CAST(STATS_ZTEST(volume_ml, 500.0, 8.0) AS CHAR(300)) AS json
    FROM bottle_fill
)
SELECT
    ROUND(JSON_EXTRACT(json, '$.z'),          6) AS z_statistic,      -- expected: -2.750000
    ROUND(JSON_EXTRACT(json, '$.p_one_tail'), 6) AS p_one_tail,       -- P(Z > z) ≈ 0.997020
    ROUND(1 - JSON_EXTRACT(json, '$.p_one_tail'), 6) AS p_lower_tail, -- P(Z < z) ≈ 0.002980
    ROUND(JSON_EXTRACT(json, '$.p_two_tail'), 6) AS p_two_tail,       -- expected:  0.005960
    IF(JSON_EXTRACT(json, '$.p_two_tail') < 0.05,
       'Reject H₀ — fill volume differs significantly from 500 ml target',
       'Retain H₀ — no significant deviation from 500 ml target') AS two_tail_conclusion,
    IF(1 - JSON_EXTRACT(json, '$.p_one_tail') < 0.05,
       'Reject H₀ — significant underfill detected (μ < 500)',
       'Retain H₀ — no significant underfill') AS lower_tail_conclusion
FROM ztest\G

DROP TABLE bottle_fill;

-- ============================================================================
-- Example 2: School reading scores vs national benchmark (GROUP BY)
-- ============================================================================

DROP TABLE IF EXISTS reading_scores;

CREATE TABLE reading_scores (
    school  VARCHAR(20) NOT NULL,
    student INT         NOT NULL,
    score   DOUBLE      NOT NULL
);

-- National benchmark: μ=72, σ=11; 30 students per school
-- Riverside: mean=77.30 — above national average
INSERT INTO reading_scores VALUES
    ('Riverside',  1, 70), ('Riverside',  2, 71), ('Riverside',  3, 72),
    ('Riverside',  4, 73), ('Riverside',  5, 74), ('Riverside',  6, 74),
    ('Riverside',  7, 75), ('Riverside',  8, 75), ('Riverside',  9, 75),
    ('Riverside', 10, 76), ('Riverside', 11, 76), ('Riverside', 12, 76),
    ('Riverside', 13, 76), ('Riverside', 14, 77), ('Riverside', 15, 77),
    ('Riverside', 16, 77), ('Riverside', 17, 77), ('Riverside', 18, 78),
    ('Riverside', 19, 78), ('Riverside', 20, 78), ('Riverside', 21, 79),
    ('Riverside', 22, 79), ('Riverside', 23, 80), ('Riverside', 24, 80),
    ('Riverside', 25, 81), ('Riverside', 26, 81), ('Riverside', 27, 82),
    ('Riverside', 28, 83), ('Riverside', 29, 84), ('Riverside', 30, 85);

-- Central: mean=72.50 — at national average
INSERT INTO reading_scores VALUES
    ('Central',  1, 60), ('Central',  2, 62), ('Central',  3, 63),
    ('Central',  4, 65), ('Central',  5, 65), ('Central',  6, 66),
    ('Central',  7, 67), ('Central',  8, 68), ('Central',  9, 68),
    ('Central', 10, 69), ('Central', 11, 70), ('Central', 12, 71),
    ('Central', 13, 72), ('Central', 14, 72), ('Central', 15, 72),
    ('Central', 16, 73), ('Central', 17, 73), ('Central', 18, 74),
    ('Central', 19, 75), ('Central', 20, 75), ('Central', 21, 76),
    ('Central', 22, 76), ('Central', 23, 77), ('Central', 24, 78),
    ('Central', 25, 79), ('Central', 26, 79), ('Central', 27, 80),
    ('Central', 28, 81), ('Central', 29, 83), ('Central', 30, 86);

-- Highland: mean=64.17 — below national average
INSERT INTO reading_scores VALUES
    ('Highland',  1, 50), ('Highland',  2, 52), ('Highland',  3, 53),
    ('Highland',  4, 55), ('Highland',  5, 56), ('Highland',  6, 57),
    ('Highland',  7, 58), ('Highland',  8, 59), ('Highland',  9, 60),
    ('Highland', 10, 61), ('Highland', 11, 62), ('Highland', 12, 63),
    ('Highland', 13, 63), ('Highland', 14, 64), ('Highland', 15, 64),
    ('Highland', 16, 65), ('Highland', 17, 65), ('Highland', 18, 66),
    ('Highland', 19, 66), ('Highland', 20, 67), ('Highland', 21, 68),
    ('Highland', 22, 68), ('Highland', 23, 69), ('Highland', 24, 70),
    ('Highland', 25, 71), ('Highland', 26, 71), ('Highland', 27, 72),
    ('Highland', 28, 74), ('Highland', 29, 76), ('Highland', 30, 80);

-- Step 1: sample descriptives per school
SELECT school, COUNT(*) AS n, ROUND(AVG(score), 2) AS sample_mean
FROM reading_scores
GROUP BY school
ORDER BY school;

-- Step 2: Z-test vs national benchmark per school
WITH ztest AS (
    SELECT
        school,
        ROUND(AVG(score), 2)                              AS sample_mean,
        CAST(STATS_ZTEST(score, 72.0, 11.0) AS CHAR(300)) AS json
    FROM reading_scores
    GROUP BY school
)
SELECT
    school,
    sample_mean,
    ROUND(JSON_EXTRACT(json, '$.z'),          4) AS z_statistic,
    ROUND(JSON_EXTRACT(json, '$.p_two_tail'), 4) AS p_two_tail,
    CASE
        WHEN JSON_EXTRACT(json, '$.p_two_tail') < 0.05
         AND JSON_EXTRACT(json, '$.z') > 0
        THEN 'Significantly above national average'
        WHEN JSON_EXTRACT(json, '$.p_two_tail') < 0.05
         AND JSON_EXTRACT(json, '$.z') < 0
        THEN 'Significantly below national average'
        ELSE 'No significant difference from national average'
    END AS conclusion
FROM ztest
ORDER BY school\G

DROP TABLE reading_scores;

UNINSTALL EXTENSION vsql_statistics;
