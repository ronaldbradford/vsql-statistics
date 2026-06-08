/*
  Chi-squared tests: customer support analysis

  Goodness-of-fit: are support tickets distributed evenly across weekdays?
    500 tickets over one week, uniform expectation = 100/day
    Observed: Mon=140, Tue=110, Wed=95, Thu=85, Fri=70
    Expected: chi_sq=28.5, df=4, p≈0.0000096 → Reject null at α=0.05

  Test of independence: is ticket resolution speed independent of agent experience?
    200 tickets, 2×2 contingency: junior/senior × fast/slow resolution
    Expected under independence: chi_sq=33.33, df=1, p≈0.0000000078 → Reject null at α=0.05
*/

INSTALL EXTENSION vsql_statistics;

-- ============================================================================
-- Goodness of fit: support ticket volume by weekday
-- ============================================================================

DROP TABLE IF EXISTS tickets_by_day;

CREATE TABLE tickets_by_day (
    day_name VARCHAR(10) NOT NULL,
    observed DOUBLE      NOT NULL,
    expected DOUBLE      NOT NULL
);

INSERT INTO tickets_by_day VALUES
    ('Monday',     140, 100),
    ('Tuesday',    110, 100),
    ('Wednesday',   95, 100),
    ('Thursday',    85, 100),
    ('Friday',      70, 100);

WITH gof AS (
    SELECT CAST(STATS_CHISQ_GOF(observed, expected) AS CHAR(200)) AS json
    FROM tickets_by_day
)
SELECT
    JSON_EXTRACT(json, '$.chi_sq') AS chi_squared,
    JSON_EXTRACT(json, '$.df')     AS degrees_of_freedom,
    JSON_EXTRACT(json, '$.p')      AS p_value,
    IF(JSON_EXTRACT(json, '$.p') < 0.05,
       'Reject Null — ticket volume is NOT uniform across weekdays',
       'Retain Null — no significant difference across weekdays') AS conclusion
FROM gof\G

DROP TABLE tickets_by_day;

-- ============================================================================
-- Test of independence: resolution speed vs. agent experience
-- ============================================================================

DROP TABLE IF EXISTS resolution_survey;

CREATE TABLE resolution_survey (
    experience VARCHAR(10) NOT NULL,
    resolution VARCHAR(10) NOT NULL,
    observed   DOUBLE      NOT NULL,
    expected   DOUBLE      NOT NULL  -- row_total × col_total / 200
);

INSERT INTO resolution_survey VALUES
    ('Junior', 'Fast',  20, 40),
    ('Junior', 'Slow',  80, 60),
    ('Senior', 'Fast',  60, 40),
    ('Senior', 'Slow',  40, 60);

WITH indep AS (
    SELECT CAST(STATS_CHISQ_INDEP(observed, expected, 2.0, 2.0) AS CHAR(200)) AS json
    FROM resolution_survey
)
SELECT
    JSON_EXTRACT(json, '$.chi_sq') AS chi_squared,
    JSON_EXTRACT(json, '$.df')     AS degrees_of_freedom,
    JSON_EXTRACT(json, '$.p')      AS p_value,
    IF(JSON_EXTRACT(json, '$.p') < 0.05,
       'Reject Null — resolution speed IS linked to agent experience',
       'Retain Null — resolution speed is independent of agent experience') AS conclusion
FROM indep\G

DROP TABLE resolution_survey;

UNINSTALL EXTENSION vsql_statistics;
