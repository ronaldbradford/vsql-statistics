/*
  Chi-squared test of independence: COVID-19 symptom status by household size
  Source: https://www.technologynetworks.com/informatics/articles/the-chi-squared-test-368882
  "The Chi-Squared Test", Technology Networks (author: Elliot McClenaghan, LSHTM)

  Research question: Is household size associated with symptomatic COVID-19 infection
  among people who tested positive for the virus?

  Design: 2×2 contingency table
    Rows:    household size — Small (1–3 members) vs Large (4+ members)
    Columns: symptom status — Symptomatic vs Asymptomatic
    N = 218 participants who tested positive for COVID-19

  H₀: There is no association between household size and symptomatic COVID-19 infection
      (the true difference in proportions symptomatic between household groups is zero)
  H₁: There is an association between household size and symptomatic COVID-19 infection
  α = 0.05

  Observed (Table 1):
                  Symptomatic  Asymptomatic  Total
    Small (1–3)        30           43          73
    Large (4+)         96           49         145
    Total             126           92         218

  Expected = (row_total × col_total) / grand_total (Table 2):
    Small / Symptomatic:   73  × 126 / 218 = 42.1
    Small / Asymptomatic:  73  ×  92 / 218 = 30.8
    Large / Symptomatic:  145  × 126 / 218 = 83.8
    Large / Asymptomatic: 145  ×  92 / 218 = 61.2

  Expected: chi_sq = 12.51, df = 1, p < 0.001 → Reject H₀
*/

INSTALL EXTENSION vsql_statistics;

DROP TABLE IF EXISTS covid_household;

CREATE TABLE covid_household (
    household_size VARCHAR(10) NOT NULL,   -- 'Small' or 'Large'
    symptom_status VARCHAR(15) NOT NULL,   -- 'Symptomatic' or 'Asymptomatic'
    observed       DOUBLE      NOT NULL,
    expected       DOUBLE      NOT NULL    -- (row_total × col_total) / 218
);

INSERT INTO covid_household VALUES
    ('Small', 'Symptomatic',    30,  73 * 126 / 218),
    ('Small', 'Asymptomatic',   43,  73 *  92 / 218),
    ('Large', 'Symptomatic',    96, 145 * 126 / 218),
    ('Large', 'Asymptomatic',   49, 145 *  92 / 218);

WITH indep AS (
    SELECT CAST(STATS_CHISQ_INDEP(observed, expected, 2.0, 2.0) AS CHAR(200)) AS json
    FROM covid_household
)
SELECT
    JSON_EXTRACT(json, '$.chi_sq') AS chi_squared,
    JSON_EXTRACT(json, '$.df')     AS degrees_of_freedom,
    JSON_EXTRACT(json, '$.p')      AS p_value,
    IF(JSON_EXTRACT(json, '$.p') < 0.05,
       'Reject H₀ — household size IS associated with symptomatic COVID-19',
       'Retain H₀ — no significant association between household size and symptoms') AS conclusion
FROM indep\G

DROP TABLE covid_household;

UNINSTALL EXTENSION vsql_statistics;
