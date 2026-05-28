# Testing vsql_statistics

## Prerequisites

- VillageSQL server running (check with `mysql -e "SELECT 1"`)
- Extension built and VEB copied to `veb_dir`
- MySQL Test Runner (`mysql-test-run.pl`) available in your VillageSQL installation

## Running the Test Suite

From your VillageSQL `mysql-test/` directory:

```bash
# Run all tests
perl mysql-test-run.pl --suite=/path/to/vsql-statistics/mysql-test

# Run a specific test
perl mysql-test-run.pl --suite=/path/to/vsql-statistics/mysql-test stats_iqr
```

## Recording Expected Results

If you add a new test or change an existing one, re-record the result file:

```bash
perl mysql-test-run.pl --suite=/path/to/vsql-statistics/mysql-test --record stats_iqr
```

Commit the updated `.result` file alongside the `.test` file.

## Test Coverage

| Test file | What it covers |
|---|---|
| `stats_iqr.test` | All six IQR functions; INT CAST workaround; single-row, two-row, and all-NULL edge cases; GROUP BY |

## Manual Spot-Check

```sql
INSTALL EXTENSION vsql_statistics;

CREATE TABLE espresso_sales (daily_count INT NOT NULL CHECK (daily_count >= 0));
INSERT INTO espresso_sales VALUES (7),(12),(15),(11),(4),(18),(14),(11),(30);

SELECT STATS_IQR(CAST(daily_count AS DOUBLE)) AS iqr FROM espresso_sales;
-- Expected: 7.5

SELECT STATS_IQR_LOWER_FENCE(CAST(daily_count AS DOUBLE)) AS lower,
       STATS_IQR_UPPER_FENCE(CAST(daily_count AS DOUBLE)) AS upper
FROM espresso_sales;
-- Expected: -2.25, 27.75

DROP TABLE espresso_sales;
UNINSTALL EXTENSION vsql_statistics;
```
