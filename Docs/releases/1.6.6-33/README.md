# Total Leisure Bowls 1.6.6 (33) — sub-committee TestFlight

Production iPhone candidate prepared 12 November 2026. Version remains 1.6.6; build increases to 33. Git branch: `codex/release-1.6.6-33`. This builds from the production `lib/main.dart` entry point and preserves the existing Mac production secrets and signing configuration.

Changes since build 32:

- Admin competition match booking on behalf of the players, using the existing fixture process and booking/reschedule communications to both entries.
- Admin addition of a preliminary match to an eligible published draw, with guarded amendment handling.
- Individual competition handicaps, calculated lower-team starting allowances, rule editing and player/total labels on draw, entry, match, booking and PDF screens.
- Both parties can sign a shared scorecard on the scorer's device. Separate-account agreement remains available. Corrections invalidate signatures; competition submission and Secretary confirmation remain separate.
- Completed competition matches no longer appear as upcoming competition fixtures or resurface under accepted fixtures on the Dashboard.
- Backend next-round emails include individual handicaps, combined totals and calculated starting scores. This backend content is already deployed and does not depend on installing build 33.

Use the build script and TestFlight notes in this directory. No controls have been disabled for committee testing. This is the production App: real publication, booking and result actions use production records and normal communications. Staging retains its test-recipient restriction.

Database migrations and relevant workers were deployed and verified during their respective amendments. No migration needs to be applied from the Mac. Do not run a blanket database push. App Store/TestFlight upload and iPhone acceptance must be completed on the signing Mac; Windows cannot produce a signed iOS archive.

Release validation and final Git commit are recorded after checks. No public App Store submission is part of this task.

Validation: production Flutter suite 703 passed, 4 opt-in tests skipped; staging focused release suite 24 passed; email regression suite 19 passed in each source tree. Shared Dart source comparison and git diff --check passed. The iOS archive/upload remain to be performed on the Mac.
