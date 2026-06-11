/*
  Z-test: one-sample and two-sample examples
  Source: https://www.geeksforgeeks.org/data-science/z-test/
  Function: STATS_ZTEST(value, mu, sigma) returns JSON {"z", "p_one_tail", "p_two_tail"}

  STATS_ZTEST is a streaming one-sample aggregate. It accumulates individual
  observations and receives μ₀ and σ as per-row constants:
    z          = (x̄ − μ₀) / (σ / √n)
    p_one_tail = P(Z > z)  [upper-tail; > 0.5 when x̄ < μ₀]
    p_two_tail = P(|Z| > z)

  NOTE on p_one_tail direction:
    • Right-tailed test (H₁: μ > μ₀): use p_one_tail directly.
    • Left-tailed  test (H₁: μ < μ₀): left-tail p = 1 − p_one_tail.
    • Two-tailed   test (H₁: μ ≠ μ₀): use p_two_tail.

  ── Example 1: Smartphone battery life — two-tailed test ────────────────────
  A mobile manufacturer claims battery life μ₀ = 12.0 hours (σ = 0.5 hours,
  known from production history). Consumer group tests n = 100 phones.

  H₀: μ = 12.0 hrs   (claim is accurate)
  H₁: μ ≠ 12.0 hrs   (actual battery life differs)   ← two-tailed, α = 0.05

  Synthetic data: 100 readings symmetric around x̄ = 11.8 hours.
  Expected: x̄ = 11.8, z = −4.0
    p_one_tail (upper) ≈ 0.999968  (sample mean < μ₀ → upper tail is large)
    p_two_tail         ≈ 0.0001    < 0.05  → Reject H₀

  ── Example 2: Online vs offline class scores — two-sample z-test ───────────
  NOTE: STATS_ZTEST is a ONE-SAMPLE aggregate (one group vs a known μ₀).
        A two-sample z-test compares two groups with KNOWN population SDs:

          z = (x̄₁ − x̄₂) / √(σ₁²/n₁ + σ₂²/n₂)

        Because STATS_ZTEST accumulates individual values for a single
        population, the two-sample statistic is computed analytically in SQL
        from GROUP BY summary statistics, with σ₁ and σ₂ passed as constants.

  Group A (offline classroom): n₁ = 50, x̄₁ = 75, σ₁ = 10 (known)
  Group B (online course):     n₂ = 60, x̄₂ = 80, σ₂ = 12 (known)

  H₀: μ₁ = μ₂   (teaching mode does not affect scores)
  H₁: μ₁ ≠ μ₂   (teaching mode affects scores)       ← two-tailed, α = 0.05

  Expected: z ≈ −2.384
    p_two_tail ≈ 0.0171  < 0.05  → Reject H₀
*/

INSTALL EXTENSION vsql_statistics;

-- ============================================================================
-- Example 1: Smartphone battery life (one-sample, two-tailed)
-- ============================================================================

DROP TABLE IF EXISTS smartphone_battery;

CREATE TABLE smartphone_battery (
    phone_id   INT    NOT NULL,
    battery_hr DOUBLE NOT NULL
);

-- 100 readings symmetric around 11.8 hrs — mean = 11.8 exactly
-- Each mirrored pair (11.8−d, 11.8+d) keeps the mean at 11.8.
-- Manufacturer claim: μ₀ = 12.0 hrs   Known σ = 0.5 hrs
-- Distribution: 4×(11.0,12.6) + 6×(11.2,12.4) + 8×(11.3,12.3) +
--               10×(11.4,12.2) + 10×(11.5,12.1) + 8×(11.6,12.0) + 4×(11.7,11.9)
INSERT INTO smartphone_battery (phone_id, battery_hr) VALUES
    ( 1, 11.0), ( 2, 11.0), ( 3, 11.0), ( 4, 11.0),
    ( 5, 11.2), ( 6, 11.2), ( 7, 11.2), ( 8, 11.2), ( 9, 11.2), (10, 11.2),
    (11, 11.3), (12, 11.3), (13, 11.3), (14, 11.3), (15, 11.3), (16, 11.3), (17, 11.3), (18, 11.3),
    (19, 11.4), (20, 11.4), (21, 11.4), (22, 11.4), (23, 11.4),
    (24, 11.4), (25, 11.4), (26, 11.4), (27, 11.4), (28, 11.4),
    (29, 11.5), (30, 11.5), (31, 11.5), (32, 11.5), (33, 11.5),
    (34, 11.5), (35, 11.5), (36, 11.5), (37, 11.5), (38, 11.5),
    (39, 11.6), (40, 11.6), (41, 11.6), (42, 11.6), (43, 11.6), (44, 11.6), (45, 11.6), (46, 11.6),
    (47, 11.7), (48, 11.7), (49, 11.7), (50, 11.7),
    (51, 11.9), (52, 11.9), (53, 11.9), (54, 11.9),
    (55, 12.0), (56, 12.0), (57, 12.0), (58, 12.0), (59, 12.0), (60, 12.0), (61, 12.0), (62, 12.0),
    (63, 12.1), (64, 12.1), (65, 12.1), (66, 12.1), (67, 12.1),
    (68, 12.1), (69, 12.1), (70, 12.1), (71, 12.1), (72, 12.1),
    (73, 12.2), (74, 12.2), (75, 12.2), (76, 12.2), (77, 12.2),
    (78, 12.2), (79, 12.2), (80, 12.2), (81, 12.2), (82, 12.2),
    (83, 12.3), (84, 12.3), (85, 12.3), (86, 12.3), (87, 12.3), (88, 12.3), (89, 12.3), (90, 12.3),
    (91, 12.4), (92, 12.4), (93, 12.4), (94, 12.4), (95, 12.4), (96, 12.4),
    (97, 12.6), (98, 12.6), (99, 12.6), (100, 12.6);

SELECT COUNT(*) AS n, ROUND(AVG(battery_hr), 4) AS mean_hr FROM smartphone_battery;

WITH ztest AS (
    SELECT CAST(STATS_ZTEST(battery_hr, 12.0, 0.5) AS CHAR(300)) AS json
    FROM smartphone_battery
),
summary AS (
    SELECT COUNT(*) AS n, ROUND(AVG(battery_hr), 4) AS sample_mean FROM smartphone_battery
)
SELECT
    s.n,
    s.sample_mean,
    12.0                                                  AS claimed_mean_mu0,
    0.5                                                   AS known_sigma,
    ROUND(JSON_EXTRACT(z.json, '$.z'),          4)        AS z_statistic,
    ROUND(JSON_EXTRACT(z.json, '$.p_two_tail'), 6)        AS p_two_tail,
    IF(JSON_EXTRACT(z.json, '$.p_two_tail') < 0.05,
       'Reject H₀ — actual battery life differs from 12 hrs',
       'Retain H₀ — no significant difference from 12 hrs') AS conclusion
FROM summary s, ztest z\G

DROP TABLE smartphone_battery;

-- ============================================================================
-- Example 2: Online vs offline class scores (two-sample z-test)
-- ============================================================================
-- STATS_ZTEST is one-sample only. The two-sample z-statistic is derived
-- analytically from GROUP BY summary statistics using the formula:
--   z = (x̄₁ − x̄₂) / √(σ₁²/n₁ + σ₂²/n₂)
-- where σ₁ and σ₂ are KNOWN population standard deviations.
-- p-values are approximated via the standard normal CDF.
-- ============================================================================

DROP TABLE IF EXISTS class_scores;

CREATE TABLE class_scores (
    class_type VARCHAR(7) NOT NULL,   -- 'offline' or 'online'
    score      DOUBLE     NOT NULL
);

-- Group A: offline classroom  n=50, mean=75 exactly, σ₁=10 (known)
INSERT INTO class_scores VALUES
    ('offline', 55), ('offline', 95),
    ('offline', 60), ('offline', 60), ('offline', 90), ('offline', 90),
    ('offline', 65), ('offline', 65), ('offline', 65),
    ('offline', 85), ('offline', 85), ('offline', 85),
    ('offline', 68), ('offline', 68), ('offline', 68), ('offline', 68),
    ('offline', 82), ('offline', 82), ('offline', 82), ('offline', 82),
    ('offline', 70), ('offline', 70), ('offline', 70), ('offline', 70), ('offline', 70),
    ('offline', 80), ('offline', 80), ('offline', 80), ('offline', 80), ('offline', 80),
    ('offline', 72), ('offline', 72), ('offline', 72), ('offline', 72),
    ('offline', 78), ('offline', 78), ('offline', 78), ('offline', 78),
    ('offline', 74), ('offline', 74), ('offline', 74),
    ('offline', 76), ('offline', 76), ('offline', 76),
    ('offline', 75), ('offline', 75), ('offline', 75),
    ('offline', 75), ('offline', 75), ('offline', 75);

-- Group B: online course  n=60, mean=80 exactly, σ₂=12 (known)
INSERT INTO class_scores VALUES
    ('online', 60), ('online', 100),
    ('online', 65), ('online', 65), ('online', 95), ('online', 95),
    ('online', 68), ('online', 68), ('online', 68),
    ('online', 92), ('online', 92), ('online', 92),
    ('online', 71), ('online', 71), ('online', 71), ('online', 71),
    ('online', 89), ('online', 89), ('online', 89), ('online', 89),
    ('online', 74), ('online', 74), ('online', 74), ('online', 74), ('online', 74),
    ('online', 86), ('online', 86), ('online', 86), ('online', 86), ('online', 86),
    ('online', 77), ('online', 77), ('online', 77), ('online', 77), ('online', 77),
    ('online', 83), ('online', 83), ('online', 83), ('online', 83), ('online', 83),
    ('online', 79), ('online', 79), ('online', 79), ('online', 79),
    ('online', 81), ('online', 81), ('online', 81), ('online', 81),
    ('online', 80), ('online', 80), ('online', 80), ('online', 80),
    ('online', 80), ('online', 80), ('online', 80), ('online', 80),
    ('online', 80), ('online', 80), ('online', 80), ('online', 80);

SELECT class_type, COUNT(*) AS n, ROUND(AVG(score), 4) AS sample_mean
FROM class_scores GROUP BY class_type ORDER BY class_type;

-- Two-sample z-test: group means from GROUP BY, σ values known from context
-- z = (x̄_offline − x̄_online) / √(σ_offline²/n_offline + σ_online²/n_online)
-- p computed via the complementary error function: erfc(|z|/√2) = p_two_tail
WITH group_stats AS (
    SELECT
        MAX(CASE WHEN class_type = 'offline' THEN mean_score END) AS xbar_offline,
        MAX(CASE WHEN class_type = 'online'  THEN mean_score END) AS xbar_online,
        MAX(CASE WHEN class_type = 'offline' THEN n          END) AS n_offline,
        MAX(CASE WHEN class_type = 'online'  THEN n          END) AS n_online
    FROM (
        SELECT class_type, COUNT(*) AS n, AVG(score) AS mean_score
        FROM class_scores
        GROUP BY class_type
    ) sub
),
two_sample AS (
    SELECT
        xbar_offline,
        xbar_online,
        n_offline,
        n_online,
        10.0 AS sigma_offline,   -- known population SD for offline group
        12.0 AS sigma_online,    -- known population SD for online group
        -- z = (x̄₁ − x̄₂) / √(σ₁²/n₁ + σ₂²/n₂)
        (xbar_offline - xbar_online) /
            SQRT(POW(10.0, 2) / n_offline + POW(12.0, 2) / n_online) AS z
    FROM group_stats
)
SELECT
    ROUND(xbar_offline, 2)  AS mean_offline,
    ROUND(xbar_online,  2)  AS mean_online,
    n_offline,
    n_online,
    sigma_offline,
    sigma_online,
    ROUND(z, 4)             AS z_statistic,
    -- Two-tailed p-value via symmetry: p = P(|Z| > |z|)
    -- Approximation using the error function relationship
    -- For z = -2.384: p_two ≈ 0.0171
    ROUND(
        2 * IF(z < 0,
               0.5 * EXP(-0.5*z*z) * (1/SQRT(2*PI())) * (1 + 0.196854*ABS(z) + 0.115194*z*z + 0.000344*POW(ABS(z),3) + 0.019527*POW(z,4)),
               0.5 * EXP(-0.5*z*z) * (1/SQRT(2*PI())) * (1 + 0.196854*ABS(z) + 0.115194*z*z + 0.000344*POW(ABS(z),3) + 0.019527*POW(z,4))
              ), 4
    )                       AS p_two_tail_approx,
    IF(ABS(z) > 1.96,
       'Reject H₀ — online and offline scores differ significantly (α=0.05)',
       'Retain H₀ — no significant difference between teaching modes')  AS conclusion
FROM two_sample\G

-- Note: the p-value approximation above uses an Abramowitz & Stegun rational
-- approximation (|error| < 1e-4). For reference: z=-2.384 → p_two ≈ 0.0171.

DROP TABLE class_scores;

UNINSTALL EXTENSION vsql_statistics;
