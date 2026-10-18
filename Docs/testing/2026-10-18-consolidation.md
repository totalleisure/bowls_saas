# Final-test consolidation — 18 October 2026

## Included changes
- Selected-player cards keep the actions menu on the right at phone widths and enlarged text sizes.
- Published Fixture Type cards offer Manage Team to managers and View Team to other eligible members.
- PDF fallback arrival guidance is 30 minutes. Explicit arrival, meeting, reporting or check-in wording in Special Instructions suppresses it. This is a wording heuristic, not a time parser; review unusual wording in the PDF.
- When a declined player loses their position during published-team editing, they leave the selected and available pools. The decline record remains. Other selected players without positions are resolved together with Reserves / Remove / Cancel before the existing final confirmation. Available unpicked members return to the available pool; accepted teammates retain their response.
- Administrators can enable login for active captain-managed members through Member Edit > Enable app login. A unique email is required. The existing member profile ID, membership and dependent history are retained. Account linking uses trusted server metadata and an atomic Auth trigger. Existing logins cannot be merged or overwritten.

## Verification
- Staging full Flutter suite: 285 passed, 4 skipped; new member dialog tests: 2 passed.
- Production full Flutter suite: 414 passed, 4 skipped (includes its additional existing tests).
- New endpoint tests: 8 passed (permissions, duplicate account, recovery email and failure handling).
- Transactional database checks passed in staging before deployment and against both deployed databases. Synthetic accounts and memberships were rolled back; no real email was sent by these checks.
- Tested successful conversion with retained profile/membership; normal signup; rejection of user-metadata spoofing, unauthorized conversion and already-linked targets.
- Both live handle_new_user definitions match: MD5 9f7d36fb0d2b510667d369cdb4aa04d7.
- Both deployed enable-member-login endpoints reject unsigned requests with HTTP 401 and verify signed callers and active administrator permissions themselves.
- Shared Dart source comparison passed; environment entry points/settings and unrelated local files were preserved.

## Deployment and manual follow-up
The new migration 20261018112929 and enable-member-login function are deployed in staging and production. No store release has been made. Existing running desktop applications need restarting/rebuilding to load source changes.

Final acceptance testing remains paused. Check the compact cards and team shortcut, the three unassigned-player choices, and PDF arrival text in staging. Also test the member email setup end to end with a test member: use Forgotten password to request a fresh code and choose a password, then confirm their existing membership and selections remain. The initial setup email is not proof of delivery; failures are reported without undoing a completed account conversion.

## Existing release-review items
Security advisors still identify the pre-existing public.debug_login_users security-definer view, an extension in public, and broad executable security-definer functions; production also flags disabled leaked-password protection. These were not introduced or altered by this consolidation. Review before provisioning:
https://supabase.com/docs/guides/database/database-linter?lint=0010_security_definer_view
