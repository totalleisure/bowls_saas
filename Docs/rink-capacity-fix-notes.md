# Rink capacity correction — 25 September 2026

## Production database: applied by Wayne

Wayne confirmed running `Rink-capacity-fix.sql` in the live database on 25 September 2026. It replaces only `get_green_rink_availability` and `check_green_area_rink_capacity`, in one transaction. It does not change fixture data, tables, policies, grants, or trigger definitions. `Rink-capacity-rollback.sql` restores the original definitions supplied from production.

The error was adding every fixture overlapping a requested period. Three rinks until 11:10 and five afterwards were counted as eight. The corrected calculation uses the maximum simultaneous demand: five, leaving one rink available between 10:00 and 13:00 in the supplied scenario. Cancelled fixtures are excluded. Maintenance is counted at the same time as fixtures, with duplicate maintenance records for a single rink counted once.

Physical rink blocking still checks the entire requested interval. Peak spare capacity does not promise that an individual rink is free throughout; the per-rink `is_booked` result retains that check. The four-hour fallback for fixtures without an end time is preserved through the existing time-range trigger.

After applying, reopen the affected booking and check that R5 can be selected for 10:00–13:00, provided the actual bookings still match the screenshot. This database correction benefits existing installed app versions. Do not expect their hourly header numbers to change until the app update is installed.

## Local app: corrected

In `C:\src\bowls_saas`, branch `release/production-preaudit-timeout`, the rink day view now displays peak simultaneous assignment counts per hour. The screenshot's 11:00, 13:00 and 16:00 headers become 5, 6 and 6. Genuine overlapping assignments are still counted, rather than hidden by a cap of six. Calendar times are normalised to the app's club wall-clock convention.

Changed sources: `lib/features/diary/rinks_day_view.dart`, new `lib/core/utils/peak_interval_usage.dart`, new `test/peak_interval_usage_test.dart`, and the two existing SQL definition files. Audit-development changes remain preserved separately. This correction is being recorded in a focused production commit. No push or new release package has been created for it.

## Verification and limits

- Isolated PostgreSQL-compatible PGlite test reproduced original false demand of eight and verified corrected demand of five, R5 free, and one spare rink.
- Tested the actual capacity trigger accepting one additional rink and rejecting excess demand; cancellation; self-exclusion on update; adjacent and empty intervals; maintenance timing and duplicate maintenance; existing and new fixtures without end times; rollback and reapplication.
- Three Flutter regression tests passed for the screenshot, genuine excess overlaps and time boundaries.
- Windows debug build passed with the final club-time alignment change.
- These are isolated tests, not authenticated production testing or a concurrency/load test. Existing concurrent-booking race behaviour is not addressed by this change.

The earlier fixture-loading timeout fix is a separate, database-only policy optimisation already recorded as deployed on 24 September. This capacity correction does not replace or undo it.
