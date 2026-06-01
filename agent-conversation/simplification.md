# Simplification Review (Phase 3)

## Agent 1: Reuse & AI-Slop — 4 findings, 1 applied

- F1 (template quartile_result helper): REJECTED — after compute_quartiles takes by value (A2-F2), each result function body is already 3 lines; additional abstraction adds more complexity than it removes.
- F2 (remove try/catch): REJECTED — try/catch on all entry points is a required convention (CLAUDE.md, skill patterns.md). Blanket removal would violate the convention enforced in Phase 4.
- F3 (make_stats_func template helper): APPLIED — constexpr template helper eliminates 6× repeated .returns/.param/.clear/.accumulate builder chain. Required `.template` keyword for dependent template calls and `constexpr` for VEF_GENERATE_ENTRY_POINTS compatibility.
- F4 (remove section banner comments): APPLIED (partial) — removed section banners as visual noise. Retained the Tukey's hinges algorithm comment in compute_quartiles (non-obvious WHY).

## Agent 2: Quality — 5 findings, 1 applied

- F1 (copy-paste in result functions): REJECTED — overlaps with A1-F1; after A2-F2 fix the per-function body is 3 lines, not worth further abstraction.
- F2 (compute_quartiles takes by value): APPLIED — changed signature from `std::vector<double> &vals` to `std::vector<double> vals`. Callers now pass `s.values` directly; the copy is internalized. Eliminates the `auto vals = s.values` boilerplate from all 5 quartile-based result functions.
- F3 (repeated builder chain): APPLIED via A1-F3.
- F4 (__func__ in error strings): REJECTED — moot since try/catch is kept and renaming is unlikely; the added string construction overhead on the error path is not worth it.
- F5 (median via compute_quartiles): REJECTED — calling compute_quartiles and discarding q1/q3 obscures intent; sort + range_median directly is clearer for median's definition.

## Agent 3: Efficiency — 6 findings, 2 applied

- F1/F2/F3 (drop const, pass s.values directly): APPLIED via A2-F2 (compute_quartiles by value internalizes the copy).
- F4 (lazy-sort or insert-sorted): REJECTED — premature optimization; sort runs once per group at result time; the code is already O(n log n) per group which is unavoidable for exact quartiles.
- F5 (document sort precondition): REJECTED — moot after compute_quartiles takes by value; callers no longer mutate state.
- F6 (assert(lo < hi) in range_median): APPLIED — bounds assertion added; all three call sites verified safe.

---

## t-Test Simplification (session 2)

### Agent 1: Reuse & AI-Slop — 5 findings, 1 applied

- F1 (merge sum+SSQ loops): REJECTED — two-pass algorithm is numerically stable for a statistics library; computational formula Σv²−n·mean² risks catastrophic cancellation.
- F2 (template dispatcher for 7 result fns): REJECTED — adds indirection with no runtime benefit; 7 explicit functions are maintainable and readable.
- F3 (ttest_clear redundant alpha reset): APPLIED — `s = TTestState{}` replaces manual field resets; prevents future field-drift.
- F4 (remove comment from ttest_t_crit_two_tail_result): REJECTED — comment explains statistical meaning (why alpha is halved), not code mechanics.
- F5 (two factory templates differ by 1 param): N/A — agent flagged as genuine boundary, no action needed.

### Agent 2: Quality — 7 findings, 0 applied

- F1 (ttest_clear redundant alpha): APPLIED via A1-F3.
- F2 (alpha overwritten per row): REJECTED — intentional; alpha is a SQL constant expression in practice; validation adds complexity without benefit.
- F3 (error on non-1/2 group values): REJECTED — silent ignore is documented intentional behavior; VEF has no warning channel.
- F4 (cache TTestResult): REJECTED — each registered function owns its own TTestState; result() is called exactly once per group per function; nothing to cache.
- F5 (copy-paste in 7 result fns): REJECTED — overlaps with A1-F2; rejected for same reason.
- F6 (t_critical leaky abstraction): REJECTED — standard statistical convention; caller context is the correct place for one/two-tail distinction.
- F7 (factory template duplication): REJECTED — templates differ by accumulate function, not just param count; genuine boundary.

### Agent 3: Efficiency — 4 findings, 1 applied

- E1 (compute_quartiles pass by const ref): APPLIED — changed to `const std::vector<double> &vals_in` with explicit internal copy; makes ownership explicit.
- E2 (stats_median_result copy): N/A — agent confirmed no fix needed.
- E3 (cache TTestResult with mutable fields): REJECTED — same as A2-F4; each result() is called once per function per group on its own TTestState; mutable cache adds complexity for zero benefit.
- E4 (merge 4 loops into 2 with computational formula): REJECTED — same numerical stability concern as A1-F1.

---

## Mode Simplification (session 3)

### Agent 1: Reuse & AI-Slop — 4 findings, 1 applied

- F1 (merge factory templates via const char* NTTP): REJECTED — const char* NTTPs unreliable in C++17; two-template pattern already established in file
- F2 (std::max_element for max loop): REJECTED — superseded by A2-F3 single-pass which eliminates the loop entirely
- F3 (trim redundant comment first line): APPLIED — kept only the non-obvious policy line
- F4 (inline mode_clear as lambda): REJECTED — VEF .template clear<>() requires named function pointer as NTTP; C++17 lambdas cannot fill this role

### Agent 2: Quality — 5 findings, 4 applied

- F1 (factory template duplication): REJECTED — same as A1-F1
- F2 (min/max result functions sort full vector to take one element): APPLIED — replaced compute_modes with dedicated two-pass helpers over freq; no vector allocation or sort
- F3 (single-pass compute_modes): APPLIED — collapses two scans into one; also resolves E2 over-reserve
- F4 (s = ModeState{} in mode_clear): APPLIED — changed to s.freq.clear() to retain bucket allocation across groups
- F5 (%lld overflow for large doubles): APPLIED — replaced integer/float branch with %g for all values; removes cast, branch, and overflow

### Agent 3: Efficiency — 4 findings, 3 applied

- E1 (mode_clear rebuilds map): APPLIED via A2-F4
- E2 (over-reserve in compute_modes): N/A — resolved by A2-F3 single-pass
- E3 (min/max result sort + discard): APPLIED via A2-F2
- E4 (NaN guard in mode_accumulate): APPLIED — added !std::isnan(v.value()) to prevent unbounded map growth from NaN keys

---

## Skewness Simplification (session 4)

### Agent 1: Reuse & AI-Slop — 6 findings, 1 applied

- F1 (std::accumulate/inner_product for loops): REJECTED — not a meaningful deduplication; inner_product approach risks same cancellation flagged by A3-E6
- F2 (move sort after mean loop): APPLIED via A2-F3 restructure — mean now computed from s.values before copy+sort
- F3 (n<3 guard for both functions): REJECTED — n=2 is mathematically valid for both formulas; m2<=0 guard handles degenerate cases
- F4 (remove try/catch): REJECTED — required project convention per AGENTS.md
- F5 (make_moment_skew_func single caller): Not actionable — correctly identified as not a problem
- F6 (remove second comment line): REJECTED — "avoid storing individual values" explains the non-obvious WHY (streaming vs. storing all values)

### Agent 2: Quality — 7 findings, 2 applied

- F1, F2: Not findings (confirmed no issue)
- F3 (std::accumulate for mean): APPLIED — cleaner, one line; also allows deferring copy+sort until after stddev check
- F4 (extract compute_variance helper): REJECTED — premature abstraction for a single call site
- F5 (kMinSamples constant): REJECTED — adds boilerplate; n < 2 is self-documenting
- F6 (rename make_skew_func → make_moment_skew_func): APPLIED — clarifies that this factory is for moment-based (SkewState) only; prevents accidental misuse with Pearson result fn
- F7 (stringly-typed error messages): REJECTED — consistent with all 16 existing functions in the file

### Agent 3: Efficiency — 8 findings, 2 applied

- E1: Not a finding
- E2 (cache x² in skew_accumulate): APPLIED — `double x2 = x*x; sum_sq += x2; sum_cu += x2*x`
- E3 (heap allocation necessary): Confirmed unavoidable
- E4 (two passes unavoidable): Confirmed clean
- E5 (StatsState lacks running sum): Design boundary — can't fix without changing shared state
- E6 (shift accumulator by first value for numerical stability): APPLIED — `ref` field added; centering eliminates catastrophic cancellation for large/offset inputs (e.g., salary data)
- E7 (n<2 redundant with m2 guard): REJECTED — cheap fast-path; harmless
- E8 (range_median bound): REJECTED — hi is exclusive per existing implementation; call `range_median(vals, 0, n)` is correct

## Z-Test Simplification (session 5)

### Agent 1: Reuse & AI-Slop — 2 findings applied, 3 rejected

- F1 (one-tail formula semantics): APPLIED (documentation) — added comment clarifying P_ONE_TAIL returns upper-tail P(Z>z) per spec; formula is correct per spec, no change.
- F2 (NaN sigma passthrough): APPLIED — changed `s.sigma <= 0.0` to `!(s.sigma > 0.0)` to reject NaN sigma.
- F3 (struct comment "last-value-wins per row"): APPLIED — updated to "last non-null wins".
- F4 (extract sqrt(2.0) constant): REJECTED — compiler constant-folds std::sqrt(2.0) at -O2; called once per group, not per row.
- F6 (comment at line 494 restates code): APPLIED — replaced formula comment with "why NULL for non-positive sigma".

### Agent 2: Quality — 3 findings applied, 2 rejected

- F1 (mu/sigma updates before value null-check): REJECTED — intentional; matches ttest_crit_accumulate pattern where constant params update regardless of value nullness.
- F2 (uninitialized double z): APPLIED — initialized to 0.0 in all three result functions.
- F3 (sigma default 1.0 → 0.0): APPLIED — default changed to 0.0 so all-null sigma returns NULL via existing sigma<=0 guard.
- F4 (add param comments in make_ztest_func): REJECTED — project convention uses accumulate function signature + section header; no param comments elsewhere in file.
- F5 (one-tail formula): Duplicate of A1-F1.

### Agent 3: Efficiency — 1 finding applied, 2 rejected

- F1 (all-null sigma uses sentinel): APPLIED — same fix as A2-F3.
- F2 (one-tail p-value directional): Duplicate of A1-F1.
- F4 (NaN sigma passthrough): Duplicate of A1-F2.

## Chi-Squared Simplification (session 6)

Three simplification agents reviewed the chi-squared implementation after first build.

### Applied

- `gamma_prefix` helper extracted — removes duplication of `exp(-x + a*log(x) - lgamma(a))` from both `gammap_series` and `gammacf`.
- `chisq_accumulate_cell` helper extracted — removes duplication of the (O-E)²/E accumulation logic between `chisq_gof_accumulate` and `chisq_indep_accumulate`.
- Guard order in `stats_chisq_indep_p_result` fixed — check `!(n_rows > 0) || !(n_cols > 0)` before computing df, preventing NaN passthrough when n_rows or n_cols is NaN.
- `ChiSqIndepState::k` field added — returns NULL when all-NULL inputs are passed with non-null n_rows/n_cols (previously returned Q(0.5, 0.0)=1 instead of NULL).

### Rejected

- Type mismatch: `stats_chisq_indep_result` using `ChiSqGofState` flagged as bug by all three agents — REJECTED. Intentional design: `STATS_CHISQ_INDEP` is a 2-param aggregate (same formula as GoF); registered via `make_chisq_gof_func`. The separate `ChiSqIndepState` is only needed for `STATS_CHISQ_INDEP_P` which takes 4 params.
- C-style casts `(double)i` → `static_cast<double>` — REJECTED. Consistent with existing style throughout the file (betacf, ttest, etc.).
- Clear function indirection (lambda vs direct) — REJECTED. Consistent with all other families in the file.
- n_rows/n_cols accumulated even when observed/expected null — REJECTED. Intentional; matches ztest_accumulate pattern where constants update regardless of value nullness.
- `gammap_series` a=0 guard — REJECTED. `a` is always df/2 with df≥2 when called, so a≥1.
- `gammacf` convergence NaN guard — REJECTED. Standard Lentz TINY guard handles near-zero; no observed non-convergence in tests.
