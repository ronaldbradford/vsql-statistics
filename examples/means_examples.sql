/*
  STATS_MEAN examples

  STATS_MEAN(value, trim_pct) returns a JSON object with four alternative
  central tendency measures:

    {"trimmed": ..., "winsorized": ..., "geometric": ..., "harmonic": ...}

  trim_pct — fraction (0 < pct < 0.5) of values to cut from each tail for
             trimmed and winsorized; pass NULL when those fields are not needed.

  trimmed   — remove the k = floor(trim_pct × n) lowest and highest values,
              average the rest; robust against extreme outliers
  winsorized— same boundary as trimmed but caps rather than removes extremes;
              retains the full sample size while limiting distortion
  geometric — exp(mean of ln(x)); correct for multiplicative processes and
              compound growth; uses only positive values
  harmonic  — n / Σ(1/x); correct for rates where the denominator unit
              (distance, time) is constant across observations; positive values only

  Three examples:

  1. Annual investment returns
     Geometric mean = true compound annual growth rate (CAGR). For volatile
     funds, arithmetic mean overstates actual long-run return (volatility drag).

  2. Employee compensation with executive outliers
     10% trimmed/winsorized means show typical employee pay; arithmetic mean
     is inflated by two executive salaries per department.

  3. Road-trip fuel efficiency
     Harmonic mean of km/L gives the correct overall efficiency when the same
     distance is driven at each rate. Arithmetic mean overstates it.
*/

INSTALL EXTENSION vsql_statistics;

-- ============================================================================
-- Example 1: Annual investment returns — geometric mean reveals volatility drag
-- ============================================================================
-- Both funds have the same arithmetic mean return (7%) over 10 years, but the
-- volatile fund's large swings suppress the true CAGR because gains and losses
-- multiply rather than add (e.g. +45% then −30% gives 1.45 × 0.70 = 1.015,
-- not the 1.075 that the arithmetic average suggests).
--
-- Growth multiplier = 1 + annual_return  (e.g. +20% return → 1.20)
-- CAGR = geometric_mean − 1

DROP TABLE IF EXISTS fund_returns;

CREATE TABLE fund_returns (
    year       SMALLINT NOT NULL,
    fund       CHAR(8)  NOT NULL,
    multiplier DOUBLE   NOT NULL    -- 1 + annual return
);

-- Stable fund: steady gains close to 7% each year
INSERT INTO fund_returns VALUES
    (2014, 'Stable', 1.08), (2015, 'Stable', 1.07), (2016, 'Stable', 1.06),
    (2017, 'Stable', 1.08), (2018, 'Stable', 1.07), (2019, 'Stable', 1.06),
    (2020, 'Stable', 1.08), (2021, 'Stable', 1.07), (2022, 'Stable', 1.06),
    (2023, 'Stable', 1.07);

-- Volatile fund: same arithmetic mean (7%) but wide swings suppress CAGR
INSERT INTO fund_returns VALUES
    (2014, 'Volatile', 1.40), (2015, 'Volatile', 0.75),
    (2016, 'Volatile', 1.35), (2017, 'Volatile', 0.80),
    (2018, 'Volatile', 1.45), (2019, 'Volatile', 0.70),
    (2020, 'Volatile', 1.25), (2021, 'Volatile', 0.90),
    (2022, 'Volatile', 1.35), (2023, 'Volatile', 0.75);

WITH means AS (
    SELECT
        fund,
        COUNT(*)                                          AS years,
        ROUND(AVG(multiplier) - 1, 4)                    AS arithmetic_avg_return,
        CAST(STATS_MEAN(multiplier, NULL) AS CHAR(200))  AS json
    FROM fund_returns
    GROUP BY fund
)
SELECT
    fund,
    years,
    CONCAT(ROUND(arithmetic_avg_return * 100, 1), '%')                       AS arithmetic_mean_return,
    CONCAT(ROUND((JSON_EXTRACT(json, '$.geometric') - 1) * 100, 1), '%')     AS geometric_mean_return,
    CONCAT(ROUND((POW(JSON_EXTRACT(json, '$.geometric'), years) - 1) * 100, 1), '%')
                                                                              AS total_return_10yr
FROM means
ORDER BY fund\G

-- Expected:
--   Stable:   arithmetic 7.0%, geometric ≈ 7.0%, 10yr total ≈ +96.7%
--   Volatile: arithmetic 7.0%, geometric ≈ 2.7%, 10yr total ≈ +31.1%

DROP TABLE fund_returns;

-- ============================================================================
-- Example 2: Employee compensation — trimmed and winsorized means resist
--            distortion from executive salaries
-- ============================================================================
-- Two executive salaries per department pull the arithmetic mean well above
-- the typical employee level. A 10% trim removes k = floor(0.10 × 30) = 3
-- values from each tail, eliminating both executives and smoothing the extremes.
-- Winsorizing caps at the same boundary but keeps all 30 observations.

DROP TABLE IF EXISTS employee_salaries;

CREATE TABLE employee_salaries (
    emp_id     SMALLINT    NOT NULL,
    department VARCHAR(20) NOT NULL,
    salary     DOUBLE      NOT NULL
);

-- Engineering: 28 staff ($55k–$88k) + VP-Engineering $250k + CTO $380k
INSERT INTO employee_salaries VALUES
    ( 1, 'Engineering', 55000), ( 2, 'Engineering', 58000),
    ( 3, 'Engineering', 60000), ( 4, 'Engineering', 62000),
    ( 5, 'Engineering', 63000), ( 6, 'Engineering', 65000),
    ( 7, 'Engineering', 66000), ( 8, 'Engineering', 67000),
    ( 9, 'Engineering', 68000), (10, 'Engineering', 69000),
    (11, 'Engineering', 70000), (12, 'Engineering', 71000),
    (13, 'Engineering', 72000), (14, 'Engineering', 73000),
    (15, 'Engineering', 74000), (16, 'Engineering', 75000),
    (17, 'Engineering', 76000), (18, 'Engineering', 77000),
    (19, 'Engineering', 78000), (20, 'Engineering', 79000),
    (21, 'Engineering', 80000), (22, 'Engineering', 81000),
    (23, 'Engineering', 82000), (24, 'Engineering', 83000),
    (25, 'Engineering', 84000), (26, 'Engineering', 85000),
    (27, 'Engineering', 86000), (28, 'Engineering', 88000),
    (29, 'Engineering', 250000), (30, 'Engineering', 380000);

-- Marketing: 28 staff ($45k–$74k) + VP-Marketing $200k + CMO $320k
INSERT INTO employee_salaries VALUES
    (31, 'Marketing', 45000), (32, 'Marketing', 47000),
    (33, 'Marketing', 48000), (34, 'Marketing', 50000),
    (35, 'Marketing', 51000), (36, 'Marketing', 52000),
    (37, 'Marketing', 53000), (38, 'Marketing', 54000),
    (39, 'Marketing', 55000), (40, 'Marketing', 56000),
    (41, 'Marketing', 57000), (42, 'Marketing', 58000),
    (43, 'Marketing', 59000), (44, 'Marketing', 60000),
    (45, 'Marketing', 61000), (46, 'Marketing', 62000),
    (47, 'Marketing', 63000), (48, 'Marketing', 64000),
    (49, 'Marketing', 65000), (50, 'Marketing', 66000),
    (51, 'Marketing', 67000), (52, 'Marketing', 68000),
    (53, 'Marketing', 69000), (54, 'Marketing', 70000),
    (55, 'Marketing', 71000), (56, 'Marketing', 72000),
    (57, 'Marketing', 73000), (58, 'Marketing', 74000),
    (59, 'Marketing', 200000), (60, 'Marketing', 320000);

WITH means AS (
    SELECT
        department,
        COUNT(*)                                          AS n,
        ROUND(AVG(salary))                               AS arithmetic_mean,
        CAST(STATS_MEAN(salary, 0.10) AS CHAR(300))      AS json
    FROM employee_salaries
    GROUP BY department
)
SELECT
    department,
    n,
    FORMAT(arithmetic_mean, 0)                           AS arithmetic_mean,
    FORMAT(ROUND(JSON_EXTRACT(json, '$.trimmed')),    0) AS trimmed_10pct,
    FORMAT(ROUND(JSON_EXTRACT(json, '$.winsorized')), 0) AS winsorized_10pct
FROM means
ORDER BY department\G

-- Expected (k=3 trimmed from each tail of 30 observations):
--   Engineering: arithmetic $89,233  trimmed $74,417  winsorized $74,333
--   Marketing:   arithmetic $73,667  trimmed $61,500  winsorized $61,500

DROP TABLE employee_salaries;

-- ============================================================================
-- Example 3: Road-trip fuel efficiency — harmonic mean for equal-distance
--            segments
-- ============================================================================
-- When the same distance (100 km) is driven at each fuel economy (km/L), the
-- harmonic mean gives the correct overall average.
-- Arithmetic mean overstates efficiency because it weights each reading equally
-- instead of by the fuel actually consumed — low-efficiency legs burn
-- disproportionately more fuel and should count more heavily.
--
-- Verify: total litres = total_km / harmonic_mean

DROP TABLE IF EXISTS trip_segments;

CREATE TABLE trip_segments (
    trip        VARCHAR(20) NOT NULL,
    segment     TINYINT     NOT NULL,
    description VARCHAR(40) NOT NULL,
    km_per_l    DOUBLE      NOT NULL    -- each segment covers 100 km
);

INSERT INTO trip_segments VALUES
    -- Three 100 km legs: city out to motorway, then suburbs
    ('City commute',   1, 'Urban stop-go (peak hour)',    6.5),
    ('City commute',   2, 'Motorway cruise (110 km/h)', 13.5),
    ('City commute',   3, 'Suburban mixed',               9.2),
    -- Four 100 km legs: mountain pass and open highway
    ('Interstate run', 1, 'Mountain ascent',               7.8),
    ('Interstate run', 2, 'Mountain descent',             11.4),
    ('Interstate run', 3, 'Open freeway (100 km/h)',      14.2),
    ('Interstate run', 4, 'Town zones (60 km/h)',          8.9);

WITH means AS (
    SELECT
        trip,
        COUNT(*) * 100                                    AS total_km,
        ROUND(AVG(km_per_l), 2)                          AS arithmetic_mean,
        CAST(STATS_MEAN(km_per_l, NULL) AS CHAR(200))    AS json
    FROM trip_segments
    GROUP BY trip
)
SELECT
    trip,
    total_km,
    arithmetic_mean                                       AS arith_km_per_l,
    ROUND(JSON_EXTRACT(json, '$.harmonic'),  2)           AS harmonic_km_per_l,
    ROUND(JSON_EXTRACT(json, '$.geometric'), 2)           AS geometric_km_per_l,
    ROUND(total_km / JSON_EXTRACT(json, '$.harmonic'), 1) AS total_litres_used
FROM means
ORDER BY trip\G

-- Expected:
--   City commute:   arithmetic 9.73  harmonic 8.91  geometric 9.32  litres 33.7
--   Interstate run: arithmetic 10.58  harmonic 10.03  geometric 10.29  litres 39.9

DROP TABLE trip_segments;

UNINSTALL EXTENSION vsql_statistics;
