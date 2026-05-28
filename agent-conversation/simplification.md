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
