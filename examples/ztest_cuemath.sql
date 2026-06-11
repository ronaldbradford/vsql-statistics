/*
  One-sample Z-test examples
  Source: https://www.cuemath.com/data/z-test/

  Example 1: Right-tailed test — teacher's claim about class scores
    H₀: μ = 82   H₁: μ > 82   (right-tailed, one-tail upper)
    n = 81, x̄ = 90, σ = 20 (known population standard deviation)
    z = (90 − 82) / (20 / √81) = 8 / 2.222 = 3.6
    Critical value α = 0.05 (right-tail): z* = 1.645
    z = 3.6 > 1.645  →  Reject H₀
    Interpretation: sufficient evidence to support the teacher's claim.

  Example 2: Left-tailed test — medicine delivery time claim
    H₀: μ = 120  H₁: μ < 120  (left-tailed, one-tail lower)
    n = 49, x̄ = 100, σ = 30 (known population standard deviation)
    z = (100 − 120) / (30 / √49) = −20 / 4.286 = −4.667
    Critical value α = 0.05 (left-tail): z* = −1.645
    z = −4.667 < −1.645  →  Reject H₀
    Interpretation: sufficient evidence to support the shop's claim.

  Example 3: Two-proportion Z-test — assembly line defect rates
    H₀: pA = pB   H₁: pA ≠ pB   (two-tailed)
    Line A: 18 defects / 200 samples,  Line B: 25 defects / 600 samples
    Pooled: p = (18+25)/(200+600) = 0.05375
    z = (pA − pB) / √[p(1−p)(1/nA + 1/nB)] ≈ 2.625
    Critical value α = 0.05 (two-tail): z* = ±1.96
    |z| = 2.625 > 1.96  →  Reject H₀
    Interpretation: significant difference in defect rates between lines.

    Note: STATS_ZTEST computes the one-sample mean z-test z = (x̄−μ)/(σ/√n).
    The two-proportion test uses a different formula and is computed here
    directly using SQL aggregate math — no extension function is needed.
*/

INSTALL EXTENSION vsql_statistics;

-- ============================================================================
-- Example 1: Right-tailed test — student exam scores
-- n=81, x̄=90, μ=82, σ=20  →  z = 3.6
-- ============================================================================

DROP TABLE IF EXISTS exam_scores;

CREATE TABLE exam_scores (
    student_id INT    NOT NULL,
    score      DOUBLE NOT NULL
);

-- 81 scores designed so that sample mean = 90.0 exactly (sum = 7290)
-- 17 symmetric pairs around 90 plus 47 scores of 90
INSERT INTO exam_scores VALUES
( 1,  70), ( 2,  72), ( 3,  74), ( 4,  75), ( 5,  76),
( 6,  78), ( 7,  79), ( 8,  80), ( 9,  81), (10,  82),
(11,  83), (12,  84), (13,  85), (14,  86), (15,  87),
(16,  88), (17,  89),
(18,  90), (19,  90), (20,  90), (21,  90), (22,  90),
(23,  90), (24,  90), (25,  90), (26,  90), (27,  90),
(28,  90), (29,  90), (30,  90), (31,  90), (32,  90),
(33,  90), (34,  90), (35,  90), (36,  90), (37,  90),
(38,  90), (39,  90), (40,  90), (41,  90), (42,  90),
(43,  90), (44,  90), (45,  90), (46,  90), (47,  90),
(48,  90), (49,  90), (50,  90), (51,  90), (52,  90),
(53,  90), (54,  90), (55,  90), (56,  90), (57,  90),
(58,  90), (59,  90), (60,  90), (61,  90), (62,  90),
(63,  90), (64,  91), (65,  92), (66,  93), (67,  94),
(68,  95), (69,  96), (70,  97), (71,  98), (72,  99),
(73, 100), (74, 101), (75, 102), (76, 104), (77, 105),
(78, 106), (79, 108), (80, 110), (81,  90);

WITH ztest AS (
    SELECT CAST(STATS_ZTEST(score, 82.0, 20.0) AS CHAR(300)) AS json
    FROM exam_scores
)
SELECT
    ROUND(JSON_EXTRACT(json, '$.z'),          4) AS z_statistic,     -- expected: 3.6
    ROUND(JSON_EXTRACT(json, '$.p_one_tail'), 6) AS p_one_tail,      -- P(Z > z) ≈ 0.000159
    IF(JSON_EXTRACT(json, '$.p_one_tail') < 0.05,
       'Reject H₀ — sufficient evidence that μ > 82',
       'Retain H₀ — insufficient evidence that μ > 82') AS conclusion
FROM ztest\G

DROP TABLE exam_scores;

-- ============================================================================
-- Example 2: Left-tailed test — medicine delivery times
-- n=49, x̄=100, μ=120, σ=30  →  z = −4.667
-- ============================================================================

DROP TABLE IF EXISTS delivery_times;

CREATE TABLE delivery_times (
    order_id INT    NOT NULL,
    minutes  DOUBLE NOT NULL
);

-- 49 delivery times designed so that sample mean = 100.0 exactly (sum = 4900)
-- 24 symmetric pairs around 100 plus 1 value of 100
INSERT INTO delivery_times VALUES
( 1,  60), ( 2,  62), ( 3,  64), ( 4,  65), ( 5,  67),
( 6,  68), ( 7,  70), ( 8,  72), ( 9,  74), (10,  75),
(11,  76), (12,  78), (13,  79), (14,  80), (15,  81),
(16,  82), (17,  83), (18,  84), (19,  85), (20,  86),
(21,  87), (22,  88), (23,  89), (24,  90),
(25, 100),
(26, 110), (27, 111), (28, 112), (29, 113), (30, 114),
(31, 115), (32, 116), (33, 117), (34, 118), (35, 119),
(36, 120), (37, 121), (38, 122), (39, 124), (40, 125),
(41, 126), (42, 128), (43, 130), (44, 132), (45, 133),
(46, 135), (47, 136), (48, 138), (49, 140);

WITH ztest AS (
    SELECT CAST(STATS_ZTEST(minutes, 120.0, 30.0) AS CHAR(300)) AS json
    FROM delivery_times
)
SELECT
    ROUND(JSON_EXTRACT(json, '$.z'),                          4) AS z_statistic,  -- expected: -4.6667
    ROUND(JSON_EXTRACT(json, '$.p_one_tail'),                 8) AS p_one_tail,   -- P(Z > z) ≈ 0.99999847
    ROUND(1 - JSON_EXTRACT(json, '$.p_one_tail'),             8) AS p_lower_tail, -- P(Z < z) ≈ 0.00000153
    IF(1 - JSON_EXTRACT(json, '$.p_one_tail') < 0.05,
       'Reject H₀ — sufficient evidence that μ < 120',
       'Retain H₀ — insufficient evidence that μ < 120') AS conclusion
FROM ztest\G

DROP TABLE delivery_times;

-- ============================================================================
-- Example 3: Two-proportion Z-test — assembly line defect rates
-- STATS_ZTEST handles one-sample mean tests; the two-proportion formula
-- is computed directly from aggregated counts.
-- ============================================================================

DROP TABLE IF EXISTS defect_counts;

CREATE TABLE defect_counts (
    line     CHAR(1) NOT NULL,  -- 'A' or 'B'
    defects  INT     NOT NULL,
    n        INT     NOT NULL
);

INSERT INTO defect_counts VALUES
    ('A',  18, 200),
    ('B',  25, 600);

WITH
props AS (
    SELECT line, defects, n, defects * 1.0 / n AS prop
    FROM defect_counts
),
pooled AS (
    SELECT SUM(defects) * 1.0 / SUM(n) AS p_pool
    FROM defect_counts
),
z_calc AS (
    SELECT
        MAX(CASE WHEN p.line = 'A' THEN p.prop END) AS p_a,
        MAX(CASE WHEN p.line = 'B' THEN p.prop END) AS p_b,
        po.p_pool,
        MAX(CASE WHEN p.line = 'A' THEN p.n   END) AS n_a,
        MAX(CASE WHEN p.line = 'B' THEN p.n   END) AS n_b
    FROM props p, pooled po
    GROUP BY po.p_pool
)
SELECT
    ROUND(p_a,     4)  AS defect_rate_a,       -- 0.0900  (18/200)
    ROUND(p_b,     4)  AS defect_rate_b,       -- 0.0417  (25/600)
    ROUND(p_pool,  4)  AS pooled_proportion,   -- 0.0538  (43/800)
    ROUND(
        (p_a - p_b) /
        SQRT(p_pool * (1 - p_pool) * (1.0/n_a + 1.0/n_b)),
        4
    )                  AS z_statistic,         -- expected: 2.6248
    IF(ABS(
        (p_a - p_b) /
        SQRT(p_pool * (1 - p_pool) * (1.0/n_a + 1.0/n_b))
    ) > 1.96,
       'Reject H₀ — defect rates differ significantly between lines',
       'Retain H₀ — no significant difference in defect rates') AS conclusion
FROM z_calc\G

DROP TABLE defect_counts;

UNINSTALL EXTENSION vsql_statistics;
