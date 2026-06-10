/*
  Skewness: age at death, Australian males and females, 2012

  Source: ABS catalogue 3302.0 — Deaths, Australia, 2012
          Table 8.1: Deaths, age at death, marital status, Australia — 2012
          File: 33020DO008_2012.xls

  The R code below uses HistogramTools::PreBinnedHistogram to visualise
  the pre-aggregated data. The deathCounts vector matches the 'Males Total'
  column in Table 8.1 exactly:

    library(HistogramTools)
    deathCounts <- c(565, 116, 69, 78, 319, 501, 633, 655, 848, 1226,
        1633, 2459, 3375, 4669, 6152, 7436, 9526, 12619, 12455, 7113,
        2104, 241)
    ageBreaks <- c(0, 1, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60,
        65, 70, 75, 80, 85, 90, 95, 100, 110)
    myhist <- PreBinnedHistogram(breaks=ageBreaks, counts=deathCounts,
        xname="Age at Death of Australian Males, 2012")
    plot(myhist)

  STATS_SKEWNESS operates on individual observations, not pre-aggregated
  bins. To analyse histogram data, each age band is expanded to (deaths)
  copies of its midpoint using a cross-join numbers table. This midpoint
  approximation is the standard technique for working with binned data.

  Both distributions are negatively (left) skewed: the bulk of deaths
  occur at old ages and the tail extends left toward infant and childhood
  mortality.

    Males:   peak at 80–84 (12,619 deaths), mean age ≈ 74.2
             Expected moment ≈ −1.4999
    Females: peak at 85–89 (15,430 deaths), mean age ≈ 80.1
             Expected moment ≈ −1.8693  (more negative: deaths concentrated
             even further toward old age than males)
*/

INSTALL EXTENSION vsql_statistics;

DROP TABLE IF EXISTS aus_deaths_by_age;

CREATE TABLE aus_deaths_by_age (
    sex      CHAR(1)     NOT NULL,  -- 'M' or 'F'
    age_band VARCHAR(10) NOT NULL,
    age_low  DOUBLE      NOT NULL,
    age_high DOUBLE      NOT NULL,  -- upper bound; 110 is notional for '100 and over'
    midpoint DOUBLE      NOT NULL,  -- (age_low + age_high) / 2
    deaths   INT         NOT NULL
);

INSERT INTO aus_deaths_by_age VALUES
-- Males: ABS Table 8.1 'Males Total' column — matches R deathCounts vector exactly
('M', '0',      0,   1,   0.5,    565),
('M', '1-4',    1,   5,   3.0,    116),
('M', '5-9',    5,  10,   7.5,     69),
('M', '10-14', 10,  15,  12.5,     78),
('M', '15-19', 15,  20,  17.5,    319),
('M', '20-24', 20,  25,  22.5,    501),
('M', '25-29', 25,  30,  27.5,    633),
('M', '30-34', 30,  35,  32.5,    655),
('M', '35-39', 35,  40,  37.5,    848),
('M', '40-44', 40,  45,  42.5,  1226),
('M', '45-49', 45,  50,  47.5,  1633),
('M', '50-54', 50,  55,  52.5,  2459),
('M', '55-59', 55,  60,  57.5,  3375),
('M', '60-64', 60,  65,  62.5,  4669),
('M', '65-69', 65,  70,  67.5,  6152),
('M', '70-74', 70,  75,  72.5,  7436),
('M', '75-79', 75,  80,  77.5,  9526),
('M', '80-84', 80,  85,  82.5, 12619),
('M', '85-89', 85,  90,  87.5, 12455),
('M', '90-94', 90,  95,  92.5,  7113),
('M', '95-99', 95, 100,  97.5,  2104),
('M', '100+', 100, 110, 105.0,   241),
-- Females: ABS Table 8.1 'Females Total' column
('F', '0',      0,   1,   0.5,    466),
('F', '1-4',    1,   5,   3.0,     87),
('F', '5-9',    5,  10,   7.5,     59),
('F', '10-14', 10,  15,  12.5,     63),
('F', '15-19', 15,  20,  17.5,    181),
('F', '20-24', 20,  25,  22.5,    202),
('F', '25-29', 25,  30,  27.5,    218),
('F', '30-34', 30,  35,  32.5,    328),
('F', '35-39', 35,  40,  37.5,    454),
('F', '40-44', 40,  45,  42.5,    750),
('F', '45-49', 45,  50,  47.5,   1024),
('F', '50-54', 50,  55,  52.5,   1569),
('F', '55-59', 55,  60,  57.5,   2093),
('F', '60-64', 60,  65,  62.5,   2909),
('F', '65-69', 65,  70,  67.5,   3745),
('F', '70-74', 70,  75,  72.5,   4810),
('F', '75-79', 75,  80,  77.5,   6914),
('F', '80-84', 80,  85,  82.5,  11290),
('F', '85-89', 85,  90,  87.5,  15430),
('F', '90-94', 90,  95,  92.5,  12946),
('F', '95-99', 95, 100,  97.5,   5637),
('F', '100+', 100, 110, 105.0,   1128);

-- ============================================================================
-- Distribution summary: skewness and IQR by sex
--
-- Each age band is expanded to (deaths) copies of its midpoint.
-- The cross-join produces integers 1..100000; HAVING trims to the largest
-- bin (females 85-89: 15,430), giving ~147,000 individual observations.
-- ============================================================================

WITH
d AS (
    SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
),
nums AS (
    SELECT a.n + b.n * 10 + c.n * 100 + d.n * 1000 + e.n * 10000 + 1 AS n
    FROM d a, d b, d c, d d, d e
    HAVING n <= 15430
),
obs AS (
    SELECT a.sex, a.midpoint
    FROM aus_deaths_by_age a
    JOIN nums ON nums.n <= a.deaths
)
SELECT
    CASE sex WHEN 'M' THEN 'Male' ELSE 'Female' END               AS sex,
    COUNT(*)                                                        AS total_deaths,
    ROUND(AVG(midpoint), 1)                                        AS mean_age,
    JSON_EXTRACT(CAST(STATS_IQR(midpoint)      AS CHAR(200)), '$.median') AS median_age,
    JSON_EXTRACT(CAST(STATS_IQR(midpoint)      AS CHAR(200)), '$.q1')     AS q1_age,
    JSON_EXTRACT(CAST(STATS_IQR(midpoint)      AS CHAR(200)), '$.q3')     AS q3_age,
    JSON_EXTRACT(CAST(STATS_SKEWNESS(midpoint) AS CHAR(200)), '$.moment') AS skewness_moment,
    JSON_EXTRACT(CAST(STATS_SKEWNESS(midpoint) AS CHAR(200)), '$.pearson') AS skewness_pearson
FROM obs
GROUP BY sex
ORDER BY sex\G

DROP TABLE aus_deaths_by_age;

UNINSTALL EXTENSION vsql_statistics;
