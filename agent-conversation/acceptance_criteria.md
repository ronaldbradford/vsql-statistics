# Acceptance Criteria

Setup:
  CREATE TABLE espresso_sales (daily_count INT NOT NULL CHECK (daily_count >= 0));
  INSERT INTO espresso_sales VALUES (7),(12),(15),(11),(4),(18),(14),(11),(30);

Note: INT columns require CAST(col AS DOUBLE) for decimal-precision output. Criteria 1–6 use
CAST(daily_count AS DOUBLE). Criteria 7 and 9 also use CAST. Without CAST, VEF returns
integer-rounded values (e.g. 8 instead of 7.5) — this is a documented VEF limitation.

1. Given the 9-row coffee shop dataset, STATS_IQR(CAST(daily_count AS DOUBLE)) must return 7.5
2. Given the same dataset, STATS_Q1(CAST(daily_count AS DOUBLE)) must return 9
3. Given the same dataset, STATS_Q3(CAST(daily_count AS DOUBLE)) must return 16.5
4. Given the same dataset, STATS_MEDIAN(CAST(daily_count AS DOUBLE)) must return 12
5. Given the same dataset, STATS_IQR_LOWER_FENCE(CAST(daily_count AS DOUBLE)) must return -2.25
6. Given the same dataset, STATS_IQR_UPPER_FENCE(CAST(daily_count AS DOUBLE)) must return 27.75
7. Given a single-row INT table {12}, STATS_IQR(CAST(col AS DOUBLE)) must return 0
8. Given a nullable DOUBLE column where all rows are NULL, STATS_IQR(col) must return NULL
9. Given a two-row INT table {5, 15}, STATS_IQR(CAST(col AS DOUBLE)) must return 10
