/*
  Chi-squared goodness-of-fit: Royal Geographical Society student guide example
  Source: https://www.rgs.org/media/pxep11bq/a-student-guide-to-chi-squared-testing.pdf

  Question: Does the age structure of visitors to a tourist attraction reflect the
  age structure of the surrounding town?

  H₀: The age distribution of visitors matches the town's population proportions
  H₁: The age distribution of visitors is significantly different from the town's

  Observed: annual visitor counts by age group (secondary data from the attraction)
  Expected: total visitors × (age group population / total town population)

  Town population (Census):
    0-19:  41,370  (23.9%)
    20-39: 48,830  (28.2%)
    40-59: 44,730  (25.8%)
    60-79: 30,500  (17.6%)
    80+:    7,650   (4.5%)
    Total: 173,080

  Visitor counts:
    0-19:  280,580
    20-39: 240,500
    40-59: 121,250
    60-79:  80,160
    80+:     2,080
    Total: 724,570

  Expected visitor count per age group = (age_pop / total_pop) × total_visitors
    0-19:  41370/173080 × 724570 = 173,172
    20-39: 48830/173080 × 724570 = 204,329
    40-59: 44730/173080 × 724570 = 186,939
    60-79: 30500/173080 × 724570 = 127,524
    80+:    7650/173080 × 724570 =  32,603

  Expected: chi_sq≈142,270, df=4 → Reject null at α=0.05 (critical value 9.49)
*/

INSTALL EXTENSION vsql_statistics;

DROP TABLE IF EXISTS tourist_visitors;

CREATE TABLE tourist_visitors (
    age_group    VARCHAR(10) NOT NULL,
    observed     DOUBLE      NOT NULL,   -- annual visitors to the attraction
    pop_of_town  DOUBLE      NOT NULL    -- census population for this age group
);

INSERT INTO tourist_visitors VALUES
    ('0-19',  280580, 41370),
    ('20-39', 240500, 48830),
    ('40-59', 121250, 44730),
    ('60-79',  80160, 30500),
    ('80+',     2080,  7650);

-- Expected visitors = (age group share of town population) × total visitors
-- Computed inline so the formula is explicit and auditable
WITH data AS (
    SELECT
        age_group,
        observed,
        (pop_of_town / SUM(pop_of_town) OVER ()) *
            SUM(observed)     OVER ()  AS expected
    FROM tourist_visitors
),
gof AS (
    SELECT CAST(STATS_CHISQ_GOF(observed, expected) AS CHAR(200)) AS json
    FROM data
)
SELECT
    JSON_EXTRACT(json, '$.chi_sq') AS chi_squared,
    JSON_EXTRACT(json, '$.df')     AS degrees_of_freedom,
    JSON_EXTRACT(json, '$.p')      AS p_value,
    IF(JSON_EXTRACT(json, '$.p') < 0.05,
       'Reject Null — visitor age profile does NOT match the town population',
       'Retain Null — visitor age profile matches the town population') AS conclusion
FROM gof\G

DROP TABLE tourist_visitors;

UNINSTALL EXTENSION vsql_statistics;
