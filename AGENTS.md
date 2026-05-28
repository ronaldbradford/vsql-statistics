# AGENTS.md

This file provides guidance to AI coding assistants when working with code in this repository.

**Note**: Also check `AGENTS.local.md` for additional local development instructions when present.

## Project Overview

`vsql-statistics` is a VillageSQL extension that provides statistical aggregate functions for data scientists. The initial release implements the IQR (Interquartile Range) family: `STATS_IQR`, `STATS_Q1`, `STATS_Q3`, `STATS_MEDIAN`, `STATS_IQR_LOWER_FENCE`, and `STATS_IQR_UPPER_FENCE`. These functions operate on `DOUBLE` columns and are usable with `GROUP BY`, mirroring the statistical primitives found in Python (numpy/scipy) and R.

Install name (underscored): `vsql_statistics`
Repo/directory name (hyphenated): `vsql-statistics`

## Build System

Set `VillageSQL_BUILD_DIR` to the directory containing the extracted SDK (e.g., `~/.villagesql`):

```bash
VillageSQL_BUILD_DIR=~/.villagesql bash build.sh
```

The `build.sh` script runs cmake and cmake --build. The `.veb` bundle is created at `build/vsql_statistics.veb` and installed to `VillageSQL_VEB_INSTALL_DIR` (auto-detected from the server's `veb_dir`).

## Architecture

**Extension type:** Pure VDF — no custom types.

**Shared accumulation state:**
```cpp
struct StatsState {
    std::vector<double> values;
};
```
All six aggregate functions share the same `clear()` and `accumulate()` implementations. Each has its own `result()` function that sorts the accumulated values and computes the relevant statistic.

**Quartile algorithm:** Tukey's hinges (exclusive median). For a sorted vector of n values:
- Lower half: indices [0, n/2)
- Upper half: indices [n/2+1, n) for odd n, [n/2, n) for even n
- Q1 = median of lower half, Q3 = median of upper half
- NULL inputs are skipped; all-NULL group returns NULL
- n=1: Q1=Q3=value, IQR=0

**Function registration:** `make_aggregate_func<StatsState, &result_fn>(name).returns(REAL).param(REAL).clear<&stats_clear>().accumulate<&stats_accumulate>().build()`

**Key files:**
- `src/vsql_statistics.cc` — all six aggregate functions
- `manifest.json` — extension metadata
- `CMakeLists.txt` — build configuration
- `cmake/FindVillageSQL.cmake` — SDK discovery
- `mysql-test/t/` — MTR test files
- `mysql-test/r/` — expected results

## Testing

```bash
# From the VillageSQL prebuilt mysql-test directory:
perl mysql-test-run.pl --suite=/Users/rbradfor/projects/villagesql/vsql-statistics/mysql-test

# Record results:
perl mysql-test-run.pl --suite=/Users/rbradfor/projects/villagesql/vsql-statistics/mysql-test --record
```

See `TESTING.md` for full instructions.

## VillageSQL Extension Framework (VEF) API

- Include: `<villagesql/vsql.h>`, `using namespace vsql;`
- Aggregate registration: `make_aggregate_func<State, &result_fn>(name)`
- Input wrapper: `RealArg` — `is_null()`, `value()` → `double`
- Result wrapper: `RealResult` — `set(double)`, `set_null()`
- Type constants: `vsql::REAL`
- Entry point macro: `VEF_GENERATE_ENTRY_POINTS`

## Installation

```sql
INSTALL EXTENSION 'vsql_statistics';
SELECT STATS_IQR(col) FROM t GROUP BY group_col;
UNINSTALL EXTENSION vsql_statistics;
```

## Conventions

- All entry points wrapped in `try/catch (...)`
- NULL check before any field access inside every VDF
- No global mutable state (re-entrant)
- C++17 required
