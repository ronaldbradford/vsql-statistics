/*
  Z-test: honors programme IQ — two-tailed test
  Source: https://statisticsbyjim.com/hypothesis-testing/z-test/
  Function: STATS_ZTEST(value, mu, sigma) returns JSON {"z", "p_one_tail", "p_two_tail"}

  STATS_ZTEST is a streaming aggregate — it accumulates individual observations
  and receives μ₀ and σ as per-row constants (last non-null value wins):
    z          = (x̄ − μ₀) / (σ / √n)
    p_one_tail = P(Z > z)  [upper-tail]
    p_two_tail = P(|Z| > z)

  ── Context ──────────────────────────────────────────────────────────────────
  A school district enrols pupils into an honors programme and later measures
  their IQ scores. The general population has a standardised IQ distribution
  with μ₀ = 100 and σ = 15 (known by definition).

  Researchers test whether honors programme graduates score significantly
  differently from the general population — in either direction.

  H₀: μ = 100     (honors programme does not change IQ)
  H₁: μ ≠ 100     (honors programme changes IQ)       ← two-tailed, α = 0.05

  Sample: n = 25 students, x̄ = 107 (sum = 2675)

  Expected:
    z          = (107 − 100) / (15 / √25) = 7 / 3 = 2.3333
    p_two_tail ≈ 0.0196  < 0.05  → Reject H₀
    Conclusion: honors programme graduates have a statistically significant
                higher mean IQ than the general population.
*/

INSTALL EXTENSION vsql_statistics;

DROP TABLE IF EXISTS honors_iq;

CREATE TABLE honors_iq (
    student_id INT    NOT NULL,
    iq_score   DOUBLE NOT NULL
);

-- n=25, sum=2675, x̄=107 exactly
-- z = (107−100)/(15/5) = 7/3 = 2.3333
INSERT INTO honors_iq VALUES
    ( 1,  85), ( 2,  90), ( 3,  93), ( 4,  96), ( 5,  98),
    ( 6,  99), ( 7, 100), ( 8, 101), ( 9, 102), (10, 103),
    (11, 104), (12, 105), (13, 106), (14, 107), (15, 108),
    (16, 109), (17, 110), (18, 111), (19, 112), (20, 114),
    (21, 116), (22, 118), (23, 121), (24, 125), (25, 142);

SELECT COUNT(*) AS n, ROUND(AVG(iq_score), 4) AS mean_iq FROM honors_iq;

-- ============================================================================
-- Z-test: two-tailed, testing whether honors IQ ≠ population μ₀ = 100
-- ============================================================================

WITH ztest AS (
    SELECT CAST(STATS_ZTEST(iq_score, 100.0, 15.0) AS CHAR(300)) AS json
    FROM honors_iq
),
summary AS (
    SELECT COUNT(*) AS n, ROUND(AVG(iq_score), 4) AS sample_mean FROM honors_iq
)
SELECT
    s.n,
    s.sample_mean,
    100.0                                                 AS population_mean_mu0,
    15.0                                                  AS known_sigma,
    ROUND(JSON_EXTRACT(z.json, '$.z'),          4)        AS z_statistic,
    ROUND(JSON_EXTRACT(z.json, '$.p_one_tail'), 6)        AS p_one_tail_upper,
    ROUND(JSON_EXTRACT(z.json, '$.p_two_tail'), 6)        AS p_two_tail,
    IF(JSON_EXTRACT(z.json, '$.p_two_tail') < 0.05,
       'Reject H₀ — honors programme mean IQ significantly differs from 100',
       'Retain H₀ — no significant difference from population mean') AS conclusion
FROM summary s, ztest z\G

-- ============================================================================
-- Interpretation breakdown
-- ============================================================================

WITH ztest AS (
    SELECT CAST(STATS_ZTEST(iq_score, 100.0, 15.0) AS CHAR(300)) AS json
    FROM honors_iq
)
SELECT
    'Two-tailed test (H₁: μ ≠ 100)'                      AS test_type,
    ROUND(JSON_EXTRACT(json, '$.z'),          4)          AS z_statistic,
    1.96                                                  AS z_critical_alpha05,
    ROUND(JSON_EXTRACT(json, '$.p_two_tail'), 4)          AS p_value,
    0.05                                                  AS alpha,
    CASE
        WHEN ABS(JSON_EXTRACT(json, '$.z')) > 1.96
        THEN CONCAT('|z| = ', ROUND(ABS(JSON_EXTRACT(json,'$.z')),4),
                    ' > 1.96 — falls in rejection region')
        ELSE CONCAT('|z| = ', ROUND(ABS(JSON_EXTRACT(json,'$.z')),4),
                    ' ≤ 1.96 — fails to reach rejection region')
    END                                                   AS z_decision,
    CASE
        WHEN JSON_EXTRACT(json, '$.p_two_tail') < 0.05
        THEN CONCAT('p = ', ROUND(JSON_EXTRACT(json,'$.p_two_tail'),4),
                    ' < 0.05 — statistically significant')
        ELSE CONCAT('p = ', ROUND(JSON_EXTRACT(json,'$.p_two_tail'),4),
                    ' ≥ 0.05 — not statistically significant')
    END                                                   AS p_decision
FROM ztest\G

DROP TABLE honors_iq;

UNINSTALL EXTENSION vsql_statistics;
