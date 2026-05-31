# Acceptance Criteria

## IQR Functions (session 1)

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

## t-Test Functions (session 2)

Setup (hand-verifiable: t=1.0 exactly, pooled_var=250, df=8):
  CREATE TABLE ttest_data (value DOUBLE, grp INT);
  INSERT INTO ttest_data VALUES (100,1),(110,1),(120,1),(130,1),(140,1);
  INSERT INTO ttest_data VALUES (90,2),(100,2),(110,2),(120,2),(130,2);

Derivation:
  mean1=120, mean2=110, var1=250, var2=250
  pooled_var = (4*250 + 4*250) / 8 = 250
  df = 8
  t = (120-110) / sqrt(250*(1/5+1/5)) = 10/10 = 1.0

10. Given ttest_data with grp 1 vs 2, STATS_TTEST_T(value, grp) must return 1.0
11. Given ttest_data, STATS_TTEST_DF(value, grp) must return 8.0
12. Given ttest_data, STATS_TTEST_POOLED_VAR(value, grp) must return 250.0
13. Given ttest_data, STATS_TTEST_P_ONE_TAIL(value, grp) must return 0.17329675354366686
14. Given ttest_data, STATS_TTEST_P_TWO_TAIL(value, grp) must return 0.3465935070873337
15. Given ttest_data, STATS_TTEST_T_CRIT_ONE_TAIL(value, grp, 0.05) must return ~1.8595
16. Given ttest_data, STATS_TTEST_T_CRIT_TWO_TAIL(value, grp, 0.05) must return ~2.3060
17. Given only group 1 present (no group 2 rows), any STATS_TTEST_* must return NULL
18. Given group 1 has exactly 1 row and group 2 has 3 rows, any STATS_TTEST_* must return NULL
19. Given all values NULL, STATS_TTEST_T(value, grp) must return NULL

## Mode Functions (session 3)

Setup:
  CREATE TABLE mode_data (val INT NOT NULL);

Note: INT columns require CAST(col AS DOUBLE). All criteria use CAST(val AS DOUBLE).

20. Given {12,15,12,18,21,15,15,14}, STATS_MODE(CAST(val AS DOUBLE)) must return '[15]'
21. Given {24,29,24,35,42,29,38,22}, STATS_MODE(CAST(val AS DOUBLE)) must return '[24, 29]'
22. Given {12,15,12,18,21,15,15,14}, STATS_MODE_MIN(CAST(val AS DOUBLE)) must return 15
23. Given {12,15,12,18,21,15,15,14}, STATS_MODE_MAX(CAST(val AS DOUBLE)) must return 15
24. Given {24,29,24,35,42,29,38,22}, STATS_MODE_MIN(CAST(val AS DOUBLE)) must return 24
25. Given {24,29,24,35,42,29,38,22}, STATS_MODE_MAX(CAST(val AS DOUBLE)) must return 29
26. Given all-unique {1,2,3,4}, STATS_MODE(CAST(val AS DOUBLE)) must return NULL
27. Given all-unique {1,2,3,4}, STATS_MODE_MIN(CAST(val AS DOUBLE)) must return NULL
28. Given all-unique {1,2,3,4}, STATS_MODE_MAX(CAST(val AS DOUBLE)) must return NULL
29. Given a single-row {42}, STATS_MODE(CAST(val AS DOUBLE)) must return NULL
30. Given a nullable DOUBLE column where all rows are NULL, STATS_MODE(col) must return NULL
