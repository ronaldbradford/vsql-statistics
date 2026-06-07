/*
  Two-sample t-test: US vs Swedish male heights (inches)
  Source: https://www.theopeneducator.com/doe/hypothesis-Testing-Inferential-Statistics-Analysis-of-Variance-ANOVA/Two-Sample-T-Test-Equal-Variance

  Tests the null hypothesis that mean US and Swedish male heights are equal.
  Expected: t ≈ -2.570, df=58, p_two_tail ≈ 0.013 → Reject null at α=0.05.
*/

INSTALL EXTENSION vsql_statistics;

DROP TABLE IF EXISTS height_measurements;

CREATE TABLE height_measurements (
    id      INT   NOT NULL,
    us      FLOAT NOT NULL,
    swedish FLOAT NOT NULL,
    PRIMARY KEY (id)
);

INSERT INTO height_measurements (id, us, swedish) VALUES
(1,  69.12, 74.56),
(2,  66.88, 71.89),
(3,  74.82, 73.00),
(4,  67.00, 67.78),
(5,  69.12, 72.22),
(6,  65.00, 68.00),
(7,  71.00, 73.56),
(8,  66.76, 75.00),
(9,  72.12, 68.22),
(10, 72.94, 69.00),
(11, 69.18, 68.00),
(12, 66.18, 72.00),
(13, 64.94, 73.56),
(14, 71.76, 72.56),
(15, 70.12, 75.00),
(16, 71.00, 68.33),
(17, 71.88, 71.67),
(18, 65.24, 72.44),
(19, 70.06, 75.00),
(20, 71.94, 71.89),
(21, 72.12, 72.00),
(22, 66.88, 70.00),
(23, 73.82, 69.22),
(24, 74.00, 74.44),
(25, 71.18, 68.00),
(26, 67.88, 73.89),
(27, 65.94, 70.00),
(28, 68.88, 70.44),
(29, 68.00, 70.22),
(30, 75.12, 73.33);

-- Full t-test: compute inference statistics and per-group descriptives once,
-- then extract individual fields. Group 1 = US, Group 2 = Swedish.
WITH height_groups AS (
    SELECT CAST(us      AS DOUBLE) AS height, 1.0 AS grp FROM height_measurements
    UNION ALL
    SELECT CAST(swedish AS DOUBLE) AS height, 2.0 AS grp FROM height_measurements
),
ttest_results AS (
    SELECT
        CAST(STATS_TTEST(height, grp, 0.05)        AS CHAR(1000)) AS ttest_json,
        CAST(STATS_TTEST_GROUPS(height, grp)        AS CHAR(1000)) AS groups_json
    FROM height_groups
)
SELECT
    JSON_EXTRACT(groups_json, '$.mean_1')          AS mean_us,
    JSON_EXTRACT(groups_json, '$.mean_2')          AS mean_swedish,
    JSON_EXTRACT(groups_json, '$.variance_1')      AS variance_us,
    JSON_EXTRACT(groups_json, '$.variance_2')      AS variance_swedish,
    JSON_EXTRACT(groups_json, '$.n_1')             AS n_us,
    JSON_EXTRACT(groups_json, '$.n_2')             AS n_swedish,
    JSON_EXTRACT(ttest_json,  '$.pooled_var')      AS pooled_variance,
    JSON_EXTRACT(ttest_json,  '$.df')              AS degrees_of_freedom,
    JSON_EXTRACT(ttest_json,  '$.t')               AS t_statistic,
    JSON_EXTRACT(ttest_json,  '$.p_one_tail')      AS p_value_one_tail,
    JSON_EXTRACT(ttest_json,  '$.t_crit_one_tail') AS t_critical_one_tail,
    JSON_EXTRACT(ttest_json,  '$.p_two_tail')      AS p_value_two_tail,
    JSON_EXTRACT(ttest_json,  '$.t_crit_two_tail') AS t_critical_two_tail,
    IF(JSON_EXTRACT(ttest_json, '$.p_two_tail') < 0.05,
       'Reject Null — heights differ significantly',
       'Retain Null — no significant difference')  AS conclusion
FROM ttest_results;

DROP TABLE height_measurements;

UNINSTALL EXTENSION vsql_statistics;
