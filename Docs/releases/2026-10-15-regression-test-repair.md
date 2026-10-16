# Regression test repair — 15 October 2026

## Outcome
All eight recorded failures reproduced in production before editing. Corrections were implemented and verified in staging first, then copied to production.

- Staging full Flutter suite: 247 passed, 4 opt-in live tests skipped, 0 failures.
- Production full Flutter suite: 374 passed, 4 opt-in live tests skipped, 0 failures.
- Mocked Graph attachment-delivery test passed in both repositories; no messages sent.
- Counts differ because production retains additional historical tests.
- Application-source comparison reports only the intentional staging session-storage file (plus its normal environment exclusions).

## Corrections
1. Guest visibility source check follows the member-directory loader delegation. The existing HTTP-mocked directory test also verifies the Guest filter on requests.
2. Member optional-fields test scrolls to the Coach control without assuming a ListView parent; verifies Active/Coach toggles and rendering.
3. Team-sheet test supplies the required per-rink player count; failed-refresh removal of stale PDF/export controls remains tested.
4. Version test validates a release version/build above the historical build-17 baseline instead of requiring the obsolete exact version.
5. Communications diagnostics check includes Open fixtures alongside event and unauthorised exclusions, ignoring whitespace.
6. Historical reselection migration check tests reset and reconciliation invariants rather than equality with a later canonical definition.
7. Corrective migration comparison permits only the two subsequent Guest exclusions and updated error wording, explicitly requiring both exclusions.
8. Graph attachment test follows the actual index-to-handler route and retains attachment-field assertions.

## Historical SQL references
The seven production test files were previously absent from staging. Twelve historical SQL references are retained under test/fixtures/release_history in both checkouts, outside deployable migrations. release_source.dart reads actual repository files when present, otherwise these historical test references. These checks do not certify the current live database definition. No historical migration was rewritten or deployed.

## Scope and next step
Only tests, test reference data and documentation changed. No application behaviour, live database, mailbox, member or fixture data changed. No rebuild or store release is required for these test-only repairs. Changes remain uncommitted.

Ready to begin final manual testing, not a store-release sign-off. Real iPhone/Android credential-manager testing, recovery/admin-reset workflows, inbox delivery, platform packaging and final release checks remain.

Evidence logs in the current Codex workspace work directory: production-eight-baseline.log, eight-fixed-staging.log, full-staging.log, full-production-fixed.log. The intermediate focused staging log contains the indentation mismatch corrected before the passing full suite.

