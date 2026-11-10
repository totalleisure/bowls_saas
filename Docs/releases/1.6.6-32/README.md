# Total Leisure Bowls 1.6.6 (32)

Release candidate prepared on 10 November 2026. Both pubspec.yaml files specify **1.6.6+32**. The user's confirmed public baseline is **1.6.5 (30)**. Internal TestFlight 1.6.6 (31) is unchanged; this candidate needs a new Apple archive and upload. The Git delivery branch is **codex/release-1.6.6-32** in totalleisure/bowls_saas. Use the existing production Mac checkout and its local production configuration.

## Changes since the public release

Apple's GB lookup API reported public version **1.6.5**, released 3 November 2026 at 16:56 UTC, when checked on 10 November. The summary below covers the work documented after that release. An exact archived source manifest for the published binary is unavailable, so this is a dated implementation summary rather than a binary comparison. Earlier reporting, branded-mailing and competition-setup work is not advertised as newly introduced here.

- **Quicker member rink booking:** choose the member fixture type, browse the real green's rink availability, select a booking and continue into Fixture Details. Compact phone layout, date picker/chevrons, Fit Day/Compact/Detailed modes and a persistent Book rink action. Admins can enter the same member booking flow without first choosing a rink. Normal admin fixture creation retains its separate process.
- **Fixture-linked shared scorecards:** fixture/player/condition prefills, one designated scorer/device, local save and recovery, background upload, read-only participant review and agreement from both sides. Correction requests can reopen an unconfirmed card for fresh agreement. Competition submission and administrator confirmation retain their separate stages and result guards. Confirmed cards are locked. Includes 100 Up controls and timer refinements.
- **Clearer personal competition lists:** unbooked matches appear under Competitions to be Arranged. A booked match appears for all participants under Your upcoming competition fixtures with response status. Pending matches also remain in the acceptance section; accepted competition fixtures are suppressed from the general accepted list.
- **Calendar attachments and lifecycle emails:** selection emails offer Add to Calendar. Date/time changes and cancellations send matching-identity calendar messages, including in-place competition changes and replacement reschedules. Older/stale queued updates are suppressed and deleted fixtures retain cancellation snapshots. Calendar applications may require opening/confirming the attachment; old imports may need manual replacement. Device interoperability is still an acceptance check, not a promise of silent updates.
- **Admin account assistance:** change another member's login email while retaining their account/password; resend confirmation for an unconfirmed linked account; existing password reset remains. Server permissions, address checks and resend throttling are enforced. The three actions now have compact equal sizing and equal gaps.
- **Fixture clarity and maintenance:** distinct Fixture Labels on both rink views; checked label/dress saves and draft preservation; date/time and duration improvements; appropriate member visibility of players/opponents/markers; guarded captain deletion. Member Internal Reschedule uses the existing date/time edit or linked competition booking-management route, with no cancelled predecessor from the ordinary in-place edit. Delete remains available under its existing guards; Cancel remains suppressed.

## Verification and deployment

| Item | Status |
|---|---|
| Shared Dart source | Aligned; Compare-AppSources.ps1 passes |
| Staging Flutter suite | 557 passed; 4 opt-in live tests skipped |
| Production Flutter suite | 684 passed; 4 opt-in live tests skipped |
| Staging offline backend suite | 299 passed |
| Production offline backend suite | 296 passed with WORKER_ENV=production |
| Live database functions | 402 in each project; shared behaviour aligned; 3 intentional environment-specific receipt functions; 2 whitespace-only differences |
| Production Windows build | Built successfully; executable reports 1.6.6+32 |
| Apple IPA/archive/TestFlight | Not built or uploaded on this Windows host |

Different suite counts reflect retained production-only historical tests and staging-only experimental/auth-hook tests. All suites above finished without failures. Logs, source differences and function hashes are retained in C:/src/bowls_staging/tmp/release-32. Older test harnesses required the native calendar helper/URL dependency, production worker mode and missing offline migration fixtures; these were corrected/restored without applying historical SQL to either live project.

## Remaining release work

Use the iOS checklist and build script on the signing Mac. Confirm the compact admin buttons on device; test quick booking, shared scorecard recovery/agreement/correction and calendar add/update/cancel on a fresh event. No claim is made that the prior internal build 31 tested the final build 32 code. Upload build 32 to internal TestFlight, complete acceptance, then select that same accepted build for App Store review. No member communication or Patricia resend is part of release preparation.

Username login, profile-photo uploads and biometric Quick Unlock remain deferred and disabled. Do not enable their flags or treat their staging-only endpoints/native work as part of this release. See integration-audit.md for deliberate platform, credential, mailbox and historical-source differences.
