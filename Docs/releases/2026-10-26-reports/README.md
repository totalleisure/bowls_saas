# Club administrator reports

## App

Membership Details → Reports is visible to Club administrators and App superusers. The server independently enforces the same access at load and export. Select a reporting date range, inspect Membership, Bookings or App Usage, and download a native Excel workbook. Export rechecks access and retrieves fresh data. Membership is paged completely and sorted by surname, forename and stable profile ID. Search only affects the displayed list, not the export.

The workbook includes surname, forename, email, mobile/home/office telephone, App role, active status, coach/captain-managed/login-enabled flags, record creation date, last sign-in, recorded logins, App visits, screen views, last App activity, bookings created, assigned fixtures and fixture responses.

“Member type” currently means App role (member/admin/captain/selector/guest). There is no subscription category field in the current database. Do not represent the App role as a Full/Social/Junior membership classification.

## Statistics and coverage

- Current membership totals include the selected Club only. No historical membership snapshots are inferred.
- Historical sign-in counts cannot be reconstructed: production `auth.audit_log_entries` had no retained rows. `auth.users.last_sign_in_at` provides the latest sign-in, not a count or a full activity history.
- New successful sign-ins are counted by an `auth.users.last_sign_in_at` trigger, including older installed Apps. Token refresh does not increment this date. Counts are account-wide for members of the selected Club, not attributed to a particular Club or device. Account-security reauthentication can also be a sign-in.
- App visits count once per account/Club per App process, including restored sessions. Background/resume does not start a new visit. Reporting failures are ignored so they do not interrupt member workflows. Counts may understate offline/failed transmissions.
- Screen views cover Dashboard, Month, List, Day, Rinks, Membership and Reports. Route entry and return count; ordinary widget rebuilds do not. Other screens and dwell time are not measured. This requires the reporting-enabled App, so currently published binaries cannot send these events.
- Only the fixed screen names, platform, user, Club and server timestamp are recorded. Search terms, typed content, location and IP addresses are not collected by this feature.
- Booking groups use scheduled fixture dates. Bookings created uses creation timestamps. Cancelled and archived counts may overlap; current excludes both.
- Assigned fixtures counts distinct current selected team/rink assignments, excluding cancelled/archived fixtures. It is not attendance and cannot reconstruct removed past assignments. Fixture responses count currently retained RSVP records with response timestamps in the period.
- Dates filter in Europe/London, inclusive at both selected calendar days. The database uses an exclusive start-of-next-day upper bound.

## Database and security

Both databases contain identical definitions for `get_club_admin_report`, `record_club_usage`, `app_reporting.capture_login`, and the existing admin authorization helpers. The private `app_reporting` schema has no client grants; its tables use RLS with no client policies. Public RPC execution is revoked from anonymous users and PUBLIC. The read RPC checks current Club administrator membership or App superuser status. The write RPC allows only the caller's active Club memberships and a fixed event/screen/platform vocabulary. Clients cannot submit login events, user IDs or timestamps. Event IDs are unique to avoid retry double-counting.

The security advisor notices for RLS without policies on the two private tables and authenticated execution of the guarded security-definer RPCs are intentional. No unrelated legacy procedures or permissions were altered.

Migration mappings (production MCP assigns its own ledger timestamps):

| Amendment | Source / staging version | Production ledger version |
|---|---|---|
| club_admin_reports | 20261026013419 | 20261026014821 |
| harden_report_parameters | 20261026014258 | 20261026014834 |

These are the same applied amendments. Do not replay the canonical source migration in production solely because its timestamp differs. Recovery is in `recovery.sql`; it removes this reporting feature and its collected events only. Export any counters before deliberately recovering. Applied migration files have not been rewritten.

## Validation and release status

- Staging full Flutter suite: 357 passed, 4 skipped; additional usage navigation test passed afterward.
- Production full Flutter suite: 485 passed, 4 skipped. Targeted export, usage navigation, authentication and Month/Day navigation suite: 28 passed. Report source analysis: no issues.
- Database rollback tests pass on both projects: anonymous/member denial, Club isolation, invalid events, duplicate event IDs, login trigger, paging, membership totals and grants. Test writes were rolled back.
- Source comparison passes. Only the reviewed report integration and pinned existing archive dependency were promoted. Environment-specific entry points, keys, mailbox configuration and unrelated working changes remain intact.
- The production data workbook contains 333 member rows. Names and mobile telephone text were checked against the extract. Excel tables, frozen headers/names, valid package XML and formula results were checked; each worksheet was rendered for review.
- Source and database changes are prepared in both environments. No commit, push, App version bump, store build or store submission was made by this task. Existing released 1.6.0 (29) binaries do not contain the Reports screen.

Snapshot, 26 October 2026: 333 active LCPIBC membership records; 139 have a recorded sign-in; 114 latest sign-ins fall in 27 September–26 October; 8 have no email; 21 have no telephone. These are database records, not reconciled store downloads.
