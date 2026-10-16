# Production source integration — 14 October 2026

## Subsequent authorised backend deployment

Wayne subsequently authorised the required database updates and admin-reset deployment. Corrective migration 20261014204847_production_fee_team_sheet_reminder_reconciliation was applied and registered in both projects. This section supersedes the earlier pending-backend status below; the source integration history remains recorded.

Production now has fixtures.match_fee_pence with its nonnegative constraint, create_fixture_with_match_fee, set_fixture_match_fee, repeat-fee inheritance, ordinary-member authorised team-sheet reads with fee metadata, and the existing reminder action trigger extended for pending published selections. The five shared routine definitions and their ACLs match staging exactly. Existing production create_fixture_with_setup_v2 was preserved.

Production fee/create/edit/repeat/zero/clear/concurrency/member/anonymous checks and published/pending reminder checks passed inside a savepoint rolled back before committing the schema migration. No test records or emails were retained. A separate rolled-back check verified ordinary-member PDF payload access and anonymous rejection. Production email settings and all three cron schedules/active states were compared before/after and are unchanged; production reply-processing routine hashes also remain unchanged.

admin-reset-password is deployed to production as ACTIVE version 1 with verify_jwt=true, using the reviewed production-local index.ts and handler.mjs. All 12 handler permission/error tests passed, and an empty unauthenticated request to the live endpoint returned 401. No live member password was reset during deployment verification. A real administrator reset remains a user workflow check.

The security advisor was run. The authenticated security-definer executable notice includes the deliberately exposed, guarded fee RPCs, alongside existing routines; their anonymous/public execution is revoked and member/anonymous denial tests passed. No extra grants or email-setting changes were made in response to the generic notice.

Recovery definitions and before/after evidence are retained in staging outputs/production-integration-20261014. Earlier historical migration aliases/raw applications are not blindly re-registered; the new corrective ledger entry records the reconciled schema state in both projects. Neither source checkout was committed or pushed, and no app was published. Production recovery-email template compatibility and optional written-reply activation remain separate checks; production Auth delivery configuration was not changed.

Local source integration only, authorised by Wayne. No commit, push, live database amendment, Edge deployment, version-policy update or store publication was performed in this task.

## Source result

49 reviewed files were integrated into C:\src\bowls_saas: shared Dart application changes, regression tests, Android saved-login bridge/dependencies, admin password-reset function source and unapplied migration source.

The previously modified Dashboard, Fixture Details and Manage Team files were reconciled using production HEAD as a base and both working copies. The conflicts were reviewed: reordered imports, superseded acceptance-panel placement, the new fee editor, a comment-only difference, reminder publication guards and read-only preselect visibility. The resulting three files match staging. Other previously modified and untracked production files were retained byte-for-byte.

Production main.dart and secrets.dart, Android application ID/signing/manifest, Apple app identity, Windows identity, existing production email workers and their mailbox/project settings were preserved. No staging credentials or staging startup/session storage were copied. The production Android build file received only the two androidx.credentials dependencies required by SavedLoginBridge; its signing configuration is intact. There was no production supabase/config.toml, and none was introduced.

The existing production reply worker was retained deliberately: staging's worker is locked to the staging project/mailbox and contains pilot/synthetic handling. It must not overwrite production. The staging Auth email hook and its mailbox configuration were likewise not copied or enabled in production. These are environment-specific integrations, not omitted shared Flutter features. Username/profile-photo source remains disabled by its existing feature flags.

Before-state files, merged candidates, applied file plan and SHA256 settings checks are retained under staging outputs/production-integration-20261014. Unrelated production file changes: none. Protected settings checks: passed.

## Verification

- Windows debug build succeeded: build/windows/x64/runner/Debug/bowls_saas.exe. The app was not launched against live data by the agent.
- 43 focused Flutter tests passed: Open fixture rinks, auth navigation/offline preservation, Android/Apple autofill simulation, fee parsing/dialog, PDF formats/draft warning, repeat dates, read-only empty team and section refresh.
- Complete production Flutter suite: 364 passed, four opt-in live tests skipped, eight failed. This is not a fully green release suite. Production retains older nested tests not present in the staging root suite.
- Compare-AppSources.ps1 was run after integration. Its sole reported difference is features/auth/staging_session_storage.dart, deliberately excluded from production because it contains staging session/enrollment keys. All other shared Dart files match.

Full-suite failures to reconcile before release:

1. guest_member_visibility_test: literal source check expects an older Guest-query expression in an unchanged members_screen.dart.
2. member_optional_fields_test: test cannot find its expected ListView descendant while scrolling the member form.
3. team_sheet_screen_test: its test fixture omits the now-required playersPerRink argument; the application builds successfully.
4. app_version_policy_upgrade_path_test: expects old tester version 1.4.1+17; current version was deliberately preserved.
5. fixture_details_communications_diagnostics_test: older literal source expectation.
6–7. member_opponent_email_action_test: two canonical SQL/migration text comparisons fail.
8. team_sheet_phase_two_routes_test: reads send-graph-email/index.ts for attachment mapping, but the retained production implementation delegates to handler.ts.

Logs: outputs/production-integration-20261014/flutter-test.log, targeted-tests.log and windows-build.log. These failures have not been silently disabled or rewritten merely to achieve a green suite.

## Required live database changes

Fresh function definitions and ACLs were compared across both live projects. No live SQL mutation was made in this task.

1. Match fee migration 20261013161440_add_fixture_match_fee.sql:
   - Add nullable fixtures.match_fee_pence integer and its nonnegative constraint. Existing records remain NULL; zero represents a free match.
   - Add create_fixture_with_match_fee, delegating atomically to the existing create_fixture_with_setup_v2.
   - Add set_fixture_match_fee with existing manager/creator authorisation and stale-value checking.
   - Amend create_repeated_fixture_from_source to inherit the fee, preserving the live predecessor definition.
   - The integrated Create Fixture screen calls the new wrapper even when no fee is entered. This migration is therefore required before testing creation, not only before fee tests.
2. Member team-sheet access migration 20261012190000_allow_member_team_sheet_read.sql:
   - Amend get_authorized_team_sheet_data to support active ordinary members' read-only team/PDF access while retaining manager capabilities and access restrictions.
3. Team-sheet fee migration 20261013163447_team_sheet_match_fee.sql:
   - After the fee column and member-access amendment, add match_fee_pence to the authorised team-sheet payload.
4. Actionable admin reminder migration 20261014194318_actionable_admin_selection_reminders.sql:
   - Extend the existing prepare_team_selection_email_action trigger to acceptance_reminder.
   - Preserve the existing v2 response-token, Accept/Decline rendering and receipt processing. Only pending selected/positioned recipients on published non-cancelled teams qualify.

The reminder migration's captured definition must be checked against production immediately before application. Do not blindly replace a subsequently amended live definition. Recovery definitions and rollback tests should accompany deployment.

## Already installed — no new schema required for local rink tests

Open-fixture rink editing and selection guards are already installed in production and match staging. set_open_fixture_rinks_required MD5: a6c762fe4f72076615887a5b18be834e. Use the existing Open fixture workflow for local live-data testing.

The admin RSVP Not Available override is already installed in both projects. Public wrapper MD5: d327f64492903182abf168c53b63b886. Its migration must not be reapplied as a new installation merely because its ledger is incomplete.

Mailing-list attachment support, written-reply captain-review routines and the established selection response protocol are already installed. Activation/configuration and end-to-end checks remain separate from schema installation.

## Backend and Auth requirements (not SQL schema changes)

- Deploy admin-reset-password to production with JWT verification and its existing server-side admin/member checks before using Membership's new password reset against live Auth. Its source is now present locally; it was not deployed. This uses the production project's runtime service credentials, never copied staging secrets.
- Confirm production password-recovery emails provide the code expected by the three-stage recovery screen and test recovery/resume against production Auth. Preserve production's existing delivery service. Do not copy staging's Graph hook, mailbox or testing email limits; adapt templates/hook only if inspection shows it is necessary.
- Production receipt processing must continue to use bowls@totalleisure.com and the production project. Existing explicit Accept/Decline processing already supports the normal production route; staging's automatic test-member sender lookup is not a production mailbox change.
- Written-reply/captain-review email activation needs a separate production settings decision and testing. The settings row was absent in the earlier production review. The shared claim_written_selection_reply SQL still uses configured reminder_recipients; staging's latest automatic membership lookup governs the outer worker and explicit commands, but does not itself remove that inner written-reply restriction. Reconcile this before promising automatic written-reply handling for every newly added account. Do not broaden production settings incidentally.

## Optional disabled prototypes — not required for this release

20261008000714_optional_account_username.sql and 20261008001047_optional_profile_photos.sql were copied as source/history only. Username/private-table/login-function deployment and profile-photo storage policies are not installed in either live project. Keep ACCOUNT_USERNAME_ENABLED and PROFILE_PHOTOS_ENABLED false unless separately approved and completed. Biometric Quick Unlock was removed; no biometric database work is required.

## Migration history and environment exclusions

Reconcile existing ledger aliases and raw-SQL applications before any migration rollout. Staging member team-sheet read is registered under 20261012214216, whereas the source file is 20261012190000. Match-fee, team-sheet fee, RSVP override and the latest admin reminder amendment were applied directly in staging and need ledger reconciliation; the RSVP override was also applied directly in production. Existing migration histories differ. Do not use blanket supabase db push or rewrite already-applied migrations.

The other live function differences are get_email_responses_cron_status, run_email_responses_now and set_email_responses_cron_enabled. Their production/staging job names, endpoint URLs and vault authentication settings are intentional and must remain separate.

Local production launch after closing an older running production debug instance:

```powershell
cd C:\src\bowls_saas
flutter run -d windows
```

Changes saved in this app affect the live database. No new installed app/store release has been produced. Source integration is complete for local testing; backend migration/deployment and the full release verification remain outstanding.
