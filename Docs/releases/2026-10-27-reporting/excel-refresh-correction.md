# Excel refresh compatibility correction

Corrects the Excel repair warning reported after refreshing the reconciled workbook.

- Regenerated report headers now also update Excel table column definitions, including Bookings and Top Users, rather than retaining incompatible old names.
- Empty managed Excel tables retain a blank data row; Guest Members remains a valid native table when there are no guests.
- The old calculation chain, its relationship and content-type entry are removed after refresh. Formula caches are invalidated and automatic full recalculation is requested. Formula expressions are retained.
- The snapshot source note uses the current export timestamp rather than retaining the original extract timestamp.

Verified staging first and promoted only the report refresh implementation and its regression tests to production. Shared-source comparison passed; changed-file analysis clean. Targeted report/refresh suites: staging 11 passed; production 11 passed. No database or store deployment needed, no commits/pushes/version changes.

Recovered the user's exact unrepaired report snapshot: 334 total members (333 active, one inactive), 17 booking groups, three screen/platform groups. Corrected workbook opened through Excel's own file API using normal open mode, with seven native tables retained and no new Excel recovery log. Full recalculation gives Overview B12 = 146/333 = 43.8%, replacing the stale cached 41.7%. An Excel-saved verification copy retained all seven tables. Artifact import, formula-error scan and rendered overview also verified.

All 334 member names/contact/role and reconciliation fields checked against the input. Original Club source sheet XML remains byte-identical. User's original and corrupt workbooks were not overwritten. Corrected review copy is under outputs/excel-refresh-correction. Restart the local production Flutter process to load the source correction before generating another refresh.
