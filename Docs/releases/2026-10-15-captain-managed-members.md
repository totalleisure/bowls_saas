# Captain-managed membership — 15 October 2026

Implemented in staging, tested, then applied to production. Administrators use Members > Add captain-managed member. Name and telephone are required; sex at birth is optional and feeds the existing match eligibility rules. No Auth account, email address or invitation is created. Existing captain pool and acceptance controls remain in use.

## Scope

- Explicit `is_captain_managed` profile flag and account-mode constraint. Existing profiles keep their account requirement; managed profiles require a telephone and cannot have an Auth link or email.
- Administrator/superuser creation RPC with an atomic profile/membership insert and duplicate protection. No new client-side INSERT policy.
- Private BEFORE INSERT recipient guards on notification_queue and email_queue skip only managed recipients. Existing publication, token, mail worker and invitation functions were not modified or redeployed.
- Member screens show telephone-only status and hide account actions. Manage Team shows the status and excludes these recipients from email reminders.

## Validation

- Eight Flutter form and directory tests passed.
- Staging and production transactional database tests passed: admin creation/editing, no Auth creation, directory and match eligibility, RSVP pool, complete mixed-team publication, normal-recipient notification and actionable email, suppression for managed recipients, admin and fixture-captain acceptance, duplicate/invalid-input rejection, ordinary-member and unauthenticated denial. All test data and queued messages rolled back, so no test email was sent.
- Both Windows debug builds succeeded. Targeted analysis found no compile errors; existing warnings remain in the member/team screens.
- Security advisors reported no finding for the new functions/schema. Unrelated existing project findings were not changed.
- Shared source comparison: only the existing staging-only `features/auth/staging_session_storage.dart` differs after promotion (plus the comparison script's intentional entry-point/secrets exclusions).

## Deployment and migration identities

Canonical source: `20261014235643_captain_managed_members.sql` (created with the CLI).
The MCP applied identical SQL under its generated ledger versions:

- Staging: `20261014235926_captain_managed_members`.
- Production: `20261015000441_captain_managed_members`.

These are the same applied amendment, verified by function hashes and constraint definitions. Do not reapply the canonical file through blanket db push; reconcile ledger aliases as part of the repository's existing migration-history reconciliation process.

Function body hashes in both databases:

- create_member: `0cdb4cbcd69a13dc9139e44453408b68`
- create_captain_managed_member: `4fc82bc658906f06fd2fdef1ac3f0994`
- skip_accountless_recipient: `a21378cd11ec64d76a7ac0f809b70331`

The existing publication and email-response functions retained their pre-change hashes. No email worker, Auth configuration, mailbox, store package or mobile release was deployed. The local Windows app is rebuilt; other installed clients need a later application release to display the new controls.

## Recovery

Keep existing managed members and their selections. Do not restore NOT NULL on user_id once managed members exist. The additive database change can remain while rolling the app back. Full schema reversal requires an explicit member migration plan; do not delete these people to reverse the feature.
