# Architecture

## Session Info

- villagesql_server_version: 0.0.4
- veb_dir: /Users/rbradfor/.villagesql/prebuilt/lib/veb/
- sdk_dir: /Users/rbradfor/.villagesql/villagesql-extension-sdk-0.0.4/
- sdk_version (confirmed via villagesql_config --version): 0.0.4
- local_only: true
- pg_port: false

## Extension

- Install name: vsql_statistics
- Repo/dir name: vsql-statistics
- Type: Pure VDF (no custom types)

## API Names (from SDK headers)

- Entry point: VEF_GENERATE_ENTRY_POINTS
- Aggregate builder: vsql::make_aggregate_func<State, &result_fn>(name)
- clear signature: void(State&)
- accumulate signature: void(State&, RealArg)
- result signature: void(const State&, RealResult)
- Input wrapper: vsql::RealArg — is_null(), value() -> double
- Result wrapper: vsql::RealResult — set(double), set_null(), error(msg)
- Type constants: vsql::REAL, vsql::INT, vsql::STRING
- kMaxParams: 8
- CMake: find_package(VillageSQL REQUIRED) via cmake/FindVillageSQL.cmake
- SDK discovery: VillageSQL_BUILD_DIR=~/.villagesql

## Function Names

| SQL name                  | result fn                          |
|---------------------------|------------------------------------|
| STATS_IQR                 | stats_iqr_result                   |
| STATS_Q1                  | stats_q1_result                    |
| STATS_Q3                  | stats_q3_result                    |
| STATS_MEDIAN              | stats_median_result                |
| STATS_IQR_LOWER_FENCE     | stats_iqr_lower_fence_result       |
| STATS_IQR_UPPER_FENCE     | stats_iqr_upper_fence_result       |

## Design

- Shared state: struct StatsState { std::vector<double> values; }
- Shared clear/accumulate across all 6 functions
- Algorithm: sort in result() → Tukey's hinges (exclusive median)
- NULL inputs: skipped (not accumulated); all-NULL group -> set_null()
- n=1: Q1=Q3=value, IQR=0
- preview_apis: none used
