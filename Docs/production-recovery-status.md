# Production working environment — 25 September 2026

## Current checkout

Folder: `C:\src\bowls_saas`

Active branch: `release/production-preaudit-timeout`

Base commit: `7fb06ad3641e52e9eb3e6d3d54ca14c943fd1447` (production 1.5.2 build 23).

The application was restored to that release, then the isolated rink hourly-count correction was added (see Rink-capacity-fix-notes.md). The newer audit references, including fixtures.created_by_user_id and fixture_deletion_preview, are absent from lib. The existing uncommitted pubspec version 1.5.3+24 and Windows installer/documentation files were retained. That version label does not mean new client functionality was added.

## Fixture timeout fix located

The saved report at `C:\Users\Wayne Sayers\Documents\Codex\2026-09-24\supabase-app-asdk-app-69d3e5ee6a708191baa733f7b8931995-2\outputs\fixture-rinks-change-report.md` records production migration `optimize_fixture_rinks_member_lookup` applied to project `xfjelvvfoguzukgvxchh` on 24 September.

It changes only the fixture_rinks SELECT policy membership lookup to use `(SELECT public.my_member_profile_id())`. Its report explicitly states no Flutter changes or pagination. The full reconstructed authenticated fixture query took 184.534 ms execution and 36.748 ms planning after the change, versus prior timeouts. This is historical database test evidence, not a new UI test or a concurrent-user capacity guarantee.

Therefore this pre-audit client can use the already-deployed backend fix; no timeout client patch needs cherry-picking from that work. The Store 1.5.2 package can also benefit from the same backend fix. Current production state was not independently queried in this recovery: the connected Supabase account previously denied production access. No database changes were made here.

## Preservation and verification

- Audit commits remain on main at d8a1a029101ea455d7a05ff3ed96bc8b353cdd75 and on preservation/audit-before-production-hotfix.
- Complete Git bundle and copies of the pre-change uncommitted patch, pubspec and installer files are in this task's work/production-before-preaudit directory. Git bundle verification passed.
- Staging checkout and its uncommitted work were untouched. Existing stashes were untouched.
- Windows debug build from C:\src\bowls_saas passed.
- lib now includes the isolated rink hourly-count correction on the pre-audit base. Wayne restarted Flutter and supplied a screenshot confirming corrected live-data header counts and the R5 booking.
- No reset or source deletion was performed. Wayne applied the SQL correction to production; the local correction is being committed without the audit files. No push has been performed.

## Next use

Stop any already-running Flutter debug session, then run `flutter run -d windows` from C:\src\bowls_saas. A full restart ensures the app runs the restored sources rather than an existing audit-version process.

Remain on release/production-preaudit-timeout for production work. Switching to main restores audit-development code and its newer database requirements.

The other production error was diagnosed as summing successive bookings rather than peak simultaneous rink demand. The local app header has been corrected and tested; Wayne confirmed applying the SQL correction to production and verified the restarted Flutter display. The rollback remains available. See Rink-capacity-fix-notes.md. Do not package a new release solely to deploy the recorded database-only timeout fix. Store review, Store-installed MSIX testing and removing the installed app's MSIX name suffix remain separate outstanding items.
