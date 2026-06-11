/*
  Z-test: one-tailed and two-tailed examples
  Source reference: https://statisticsbyjim.com/hypothesis-testing/z-test/
  Function: STATS_ZTEST(value, mu, sigma) returns JSON {"z", "p_one_tail", "p_two_tail"}

  Use the z-test when the population standard deviation (σ) is known and the
  sample size is large enough (n ≥ 30) for the Central Limit Theorem to apply.

  STATS_ZTEST is a streaming aggregate — it accumulates individual observations
  and receives μ₀ and σ as per-row constants (last non-null value wins):
    z          = (x̄ − μ₀) / (σ / √n)
    p_one_tail = P(Z > z)  [upper-tail; > 0.5 when x̄ < μ₀]
    p_two_tail = P(|Z| > z)

  NOTE on p_one_tail direction:
    The function always returns the UPPER-tail probability P(Z > z).
    • Right-tailed test (H₁: μ > μ₀): use p_one_tail directly.
    • Left-tailed  test (H₁: μ < μ₀): left-tail p = 1 − p_one_tail.
    • Two-tailed   test (H₁: μ ≠ μ₀): use p_two_tail.

  ── Example 1: Battery QC — left-tailed test ────────────────────────────────
  A manufacturer claims their batteries last μ₀ = 500 hours (σ = 40 hours,
  known from long-run production data). A QA engineer tests a batch of n = 30
  batteries and suspects this batch falls short of the claimed lifetime.

  H₀: μ = 500 hrs   (batch meets specification)
  H₁: μ < 500 hrs   (batch falls short)          ← left-tailed, α = 0.05

  Expected: x̄ ≈ 480.3 hrs, z ≈ −2.693
    p_one_tail (upper)    ≈ 0.9965
    left-tail p-value     ≈ 0.0035  < 0.05  → Reject H₀
    p_two_tail            ≈ 0.0071  < 0.05  → also significant

  ── Example 2: IQ enrichment programme — two-tailed test ────────────────────
  General population IQ: μ₀ = 100, σ = 15 (standardised by definition).
  An education researcher measures IQ scores of n = 40 graduates from an
  enrichment programme to see whether the programme changes IQ in either
  direction.

  H₀: μ = 100        (programme has no effect)
  H₁: μ ≠ 100        (programme changes IQ)      ← two-tailed, α = 0.05

  Expected: x̄ ≈ 106.1, z ≈ 2.572
    p_one_tail (upper) ≈ 0.0051  (sample mean > μ₀, so upper-tail is small)
    p_two_tail         ≈ 0.0101  < 0.05  → Reject H₀
*/

INSTALL EXTENSION vsql_statistics;

-- ============================================================================
-- Example 1: Battery lifetime quality control (left-tailed)
-- ============================================================================

DROP TABLE IF EXISTS battery_lifetimes;

CREATE TABLE battery_lifetimes (
    battery_id INT    NOT NULL,
    hours      DOUBLE NOT NULL
);

INSERT INTO battery_lifetimes VALUES
    ( 1, 432), ( 2, 448), ( 3, 451), ( 4, 455), ( 5, 458),
    ( 6, 460), ( 7, 462), ( 8, 465), ( 9, 467), (10, 469),
    (11, 471), (12, 473), (13, 475), (14, 477), (15, 479),
    (16, 481), (17, 483), (18, 485), (19, 487), (20, 489),
    (21, 491), (22, 493), (23, 496), (24, 499), (25, 502),
    (26, 505), (27, 508), (28, 511), (29, 516), (30, 522);

WITH ztest AS (
    SELECT CAST(STATS_ZTEST(hours, 500.0, 40.0) AS CHAR(300)) AS json
    FROM battery_lifetimes
),
result AS (
    SELECT
        COUNT(*)                    AS n,
        ROUND(AVG(hours), 4)        AS sample_mean,
        500.0                       AS claimed_mean,
        40.0                        AS known_sigma
    FROM battery_lifetimes
)
SELECT
    r.n,
    r.sample_mean,
    r.claimed_mean,
    r.known_sigma,
    ROUND(JSON_EXTRACT(z.json, '$.z'),          4)  AS z_statistic,
    -- Left-tailed p = 1 − p_one_tail  (function returns upper-tail P(Z > z))
    ROUND(1 - JSON_EXTRACT(z.json, '$.p_one_tail'), 6) AS p_left_tail,
    ROUND(JSON_EXTRACT(z.json, '$.p_two_tail'), 6)  AS p_two_tail,
    IF(1 - JSON_EXTRACT(z.json, '$.p_one_tail') < 0.05,
       'Reject H₀ — batch lifetime IS significantly below 500 hrs',
       'Retain H₀ — no significant evidence batch falls short') AS conclusion
FROM result r, ztest z\G

DROP TABLE battery_lifetimes;

-- ============================================================================
-- Example 2: IQ enrichment programme (two-tailed)
-- ============================================================================

DROP TABLE IF EXISTS iq_scores;

CREATE TABLE iq_scores (
    participant_id INT    NOT NULL,
    iq             DOUBLE NOT NULL
);

INSERT INTO iq_scores VALUES
    ( 1,  82), ( 2,  88), ( 3,  90), ( 4,  92), ( 5,  93),
    ( 6,  95), ( 7,  96), ( 8,  97), ( 9,  98), (10,  99),
    (11, 100), (12, 100), (13, 101), (14, 101), (15, 102),
    (16, 103), (17, 103), (18, 104), (19, 104), (20, 105),
    (21, 105), (22, 106), (23, 107), (24, 107), (25, 108),
    (26, 109), (27, 110), (28, 111), (29, 112), (30, 113),
    (31, 114), (32, 115), (33, 116), (34, 117), (35, 119),
    (36, 120), (37, 122), (38, 124), (39, 126), (40, 130);

WITH ztest AS (
    SELECT CAST(STATS_ZTEST(iq, 100.0, 15.0) AS CHAR(300)) AS json
    FROM iq_scores
),
result AS (
    SELECT
        COUNT(*)              AS n,
        ROUND(AVG(iq), 4)     AS sample_mean,
        100.0                 AS population_mean,
        15.0                  AS known_sigma
    FROM iq_scores
)
SELECT
    r.n,
    r.sample_mean,
    r.population_mean,
    r.known_sigma,
    ROUND(JSON_EXTRACT(z.json, '$.z'),          4)  AS z_statistic,
    ROUND(JSON_EXTRACT(z.json, '$.p_one_tail'), 6)  AS p_one_tail_upper,
    ROUND(JSON_EXTRACT(z.json, '$.p_two_tail'), 6)  AS p_two_tail,
    IF(JSON_EXTRACT(z.json, '$.p_two_tail') < 0.05,
       'Reject H₀ — programme graduates score significantly differently from μ=100',
       'Retain H₀ — no significant difference from population mean') AS conclusion
FROM result r, ztest z\G

DROP TABLE iq_scores;

UNINSTALL EXTENSION vsql_statistics;
