/*
  STATS_IQR examples

  STATS_IQR(col) returns the five-number summary and Tukey fence values:

    {"q1":..., "median":..., "q3":..., "iqr":...,
     "lower_fence":..., "upper_fence":...}

  q1, q3       — Tukey's hinges (exclusive-median method)
  iqr          — q3 − q1
  lower_fence  — q1 − 1.5 × iqr (Tukey inner lower fence)
  upper_fence  — q3 + 1.5 × iqr (Tukey inner upper fence)

  Values outside the fences are mild Tukey outliers.

  Three examples covering the main usage patterns:

  1. Parkrun finish times by age group  [GROUP BY, summary statistics]
     IQR grows with age, reflecting wider performance spread. Fence values
     joined back to the raw rows to count outliers per group.

  2. E-commerce order values  [single group, flag individual rows]
     Compute fences once in a subquery, cross-join to every row to tag
     each order as normal / low outlier / high outlier.

  3. Manufacturing: cylinder diameter by machine  [GROUP BY + join, counts]
     IQR per machine quantifies process consistency. Fences joined back
     to count both spec violations (engineering tolerance) and statistical
     outliers (Tukey) in one pass.
*/

INSTALL EXTENSION vsql_statistics;

-- ============================================================================
-- Example 1: Parkrun finish times by age group
-- ============================================================================
-- Pattern: GROUP BY → IQR stats per group → join fences to raw rows → count.
--
-- IQR grows with age group (3.3 → 3.7 → 5.4 → 8.8 min), confirming that
-- older runners span a wider range of fitness. Each group contains one walker
-- or injury finish that sits above the upper fence.

DROP TABLE IF EXISTS race_results;

CREATE TABLE race_results (
    runner_id   SMALLINT    NOT NULL,
    age_group   VARCHAR(10) NOT NULL,
    finish_time DOUBLE      NOT NULL    -- minutes
);

-- 12 finishers per group; the last entry in each group is a walker/injury
INSERT INTO race_results VALUES
    -- 18–29: competitive pack
    ( 1, '18-29', 17.2), ( 2, '18-29', 18.5), ( 3, '18-29', 19.1),
    ( 4, '18-29', 20.3), ( 5, '18-29', 21.0), ( 6, '18-29', 21.5),
    ( 7, '18-29', 22.0), ( 8, '18-29', 22.4), ( 9, '18-29', 22.8),
    (10, '18-29', 23.2), (11, '18-29', 23.6), (12, '18-29', 35.8),

    -- 30–44: slightly slower and more spread
    (13, '30-44', 20.5), (14, '30-44', 21.8), (15, '30-44', 22.5),
    (16, '30-44', 23.0), (17, '30-44', 23.8), (18, '30-44', 24.2),
    (19, '30-44', 24.8), (20, '30-44', 25.3), (21, '30-44', 26.0),
    (22, '30-44', 26.8), (23, '30-44', 27.5), (24, '30-44', 43.0),

    -- 45–59: broader fitness range
    (25, '45-59', 22.0), (26, '45-59', 23.5), (27, '45-59', 24.5),
    (28, '45-59', 25.2), (29, '45-59', 26.0), (30, '45-59', 26.8),
    (31, '45-59', 27.5), (32, '45-59', 28.2), (33, '45-59', 29.5),
    (34, '45-59', 31.0), (35, '45-59', 33.0), (36, '45-59', 55.0),

    -- 60+: widest performance spread
    (37, '60+', 25.0), (38, '60+', 27.5), (39, '60+', 28.5),
    (40, '60+', 30.0), (41, '60+', 31.0), (42, '60+', 32.0),
    (43, '60+', 33.5), (44, '60+', 35.0), (45, '60+', 37.0),
    (46, '60+', 39.0), (47, '60+', 42.0), (48, '60+', 67.0);

WITH iqr_stats AS (
    SELECT
        age_group,
        COUNT(*)                                            AS n,
        CAST(STATS_IQR(finish_time) AS CHAR(300))          AS json
    FROM race_results
    GROUP BY age_group
),
fences AS (
    SELECT
        age_group,
        n,
        ROUND(JSON_EXTRACT(json, '$.q1'),     2)  AS q1,
        ROUND(JSON_EXTRACT(json, '$.median'), 2)  AS median_time,
        ROUND(JSON_EXTRACT(json, '$.q3'),     2)  AS q3,
        ROUND(JSON_EXTRACT(json, '$.iqr'),    2)  AS iqr,
        JSON_EXTRACT(json, '$.lower_fence')        AS lower_fence,
        JSON_EXTRACT(json, '$.upper_fence')        AS upper_fence
    FROM iqr_stats
)
SELECT
    f.age_group,
    f.n,
    CONCAT(f.q1, '–', f.q3, ' min')            AS q1_q3,
    CONCAT(f.median_time, ' min')               AS median,
    CONCAT(f.iqr, ' min')                       AS iqr,
    CONCAT(ROUND(f.upper_fence, 2), ' min')     AS upper_fence,
    SUM(CASE
        WHEN r.finish_time > f.upper_fence
          OR r.finish_time < f.lower_fence THEN 1 ELSE 0
    END)                                        AS outlier_count
FROM race_results r
JOIN fences f USING (age_group)
GROUP BY f.age_group, f.n, f.q1, f.q3, f.median_time, f.iqr, f.lower_fence, f.upper_fence
ORDER BY f.age_group;

-- Expected:
--   18-29: Q1–Q3 = 19.70–23.00 min  IQR = 3.30 min  upper fence 27.95  outliers = 1 (35.8 min)
--   30-44: Q1–Q3 = 22.75–26.40 min  IQR = 3.65 min  upper fence 31.88  outliers = 1 (43.0 min)
--   45-59: Q1–Q3 = 24.85–30.25 min  IQR = 5.40 min  upper fence 38.35  outliers = 1 (55.0 min)
--   60+:   Q1–Q3 = 29.25–38.00 min  IQR = 8.75 min  upper fence 51.12  outliers = 1 (67.0 min)

DROP TABLE race_results;

-- ============================================================================
-- Example 2: E-commerce order values — flag individual outlier rows
-- ============================================================================
-- Pattern: single STATS_IQR call in a subquery → cross-join to every row.
--
-- Normal orders cluster between $45–$90. A $2 entry (cancelled/test) and
-- a $200 entry (bulk purchase) both fall outside the Tukey fences and are
-- flagged for review. The same query structure works for any single-group
-- outlier scan.

DROP TABLE IF EXISTS orders;

CREATE TABLE orders (
    order_id    SMALLINT    NOT NULL,
    customer    VARCHAR(20) NOT NULL,
    order_value DOUBLE      NOT NULL
);

-- 23 normal orders ($45–$90), one $2.00 test/refund, one $200.00 bulk order
INSERT INTO orders VALUES
    ( 1, 'Chen',      2.00),
    ( 2, 'Walsh',    45.00), ( 3, 'Patel',    48.00), ( 4, 'Kim',      50.00),
    ( 5, 'Jones',    52.00), ( 6, 'Singh',    54.00), ( 7, 'Brown',    56.00),
    ( 8, 'Lee',      58.00), ( 9, 'Kowalski', 60.00), (10, 'Müller',   62.00),
    (11, 'Tanaka',   64.00), (12, 'Rossi',    66.00), (13, 'Garcia',   68.00),
    (14, 'Ali',      70.00), (15, 'Ng',       72.00), (16, 'Petrov',   74.00),
    (17, 'Okafor',   76.00), (18, 'Yamada',   78.00), (19, 'Ferreira', 80.00),
    (20, 'Hassan',   82.00), (21, 'Ivanova',  84.00), (22, 'Dubois',   86.00),
    (23, 'Andersen', 88.00), (24, 'Bauer',    90.00),
    (25, 'Costa',   200.00);

WITH fences AS (
    SELECT
        JSON_EXTRACT(json, '$.q1')          AS q1,
        JSON_EXTRACT(json, '$.median')      AS median_value,
        JSON_EXTRACT(json, '$.q3')          AS q3,
        JSON_EXTRACT(json, '$.lower_fence') AS lower_fence,
        JSON_EXTRACT(json, '$.upper_fence') AS upper_fence
    FROM (
        SELECT CAST(STATS_IQR(order_value) AS CHAR(300)) AS json
        FROM orders
    ) s
)
SELECT
    o.order_id,
    o.customer,
    o.order_value,
    CASE
        WHEN o.order_value < f.lower_fence THEN 'LOW OUTLIER'
        WHEN o.order_value > f.upper_fence THEN 'HIGH OUTLIER'
        ELSE 'normal'
    END                                     AS flag
FROM orders o, fences f
ORDER BY o.order_value;

-- Expected fences (n=25, Q1=55, Q3=81, IQR=26):
--   lower_fence = 16.0  →  order #1 ($2.00) flagged LOW OUTLIER
--   upper_fence = 120.0 →  order #25 ($200.00) flagged HIGH OUTLIER

DROP TABLE orders;

-- ============================================================================
-- Example 3: Manufacturing — cylinder diameter by machine line
-- ============================================================================
-- Pattern: GROUP BY → STATS_IQR per machine → join fences back → counts.
--
-- Target diameter: 50.0 mm, engineering spec: ±2.0 mm (48.0–52.0 mm).
-- Machine A (well-calibrated):   IQR ≈ 0.60 mm, no violations
-- Machine B (slight upward bias): IQR ≈ 0.50 mm, median 50.6 mm — drifting high
-- Machine C (worn tooling):       IQR ≈ 3.00 mm, 4 spec violations, 1 Tukey outlier

DROP TABLE IF EXISTS components;

CREATE TABLE components (
    part_id  SMALLINT    NOT NULL,
    machine  CHAR(1)     NOT NULL,
    diameter DOUBLE      NOT NULL    -- mm
);

-- 15 measurements per machine
INSERT INTO components VALUES
    -- Machine A: tight, centred on 50.0
    ( 1, 'A', 49.2), ( 2, 'A', 49.4), ( 3, 'A', 49.6), ( 4, 'A', 49.7),
    ( 5, 'A', 49.8), ( 6, 'A', 49.9), ( 7, 'A', 50.0), ( 8, 'A', 50.0),
    ( 9, 'A', 50.1), (10, 'A', 50.2), (11, 'A', 50.2), (12, 'A', 50.3),
    (13, 'A', 50.4), (14, 'A', 50.5), (15, 'A', 50.6),

    -- Machine B: tight, but median has drifted to 50.6
    (16, 'B', 50.0), (17, 'B', 50.1), (18, 'B', 50.2), (19, 'B', 50.3),
    (20, 'B', 50.4), (21, 'B', 50.4), (22, 'B', 50.5), (23, 'B', 50.6),
    (24, 'B', 50.6), (25, 'B', 50.7), (26, 'B', 50.7), (27, 'B', 50.8),
    (28, 'B', 50.9), (29, 'B', 51.0), (30, 'B', 51.1),

    -- Machine C: worn tooling — wide spread, several parts outside spec
    (31, 'C', 47.5), (32, 'C', 48.2), (33, 'C', 48.5), (34, 'C', 49.0),
    (35, 'C', 49.5), (36, 'C', 49.8), (37, 'C', 50.0), (38, 'C', 50.2),
    (39, 'C', 50.5), (40, 'C', 51.0), (41, 'C', 51.5), (42, 'C', 52.0),
    (43, 'C', 52.5), (44, 'C', 53.0), (45, 'C', 57.5);

WITH iqr_stats AS (
    SELECT
        machine,
        COUNT(*)                                            AS n,
        CAST(STATS_IQR(diameter) AS CHAR(300))             AS json
    FROM components
    GROUP BY machine
),
fences AS (
    SELECT
        machine,
        n,
        ROUND(JSON_EXTRACT(json, '$.q1'),     2)  AS q1,
        ROUND(JSON_EXTRACT(json, '$.median'), 2)  AS median_mm,
        ROUND(JSON_EXTRACT(json, '$.q3'),     2)  AS q3,
        ROUND(JSON_EXTRACT(json, '$.iqr'),    2)  AS iqr_mm,
        JSON_EXTRACT(json, '$.lower_fence')        AS lower_fence,
        JSON_EXTRACT(json, '$.upper_fence')        AS upper_fence
    FROM iqr_stats
)
SELECT
    f.machine,
    f.median_mm,
    f.q1,
    f.q3,
    f.iqr_mm,
    SUM(CASE
        WHEN c.diameter < 48.0 OR c.diameter > 52.0 THEN 1 ELSE 0
    END)                                        AS spec_violations,
    SUM(CASE
        WHEN c.diameter < f.lower_fence
          OR c.diameter > f.upper_fence THEN 1 ELSE 0
    END)                                        AS tukey_outliers
FROM components c
JOIN fences f USING (machine)
GROUP BY f.machine, f.median_mm, f.q1, f.q3, f.iqr_mm, f.lower_fence, f.upper_fence
ORDER BY f.machine;

-- Expected:
--   A: median 50.00  Q1 49.70  Q3 50.30  IQR 0.60  spec_violations 0  tukey_outliers 0
--   B: median 50.60  Q1 50.30  Q3 50.80  IQR 0.50  spec_violations 0  tukey_outliers 0
--      (note: Machine B is drifting high — median 0.6 mm above target)
--   C: median 50.20  Q1 49.00  Q3 52.00  IQR 3.00  spec_violations 4  tukey_outliers 1
--      (4 parts outside ±2 mm spec; 57.5 mm is a statistical outlier)

DROP TABLE components;

UNINSTALL EXTENSION vsql_statistics;
