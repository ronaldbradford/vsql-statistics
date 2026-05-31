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
- accumulate signature: void(State&, RealArg[, RealArg...]) — NumParams args after State&
- result signature: void(const State&, RealResult)
- Input wrapper: vsql::RealArg — is_null(), value() -> double
- Result wrapper: vsql::RealResult — set(double), set_null(), error(msg)
- Type constants: vsql::REAL, vsql::INT, vsql::STRING
- kMaxParams: 8
- CMake: find_package(VillageSQL REQUIRED) via cmake/FindVillageSQL.cmake
- SDK discovery: VillageSQL_BUILD_DIR=~/.villagesql

## IQR Function Names (Phase 1, session 1)

| SQL name                  | result fn                          | params |
|---------------------------|------------------------------------|--------|
| STATS_IQR                 | stats_iqr_result                   | 1      |
| STATS_Q1                  | stats_q1_result                    | 1      |
| STATS_Q3                  | stats_q3_result                    | 1      |
| STATS_MEDIAN              | stats_median_result                | 1      |
| STATS_IQR_LOWER_FENCE     | stats_iqr_lower_fence_result       | 1      |
| STATS_IQR_UPPER_FENCE     | stats_iqr_upper_fence_result       | 1      |

## t-Test Function Names (Phase 1, session 2)

| SQL name                       | result fn                         | SQL params | accumulate       |
|--------------------------------|-----------------------------------|------------|------------------|
| STATS_TTEST_T                  | ttest_t_result                    | 2          | ttest_accumulate |
| STATS_TTEST_DF                 | ttest_df_result                   | 2          | ttest_accumulate |
| STATS_TTEST_POOLED_VAR         | ttest_pooled_var_result           | 2          | ttest_accumulate |
| STATS_TTEST_P_ONE_TAIL         | ttest_p_one_tail_result           | 2          | ttest_accumulate |
| STATS_TTEST_P_TWO_TAIL         | ttest_p_two_tail_result           | 2          | ttest_accumulate |
| STATS_TTEST_T_CRIT_ONE_TAIL    | ttest_t_crit_one_tail_result      | 3          | ttest_crit_accumulate |
| STATS_TTEST_T_CRIT_TWO_TAIL    | ttest_t_crit_two_tail_result      | 3          | ttest_crit_accumulate |

## IQR Design (session 1)

- Shared state: struct StatsState { std::vector<double> values; }
- Shared clear/accumulate across all 6 functions
- Algorithm: sort in result() → Tukey's hinges (exclusive median)
- NULL inputs: skipped; all-NULL group -> set_null()
- n=1: Q1=Q3=value, IQR=0
- preview_apis: none used

## t-Test Design (session 2)

- State: struct TTestState { std::vector<double> group1, group2; double alpha{0.05}; }
- ttest_clear: clears both vectors, resets alpha to 0.05
- ttest_accumulate(State&, RealArg value, RealArg group):
    skip if value or group is null; push to group1 if group==1.0, group2 if group==2.0, else skip
- ttest_crit_accumulate(State&, RealArg value, RealArg group, RealArg alpha):
    calls ttest_accumulate logic, then if !alpha.is_null() stores alpha.value()
- NULL return conditions:
    - either group empty → NULL
    - either group has n=1 (df would be ≤ 0) → NULL
    - pooled_var = 0 and means differ → NULL (degenerate; t would be ±inf)
    - pooled_var = 0 and means equal → t=0, p=1.0 (valid degenerate case)
- Algorithm:
    pooled_var = ((n1-1)*var1 + (n2-1)*var2) / (n1+n2-2)
    t = (mean1 - mean2) / sqrt(pooled_var * (1/n1 + 1/n2))
    df = n1 + n2 - 2
- p-value: regularized incomplete beta function via Lentz continued fraction
    P(|T|>t, df) = I_x(df/2, 0.5) where x = df/(df + t²)
    one-tail p = P(|T|>|t|) / 2
    two-tail p = P(|T|>|t|)
- critical value: bisection inversion of the one-tail p-value function
    t_crit such that P(T_df > t_crit) = alpha; 100 bisection iterations
- Math headers needed: <cmath> (lgamma, sqrt, exp, log, fabs)
- Implementation: all new math helpers and result functions appended to src/vsql_statistics.cc;
    VEF_GENERATE_ENTRY_POINTS extended with 7 new .func() calls
- Group indicator convention: 1.0 = group 1, 2.0 = group 2; other values silently ignored
- preview_apis: none used
