/*
  One-way fixed-effect ANOVA: fuel economy by fuel type
  Source: https://www.theopeneducator.com/doe/One-Way-Single-Factor-ANOVA/Example-Analysis-Fixed-Effect-One-Way-Single-Factor-ANOVA
  "Example Analysis — Fixed-Effect One-Way/Single-Factor ANOVA" (Ling 300, DOE Module 3)

  Research question: Does fuel type affect fuel economy (miles per gallon)?

  Design: completely randomized design (CRD), fixed-effect model
    Factor:   fuel type (3 levels — Type 1, Type 2, Type 3)
    Response: fuel economy (miles per gallon)
    n per group: 10 observations, N = 30 total

  H₀: μ₁ = μ₂ = μ₃  (all fuel types yield the same mean mpg)
  H₁: at least one fuel type mean differs from the others
  α = 0.05

  Note: Table 1 on the source page is rendered as an image and not machine-readable.
  The dataset below is reconstructed to match the stated group means exactly:
    Fuel Type 1: mean = 32.37 mpg (best)
    Fuel Type 2: mean = 27.00 mpg
    Fuel Type 3: mean = 22.83 mpg (worst)
  and is consistent with the page's stated result of p < 0.001.

  Expected: F >> F_crit(2,27) = 3.35 at α=0.05 → Reject H₀
*/

INSTALL EXTENSION vsql_statistics;

DROP TABLE IF EXISTS fuel_economy;

CREATE TABLE fuel_economy (
    obs       INT    NOT NULL,
    fuel_type INT    NOT NULL,   -- 1, 2, or 3
    mpg       DOUBLE NOT NULL
);

-- Fuel Type 1: mean = 32.37 mpg  (Σ = 323.7)
INSERT INTO fuel_economy VALUES
    ( 1, 1, 30.1),
    ( 2, 1, 31.2),
    ( 3, 1, 32.5),
    ( 4, 1, 33.8),
    ( 5, 1, 34.2),
    ( 6, 1, 31.0),
    ( 7, 1, 33.1),
    ( 8, 1, 33.5),
    ( 9, 1, 31.9),
    (10, 1, 32.4);

-- Fuel Type 2: mean = 27.00 mpg  (Σ = 270.0)
INSERT INTO fuel_economy VALUES
    (11, 2, 25.5),
    (12, 2, 26.3),
    (13, 2, 27.1),
    (14, 2, 28.2),
    (15, 2, 27.8),
    (16, 2, 26.5),
    (17, 2, 27.2),
    (18, 2, 26.8),
    (19, 2, 27.5),
    (20, 2, 27.1);

-- Fuel Type 3: mean = 22.83 mpg  (Σ = 228.3)
INSERT INTO fuel_economy VALUES
    (21, 3, 21.1),
    (22, 3, 22.3),
    (23, 3, 23.5),
    (24, 3, 24.7),
    (25, 3, 22.1),
    (26, 3, 23.2),
    (27, 3, 22.8),
    (28, 3, 23.4),
    (29, 3, 21.5),
    (30, 3, 23.7);

-- ============================================================================
-- Step 1: Descriptive statistics per group (equivalent to post-hoc means table)
-- ============================================================================

SELECT
    fuel_type,
    COUNT(*)                              AS n,
    ROUND(AVG(mpg), 4)                                          AS mean_mpg,
    ROUND(JSON_EXTRACT(CAST(STATS_IQR(mpg) AS CHAR(300)), '$.median'), 4) AS median_mpg,
    ROUND(JSON_EXTRACT(CAST(STATS_IQR(mpg) AS CHAR(300)), '$.iqr'),    4) AS iqr_mpg
FROM fuel_economy
GROUP BY fuel_type
ORDER BY fuel_type;

-- ============================================================================
-- Step 2: One-way ANOVA — full table (SSB, SSW, SST, MSB, MSW, F, p)
-- ============================================================================
-- STATS_ANOVA(response, group) — group is passed as REAL

WITH anova AS (
    SELECT CAST(STATS_ANOVA(mpg, fuel_type) AS CHAR(400)) AS json
    FROM fuel_economy
)
SELECT
    JSON_EXTRACT(json, '$.df_b') AS df_between,
    JSON_EXTRACT(json, '$.df_w') AS df_within,
    JSON_EXTRACT(json, '$.ssb')  AS ss_between,
    JSON_EXTRACT(json, '$.ssw')  AS ss_within,
    JSON_EXTRACT(json, '$.sst')  AS ss_total,
    JSON_EXTRACT(json, '$.msb')  AS ms_between,
    JSON_EXTRACT(json, '$.msw')  AS ms_within,
    JSON_EXTRACT(json, '$.f')    AS f_statistic,
    JSON_EXTRACT(json, '$.p')    AS p_value,
    IF(JSON_EXTRACT(json, '$.p') < 0.05,
       'Reject H₀ — at least one fuel type mean differs significantly',
       'Retain H₀ — no significant difference in mean mpg across fuel types') AS conclusion
FROM anova\G

DROP TABLE fuel_economy;

UNINSTALL EXTENSION vsql_statistics;
