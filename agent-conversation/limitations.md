# Limitations

## Confirmed (from Phase 1 header analysis)

- **O(n log n) sort per group:** Exact quartile computation requires sorting all accumulated values per group. No streaming/online algorithm exists for exact quartiles. For large groups (millions of rows), memory and CPU cost will be significant. Workaround: none within VEF. VEF capability that would help: a streaming aggregate API with merge support.

## Confirmed from Phase 3 probes

- **INT columns return integer-rounded results:** VEF aggregate functions inherit the MySQL result type from the input column. When the column is INT, the REAL return value is rounded to the nearest integer (e.g. STATS_IQR on an INT column returns 8 instead of 7.5). Workaround: wrap the column in CAST(col AS DOUBLE). This is a VEF type-inference limitation; the underlying computation is correct.

- **INT→DOUBLE coercion:** Calling STATS_IQR(int_col) on an INT column works — MySQL coerces INT to DOUBLE before the VDF receives it. No explicit CAST required.
- **No ALTER EXTENSION:** Extension upgrade requires UNINSTALL EXTENSION + INSTALL EXTENSION as separate steps. No in-place upgrade command exists.

- **STATS_MODE hex display in mysql CLI:** VEF 0.0.4 `STRING` return type carries no character set metadata. The MySQL client treats the result as binary and displays it as hex (e.g. `0x5B31355D` instead of `[15]`). The underlying data is correct. Workarounds: `mysql --skip-binary-as-hex` for interactive sessions; `CAST(STATS_MODE(...) AS CHAR)` in SQL. Root cause: VEF ABI has an open question on encoding/collation support (noted in abi/types.h).
