/*
  Skewness: London 2012 Men's Long Jump qualifying round

  Source: https://www.olympic.org/olympic-results/london-2012/athletics/long-jump-m
  Adapted from an R analysis using the moments package:
    require(moments)
    skewness(distances, na.rm=TRUE)

  Three analyses showing how skewness changes at different performance tiers:

  1. Full qualifying round — 40 athletes with valid jumps (2 DNS excluded)
     Most distances cluster near 8m; a long left tail of poor performers
     pulls the distribution strongly negative.
     Expected: moment ≈ -1.1186569

  2. Top 12 qualifiers — athletes who advanced to the Final
     Close clustering around 8m with little variation → near-symmetric.
     Expected: moment ≈ -0.1248782  (R: skewness(distances[1:12]))

  3. Final results — best jump per athlete across all final attempts
     Elite athletes performing at peak; very slight negative skew.
     Expected: moment ≈ -0.0857836  (R: skewness(c(8.31,8.16,...)))

  Interpretation: negative skewness (moment < 0) means the left tail is
  longer — there are more observations above the mean than below it, but
  the below-mean values are further away. In long jump this reflects a
  distribution where most athletes jump well but a few fall far short.
*/

INSTALL EXTENSION vsql_statistics;

-- ============================================================================
-- Qualifying round: all 40 athletes with a valid jump
-- ============================================================================

DROP TABLE IF EXISTS longjump_qualifying;

CREATE TABLE longjump_qualifying (
    result_rank  INT         NULL,       -- NULL = no legal jump (DNS)
    athlete_name VARCHAR(60) NOT NULL,
    country      CHAR(3)     NOT NULL,
    distance     DOUBLE      NULL        -- NULL = DNS
);

INSERT INTO longjump_qualifying VALUES
( 1, 'Mauro Vinicius DA SILVA',    'BRA', 8.11),
( 2, 'Marquise GOODWIN',           'USA', 8.11),
( 3, 'Aleksandr MENKOV',           'RUS', 8.09),
( 4, 'Greg RUTHERFORD',            'GBR', 8.08),
( 5, 'Christopher TOMLINSON',      'GBR', 8.06),
( 6, 'Michel TORNEUS',             'SWE', 8.03),
( 7, 'Godfrey Khotso MOKOENA',     'RSA', 8.02),
( 8, 'Will CLAYE',                 'USA', 7.99),
( 9, 'Mitchell WATT',              'AUS', 7.99),
(10, 'Tyrone SMITH',               'BER', 7.97),
(11, 'Henry FRAYNE',               'AUS', 7.95),
(12, 'Sebastian BAYER',            'GER', 7.92),
(13, 'Christian REIF',             'GER', 7.92),
(14, 'Eusebio CACERES',            'ESP', 7.92),
(15, 'Aleksandr PETROV',           'RUS', 7.89),
(16, 'Sergey MORGUNOV',            'RUS', 7.87),
(17, 'Mohammad ARZANDEH',          'IRI', 7.84),
(18, 'Ignisious GAISAH',           'GHA', 7.79),
(19, 'Damar FORBES',               'JAM', 7.79),
(20, 'Jinzhe LI',                  'CHN', 7.77),
(21, 'Raymond HIGGS',              'BAH', 7.76),
(22, 'Alyn CAMARA',                'GER', 7.72),
(23, 'Salim SDIRI',                'FRA', 7.71),
(24, 'Ndiss Kaba BADJI',           'SEN', 7.66),
(25, 'Arsen SARGSYAN',             'ARM', 7.62),
(26, 'Povilas MYKOLAITIS',         'LTU', 7.61),
(27, 'Stanley GBAGBEKE',           'NGR', 7.59),
(28, 'Marcos CHUVA',               'POR', 7.55),
(29, 'Louis TSATOUMAS',            'GRE', 7.53),
(30, 'Stepan WAGNER',              'CZE', 7.50),
(31, 'Viktor KUZNYETSOV',          'UKR', 7.50),
(32, 'Luis RIVERA',                'MEX', 7.42),
(33, 'Ching-Hsuan LIN',            'TPE', 7.38),
(33, 'Supanara SUKHASVASTI N A',   'THA', 7.38),
(35, 'Boleslav SKHIRTLADZE',       'GEO', 7.26),
(36, 'Xiaoyi ZHANG',               'CHN', 7.25),
(37, 'Mohamed Fathalla DIFALLAH',  'EGY', 7.08),
(38, 'Roman NOVOTNY',              'CZE', 6.96),
(39, 'George KITCHENS',            'USA', 6.84),
(40, 'Vardan PAHLEVANYAN',         'ARM', 6.55),
(NULL, 'Luis MELIZ',               'ESP', NULL),
(NULL, 'Irving SALADINO',          'PAN', NULL);

-- Full qualifying round: all 40 athletes (NULL distances skipped automatically)
WITH stats AS (
    SELECT CAST(STATS_SKEWNESS(distance) AS CHAR(200)) AS json
    FROM longjump_qualifying
)
SELECT
    JSON_EXTRACT(json, '$.moment')  AS skewness_moment,   -- expected: -1.1186569
    JSON_EXTRACT(json, '$.pearson') AS skewness_pearson,
    'Strong negative skew: bulk near 8m, long left tail to 6.55m' AS interpretation
FROM stats\G

-- Top 12 qualifiers: athletes who advanced to the Final
WITH stats AS (
    SELECT CAST(STATS_SKEWNESS(distance) AS CHAR(200)) AS json
    FROM longjump_qualifying
    WHERE result_rank <= 12
)
SELECT
    JSON_EXTRACT(json, '$.moment')  AS skewness_moment,   -- expected: -0.1248782
    JSON_EXTRACT(json, '$.pearson') AS skewness_pearson,
    'Near-symmetric: top qualifiers clustered tightly around 8m' AS interpretation
FROM stats\G

DROP TABLE longjump_qualifying;

-- ============================================================================
-- Final results: best jump per athlete across all final attempts
-- ============================================================================

DROP TABLE IF EXISTS longjump_final;

CREATE TABLE longjump_final (
    result_rank  INT         NOT NULL,
    athlete_name VARCHAR(60) NOT NULL,
    country      CHAR(3)     NOT NULL,
    distance     DOUBLE      NOT NULL
);

INSERT INTO longjump_final VALUES
( 1, 'Greg RUTHERFORD',        'GBR', 8.31),
( 2, 'Will CLAYE',             'USA', 8.16),
( 3, 'Mauro Vinicius DA SILVA','BRA', 8.12),
( 4, 'Mitchell WATT',          'AUS', 8.11),
( 5, 'Marquise GOODWIN',       'USA', 8.10),
( 6, 'Aleksandr MENKOV',       'RUS', 8.07),
( 7, 'Godfrey Khotso MOKOENA', 'RSA', 8.01),
( 8, 'Michel TORNEUS',         'SWE', 7.93),
( 9, 'Christopher TOMLINSON',  'GBR', 7.85),
(10, 'Henry FRAYNE',           'AUS', 7.80),
(11, 'Tyrone SMITH',           'BER', 7.78),
(12, 'Sebastian BAYER',        'GER', 7.70);

WITH stats AS (
    SELECT CAST(STATS_SKEWNESS(distance) AS CHAR(200)) AS json
    FROM longjump_final
)
SELECT
    JSON_EXTRACT(json, '$.moment')  AS skewness_moment,   -- expected: -0.0857836
    JSON_EXTRACT(json, '$.pearson') AS skewness_pearson,
    'Very slight negative skew: elite performances closely grouped' AS interpretation
FROM stats\G

DROP TABLE longjump_final;

UNINSTALL EXTENSION vsql_statistics;
