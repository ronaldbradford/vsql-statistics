# VillageSQL Statistics Extension

Statistical aggregate functions for data scientists — IQR, quartiles, and outlier detection.

## Installing

Build and install the extension:

```bash
VillageSQL_BUILD_DIR=~/.villagesql bash build.sh
cp build/vsql_statistics.veb <veb_dir>/
```

Enable in a session:

```sql
INSTALL EXTENSION vsql_statistics;
```

## Quick Start

```sql
-- Detect outliers by region
SELECT
  region,
  STATS_IQR_LOWER_FENCE(CAST(sale_amount AS DOUBLE)) AS lower_fence,
  STATS_IQR_UPPER_FENCE(CAST(sale_amount AS DOUBLE)) AS upper_fence
FROM daily_sales
GROUP BY region;
```

## Function Reference

| Function | Returns | Description |
|---|---|---|
| `STATS_IQR(col)` | `DOUBLE` | Interquartile range: Q3 − Q1 |
| `STATS_Q1(col)` | `DOUBLE` | 25th percentile (Tukey's lower hinge) |
| `STATS_Q3(col)` | `DOUBLE` | 75th percentile (Tukey's upper hinge) |
| `STATS_MEDIAN(col)` | `DOUBLE` | 50th percentile |
| `STATS_IQR_LOWER_FENCE(col)` | `DOUBLE` | Q1 − 1.5 × IQR (outlier lower bound) |
| `STATS_IQR_UPPER_FENCE(col)` | `DOUBLE` | Q3 + 1.5 × IQR (outlier upper bound) |

All functions:
- Accept any numeric column (`INT`, `DOUBLE`, etc.)
- Skip NULL values; return NULL for an all-NULL group
- Use Tukey's hinges (exclusive median) for quartile computation
- Work with `GROUP BY`

## Building

**Prerequisites:** CMake 3.18+, C++17 compiler, VillageSQL Extension SDK 0.0.4+

```bash
VillageSQL_BUILD_DIR=/path/to/sdk bash build.sh
```

The `.veb` bundle is written to `build/vsql_statistics.veb`. Copy it to the directory shown by `SHOW VARIABLES LIKE 'veb_dir'`.

## Known Limitations

**INT column rounding.** When the input column is an `INT` type, VEF inherits the column type for result display, causing decimal values to be rounded (e.g. `STATS_IQR` on an INT column returns `8` instead of `7.5`). The underlying computation is correct.

Workaround: wrap the column in `CAST(col AS DOUBLE)`:

```sql
SELECT STATS_IQR(CAST(daily_count AS DOUBLE)) FROM espresso_sales;
-- Returns 7.5 (correct)

SELECT STATS_IQR(daily_count) FROM espresso_sales;
-- Returns 8 (rounded — INT column without CAST)
```

**Memory usage for large groups.** Exact quartile computation requires accumulating and sorting all values per group. For groups with millions of rows, memory and CPU cost will be proportional to group size. There is no streaming approximation within VEF.

**No in-place upgrade.** Upgrading the extension requires two separate steps:

```sql
UNINSTALL EXTENSION vsql_statistics;
INSTALL EXTENSION vsql_statistics;
```

## Testing

See `TESTING.md`.

## Reporting Bugs and Requesting Features

Open an issue at: https://github.com/villagesql/villagesql-server/issues

## Contact

- Discord: https://discord.gg/KSr6whd3Fr
- GitHub Issues: https://github.com/villagesql/villagesql-server/issues

## License

GPL-2.0. See `LICENSE`.
