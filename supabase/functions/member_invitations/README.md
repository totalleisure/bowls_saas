# Member import and invitation review

Release deployed to Supabase on 12 September 2026. The migration, member_invitations v1 and import_members_csv v28 are live. Both approved Lewisham guides are uploaded and configured. No membership import or email send was performed during release. The updated web build is available locally; public app publishing is separate.

## Behaviour

The membership Import action asks whether to import, the starting status for new
memberships, and whether to prepare invitations. Existing roles/statuses remain
unchanged; new memberships receive the Member role. Selecting No to import only
uses the CSV to identify existing members. Invitations are a separate reviewed
action. The import itself never sends email.

The review allows recipient selection, per-member email previews and opening both
approved guides. Import errors, missing/ambiguous accounts, changed login emails,
inactive memberships and duplicate CSV addresses are listed separately.
The invitation uses the current password/Forgotten password wording; no CSV
password is included. It uses the confirmed Apple App Store link.

Previously accepted invitations are skipped unless Resend invitations is selected.
Rejected sends can be retried by preparing a new review without re-importing.
Sending happens one member per request, with a durable claim and immutable reviewed
HTML/recipient/document paths. Multiple reviews cannot race to send the same
member. Reviews expire after 24 hours. The review's creator must still be an active
club admin or platform superuser at send time. Membership and email are rechecked.

Graph 202 means accepted, not delivered; copies go to the configured mailbox's Sent
Items. Timeouts, 5xx and ambiguous responses remain unknown (or sending if the
function terminated). They are deliberately blocked from automatic resend. An
operator must check Sent Items before resolving such a record; there is no UI
override that could silently send a duplicate. Failed/pending attempts and prior
superseded invitations remain in the audit table.

## Release and first-test checklist

1. Review/apply `20260912005337_member_invitations.sql`. It creates private invitation
   tracking, the private guide bucket and the service-only atomic claim function.
   No existing member rows are changed by this migration.
2. Deploy `member_invitations` with gateway JWT verification disabled, as with the
   importer: the function validates the bearer token with Auth and verifies club
   admin access before every action. Include `_shared/member_csv.ts` and `email.ts`.
   The importer now imports the shared parser too; include it if redeploying that
   function. Its import behaviour is otherwise unchanged.
3. Verify server secrets `MS_TENANT_ID`, `MS_CLIENT_ID`, `MS_CLIENT_SECRET` and
   `MS_MAILBOX`, using the same mail setup as `send-graph-email`. The new function
   calls Graph directly after authorization, rather than exposing the generic mail
   function to clients. Confirm the intended From mailbox before the first send.
4. Publish the updated Flutter app. Do not enable the new client flow before the
   migration and function are available.
5. In invitation review, Add guide for each of the two approved documents:
   `Bowls_Club_App_Member_Introduction II.pdf` and
   `Bowls_Club_App_Android_Samsung_App_Installation_Guide.pdf`.
   This stores central approved copies. Future admin replacements create immutable
   versions; old versions remain available to existing reviews. PDFs must be under
   1.5 MB each and 2.8 MB combined. Current supplied guides fit these limits.
6. With explicit send approval, select one or two active committee members, open
   both PDFs, check the personalised preview, then send. Confirm received messages
   and attachments, prepare another review to verify duplicate skipping, then
   send to the remaining eligible committee members. Historical mail sent outside
   this feature is not automatically known to the invitation tracker.

The screen supports up to 250 CSV records per invitation review. This initial
version processes sends while the review screen is open; it is not an unattended
background mailing job. Closing the app does not automatically send remaining
members. A new review safely identifies those still eligible.

## Local validation

Run from the repository root with Node 24+, Deno and Flutter installed:

```text
node --test supabase/functions/import_members_csv/import_members_csv.test.mjs
node --test supabase/functions/member_invitations/member_invitations.test.mjs
deno check --config supabase/functions/member_invitations/deno.json supabase/functions/member_invitations/index.ts
flutter test test/features/members
flutter analyze lib/features/members/member_import_options_dialog.dart lib/features/members/member_invitation_screen.dart lib/features/members/members_screen.dart
git diff --check
```

The database claim tests use a disposable PostgreSQL/PGlite database with minimal
fixtures matching inspected live column types. Install `@electric-sql/pglite@0.3.14`
locally, set `PGLITE_MODULE` to its `dist/index.js` file, then run:

```text
node --test supabase/functions/member_invitations/claim.test.mjs
```

These tests apply the real migration, exercise its privileges and claim behaviour,
and do not contact Supabase. Function tests mock Auth, Storage and Graph and never
send real mail. Live storage, mail credentials and inbox delivery still require
the approved end-to-end test above.

