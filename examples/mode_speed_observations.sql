/*
  Mode: speed camera observations by road type
  Function: STATS_MODE returns JSON {"values": [...], "min": x, "max": y}

  Context: 150 vehicle speed readings (integer mph) recorded at three road types.
  Mode reveals the most common speed(s) driven — useful for traffic planning
  and understanding whether drivers cluster around speed limits.

    Motorway (50 obs, limit 70 mph)
      Speeds concentrate at 70 mph.
      Expected: mode = {70} — unimodal, drivers observe the speed limit

    Urban 30 zone (50 obs, limit 30 mph)
      Speeds split between drivers doing ~20 mph (cautious) and ~30 mph (limit).
      Expected: modes = {20, 30} — bimodal, two equally common behaviours

    Rural (50 obs, limit 60 mph)
      Speeds concentrate just below the 60 mph limit.
      Expected: mode = {60} — unimodal

  Speed frequencies are inserted in batches per value to keep the file concise.
*/

INSTALL EXTENSION vsql_statistics;

DROP TABLE IF EXISTS speed_observations;

CREATE TABLE speed_observations (
    road_type VARCHAR(10) NOT NULL,
    speed_mph DOUBLE      NOT NULL
);

-- ============================================================================
-- Motorway: 50 observations, clustering at 70 mph
-- ============================================================================
INSERT INTO speed_observations VALUES
    ('motorway', 65), ('motorway', 65), ('motorway', 65),
    ('motorway', 67), ('motorway', 67), ('motorway', 67), ('motorway', 67),
    ('motorway', 68), ('motorway', 68), ('motorway', 68), ('motorway', 68), ('motorway', 68),
    ('motorway', 69), ('motorway', 69), ('motorway', 69), ('motorway', 69),
    ('motorway', 69), ('motorway', 69), ('motorway', 69),
    ('motorway', 70), ('motorway', 70), ('motorway', 70), ('motorway', 70),
    ('motorway', 70), ('motorway', 70), ('motorway', 70), ('motorway', 70),
    ('motorway', 70), ('motorway', 70), ('motorway', 70), ('motorway', 70),
    ('motorway', 71), ('motorway', 71), ('motorway', 71), ('motorway', 71),
    ('motorway', 71), ('motorway', 71), ('motorway', 71), ('motorway', 71),
    ('motorway', 72), ('motorway', 72), ('motorway', 72), ('motorway', 72),
    ('motorway', 72), ('motorway', 72),
    ('motorway', 73), ('motorway', 73), ('motorway', 73),
    ('motorway', 75), ('motorway', 75);

-- ============================================================================
-- Urban 30 zone: 50 observations, bimodal at 20 and 30 mph
-- ============================================================================
INSERT INTO speed_observations VALUES
    ('urban', 18), ('urban', 18), ('urban', 18),
    ('urban', 19), ('urban', 19), ('urban', 19), ('urban', 19),
    ('urban', 20), ('urban', 20), ('urban', 20), ('urban', 20),
    ('urban', 20), ('urban', 20), ('urban', 20), ('urban', 20),
    ('urban', 21), ('urban', 21), ('urban', 21), ('urban', 21), ('urban', 21),
    ('urban', 22), ('urban', 22), ('urban', 22),
    ('urban', 28), ('urban', 28), ('urban', 28),
    ('urban', 29), ('urban', 29), ('urban', 29), ('urban', 29), ('urban', 29),
    ('urban', 30), ('urban', 30), ('urban', 30), ('urban', 30),
    ('urban', 30), ('urban', 30), ('urban', 30), ('urban', 30),
    ('urban', 31), ('urban', 31), ('urban', 31), ('urban', 31), ('urban', 31),
    ('urban', 32), ('urban', 32), ('urban', 32),
    ('urban', 35), ('urban', 35), ('urban', 35);

-- ============================================================================
-- Rural: 50 observations, clustering just at 60 mph
-- ============================================================================
INSERT INTO speed_observations VALUES
    ('rural', 50), ('rural', 50),
    ('rural', 53), ('rural', 53), ('rural', 53),
    ('rural', 55), ('rural', 55), ('rural', 55), ('rural', 55), ('rural', 55),
    ('rural', 57), ('rural', 57), ('rural', 57), ('rural', 57),
    ('rural', 57), ('rural', 57),
    ('rural', 58), ('rural', 58), ('rural', 58), ('rural', 58),
    ('rural', 58), ('rural', 58), ('rural', 58),
    ('rural', 59), ('rural', 59), ('rural', 59), ('rural', 59),
    ('rural', 59), ('rural', 59), ('rural', 59), ('rural', 59),
    ('rural', 60), ('rural', 60), ('rural', 60), ('rural', 60),
    ('rural', 60), ('rural', 60), ('rural', 60), ('rural', 60),
    ('rural', 60), ('rural', 60),
    ('rural', 61), ('rural', 61), ('rural', 61), ('rural', 61), ('rural', 61),
    ('rural', 62), ('rural', 62), ('rural', 62), ('rural', 62);

-- ============================================================================
-- Verify row counts per road type
-- ============================================================================
SELECT road_type, COUNT(*) AS n FROM speed_observations GROUP BY road_type ORDER BY road_type;

-- ============================================================================
-- Mode results with full descriptives
-- ============================================================================
WITH stats AS (
    SELECT
        road_type,
        COUNT(*)                               AS n,
        ROUND(MIN(speed_mph), 0)               AS min_speed,
        ROUND(AVG(speed_mph), 2)               AS mean_speed,
        ROUND(MAX(speed_mph), 0)               AS max_speed,
        CAST(STATS_MODE(speed_mph) AS CHAR(200))  AS mode_json,
        CAST(STATS_IQR(speed_mph)  AS CHAR(300))  AS iqr_json
    FROM speed_observations
    GROUP BY road_type
)
SELECT
    road_type,
    n,
    min_speed,
    mean_speed,
    max_speed,
    ROUND(JSON_EXTRACT(iqr_json, '$.median'), 1)       AS median_speed,
    ROUND(JSON_EXTRACT(iqr_json, '$.iqr'),    1)       AS iqr,
    JSON_EXTRACT(mode_json, '$.values')                AS mode_values,
    JSON_EXTRACT(mode_json, '$.min')                   AS mode_min,
    JSON_EXTRACT(mode_json, '$.max')                   AS mode_max,
    JSON_LENGTH(JSON_EXTRACT(mode_json, '$.values'))   AS mode_count,
    CASE
        WHEN mode_json IS NULL                                             THEN 'No mode'
        WHEN JSON_LENGTH(JSON_EXTRACT(mode_json, '$.values')) = 1         THEN 'Unimodal'
        ELSE CONCAT('Multimodal (', JSON_LENGTH(JSON_EXTRACT(mode_json, '$.values')), ' modes)')
    END                                                AS shape
FROM stats
ORDER BY road_type;

DROP TABLE speed_observations;

UNINSTALL EXTENSION vsql_statistics;
