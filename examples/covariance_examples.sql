/*
  STATS_COVARIANCE examples

  STATS_COVARIANCE(x, y) returns the population and sample covariance:

    {"pop": ..., "samp": ...}

  pop  — σ_xy = C/n      (population covariance; 0.0 when n = 1)
  samp — s_xy = C/(n−1)  (sample covariance; null when n < 2)

  A row is skipped when either argument is NULL or non-finite.
  The whole result is NULL when no valid (x, y) pairs were accumulated.

  Interpreting the result:
    pop  > 0 — x and y tend to increase together
    pop  < 0 — x tends to increase as y decreases (and vice versa)
    pop  ≈ 0 — no linear relationship
    |pop| alone is not comparable across different units or scales;
    use correlation (cov / (σx × σy)) for unit-free comparisons.

  Use pop when the rows represent the complete population.
  Use samp when the rows are a sample drawn from a larger population —
  it applies Bessel's correction (÷(n−1)) to give an unbiased estimator.

  Three examples:

  1. Height and weight by sex  [GROUP BY, positive covariance]
     Both height and weight are larger on average for males, so the male
     group shows higher absolute covariance than the female group.

  2. Fuel price vs monthly kilometres driven  [single group, negative]
     Drivers reduce travel as petrol prices rise; covariance is negative.

  3. Monthly investment returns: correlated vs uncorrelated asset pairs
     [GROUP BY pair, pop vs samp, portfolio diversification context]
     Tech-Tech pair: high positive covariance — assets move in lockstep.
     Tech-Bonds pair: negative covariance — bonds offset equity drawdowns,
     providing the portfolio diversification benefit.
*/

INSTALL EXTENSION vsql_statistics;

-- ============================================================================
-- Example 1: Height vs weight per sex
-- ============================================================================
-- Positive covariance in both groups: taller individuals tend to weigh more.
-- The male covariance is larger in absolute terms because males occupy a
-- wider range of heights and weights, not because the relationship is
-- stronger — this is why raw covariance is scale-dependent.

DROP TABLE IF EXISTS body_measurements;

CREATE TABLE body_measurements (
    person_id SMALLINT NOT NULL,
    sex       CHAR(1)  NOT NULL,    -- 'M' or 'F'
    height_cm DOUBLE   NOT NULL,
    weight_kg DOUBLE   NOT NULL
);

INSERT INTO body_measurements VALUES
    ( 1, 'M', 165, 65), ( 2, 'M', 168, 68), ( 3, 'M', 170, 72),
    ( 4, 'M', 172, 74), ( 5, 'M', 173, 73), ( 6, 'M', 175, 78),
    ( 7, 'M', 176, 79), ( 8, 'M', 178, 80), ( 9, 'M', 179, 82),
    (10, 'M', 180, 84), (11, 'M', 182, 86), (12, 'M', 183, 88),
    (13, 'M', 185, 90), (14, 'M', 188, 94), (15, 'M', 192, 98),

    (16, 'F', 152, 50), (17, 'F', 155, 54), (18, 'F', 157, 55),
    (19, 'F', 158, 56), (20, 'F', 160, 58), (21, 'F', 161, 59),
    (22, 'F', 163, 61), (23, 'F', 164, 62), (24, 'F', 165, 63),
    (25, 'F', 166, 64), (26, 'F', 167, 65), (27, 'F', 168, 66),
    (28, 'F', 170, 68), (29, 'F', 172, 70), (30, 'F', 175, 74);

WITH cov_stats AS (
    SELECT
        sex,
        COUNT(*)                                                      AS n,
        ROUND(AVG(height_cm), 2)                                      AS mean_height,
        ROUND(AVG(weight_kg), 2)                                      AS mean_weight,
        CAST(STATS_COVARIANCE(height_cm, weight_kg) AS CHAR(200))     AS json
    FROM body_measurements
    GROUP BY sex
)
SELECT
    IF(sex = 'M', 'Male', 'Female')              AS sex,
    n,
    mean_height,
    mean_weight,
    ROUND(JSON_EXTRACT(json, '$.pop'),  2)        AS pop_cov,
    ROUND(JSON_EXTRACT(json, '$.samp'), 2)        AS samp_cov
FROM cov_stats
ORDER BY sex\G

-- Expected:
--   Female: mean height 163.53 cm  mean weight 61.67 kg
--           pop_cov  39.11  samp_cov  41.90  (cm·kg)
--   Male:   mean height 177.73 cm  mean weight 80.73 kg
--           pop_cov  66.46  samp_cov  71.21  (cm·kg)

DROP TABLE body_measurements;

-- ============================================================================
-- Example 2: Fuel price vs kilometres driven per month
-- ============================================================================
-- As petrol prices rise, drivers cut back on travel — negative covariance.
-- 12 months of data treated as a sample (the population being all months
-- across the full economic cycle), so samp_cov is the relevant statistic.

DROP TABLE IF EXISTS driving_data;

CREATE TABLE driving_data (
    month        TINYINT NOT NULL,
    price_cpl    DOUBLE  NOT NULL,    -- fuel price, cents per litre
    km_driven    DOUBLE  NOT NULL     -- household km driven that month
);

INSERT INTO driving_data VALUES
    ( 1, 142, 1350), ( 2, 148, 1310), ( 3, 155, 1270),
    ( 4, 162, 1220), ( 5, 168, 1180), ( 6, 175, 1130),
    ( 7, 172, 1150), ( 8, 165, 1200), ( 9, 158, 1250),
    (10, 150, 1300), (11, 145, 1330), (12, 140, 1360);

WITH cov_stats AS (
    SELECT
        COUNT(*)                                               AS n,
        ROUND(AVG(price_cpl), 2)                              AS mean_price,
        ROUND(AVG(km_driven), 2)                              AS mean_km,
        CAST(STATS_COVARIANCE(price_cpl, km_driven) AS CHAR(200)) AS json
    FROM driving_data
)
SELECT
    n,
    mean_price,
    mean_km,
    ROUND(JSON_EXTRACT(json, '$.pop'),  2)   AS pop_cov,
    ROUND(JSON_EXTRACT(json, '$.samp'), 2)   AS samp_cov,
    'Negative: higher price → fewer km'      AS interpretation
FROM cov_stats\G

-- Expected (n=12):
--   mean_price 156.67 c/L  mean_km 1254.17 km
--   pop_cov −851.94  samp_cov −929.39  (c/L · km)

DROP TABLE driving_data;

-- ============================================================================
-- Example 3: Monthly investment returns — two asset pairs
-- ============================================================================
-- Tech-Tech pair: two technology equities that rise and fall with the
-- same market sentiment → large positive covariance.
-- Tech-Bonds pair: technology equity + government bond ETF; bonds tend to
-- rally when equities sell off → negative covariance, providing
-- portfolio diversification.
--
-- Use samp_cov for inference about future return behaviour (these 12 months
-- are a sample from the ongoing market history); pop_cov would apply only
-- if analysing this exact 12-month window as a self-contained universe.

DROP TABLE IF EXISTS asset_returns;

CREATE TABLE asset_returns (
    pair_label VARCHAR(15) NOT NULL,
    month      TINYINT     NOT NULL,
    return_x   DOUBLE      NOT NULL,    -- first asset monthly return (%)
    return_y   DOUBLE      NOT NULL     -- second asset monthly return (%)
);

-- Tech-Tech: Asset A and Asset B both track equity growth sectors
INSERT INTO asset_returns VALUES
    ('Tech-Tech',  1,  4.2,  3.8), ('Tech-Tech',  2, -2.1, -1.9),
    ('Tech-Tech',  3,  5.5,  5.0), ('Tech-Tech',  4, -3.0, -2.7),
    ('Tech-Tech',  5,  3.8,  3.5), ('Tech-Tech',  6, -1.5, -1.3),
    ('Tech-Tech',  7,  4.8,  4.3), ('Tech-Tech',  8, -2.5, -2.2),
    ('Tech-Tech',  9,  3.2,  2.9), ('Tech-Tech', 10, -1.8, -1.6),
    ('Tech-Tech', 11,  5.0,  4.6), ('Tech-Tech', 12, -2.2, -2.0);

-- Tech-Bonds: same tech equity (return_x) paired with a bond ETF (return_y)
INSERT INTO asset_returns VALUES
    ('Tech-Bonds',  1,  4.2, -0.3), ('Tech-Bonds',  2, -2.1,  0.5),
    ('Tech-Bonds',  3,  5.5, -0.2), ('Tech-Bonds',  4, -3.0,  0.6),
    ('Tech-Bonds',  5,  3.8, -0.1), ('Tech-Bonds',  6, -1.5,  0.4),
    ('Tech-Bonds',  7,  4.8, -0.3), ('Tech-Bonds',  8, -2.5,  0.5),
    ('Tech-Bonds',  9,  3.2, -0.1), ('Tech-Bonds', 10, -1.8,  0.4),
    ('Tech-Bonds', 11,  5.0, -0.2), ('Tech-Bonds', 12, -2.2,  0.5);

WITH cov_stats AS (
    SELECT
        pair_label,
        COUNT(*)                                                   AS months,
        ROUND(AVG(return_x), 4)                                    AS mean_x,
        ROUND(AVG(return_y), 4)                                    AS mean_y,
        CAST(STATS_COVARIANCE(return_x, return_y) AS CHAR(200))    AS json
    FROM asset_returns
    GROUP BY pair_label
)
SELECT
    pair_label,
    months,
    mean_x,
    mean_y,
    ROUND(JSON_EXTRACT(json, '$.pop'),  4)  AS pop_cov,
    ROUND(JSON_EXTRACT(json, '$.samp'), 4)  AS samp_cov,
    CASE
        WHEN JSON_EXTRACT(json, '$.pop') > 5   THEN 'strong positive — assets move in lockstep'
        WHEN JSON_EXTRACT(json, '$.pop') > 0   THEN 'weak positive'
        WHEN JSON_EXTRACT(json, '$.pop') < -0.5 THEN 'negative — diversification benefit'
        ELSE 'near zero — uncorrelated'
    END                                     AS relationship
FROM cov_stats
ORDER BY pair_label\G

-- Expected (n=12 months):
--   Tech-Bonds: pop_cov −1.1599  samp_cov −1.2653  → diversification benefit
--   Tech-Tech:  pop_cov 10.2211  samp_cov 11.1503  → strong positive (lockstep)

DROP TABLE asset_returns;

UNINSTALL EXTENSION vsql_statistics;
