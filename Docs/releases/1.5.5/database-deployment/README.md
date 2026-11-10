# Production database upgrade for 1.5.5 (26)

Status: prepared and locally rehearsed; NOT applied to production or staging.
Source comparison refreshed 3 October 2026. Production: xfjelvvfoguzukgvxchh.

## Scope

The timestamped SQL file is the proposed forward migration. It creates five
new tables (audit journal, private import runs and three written-reply tables),
adds three nullable fixture fields and the audit identity sequence, introduces
22 functions including the private notification permission predicate, and
updates definitions and/or execution permissions for 96 existing functions.
It also adds audit/validation triggers, indexes and tested access policies.

No existing table or column is dropped. Existing rows, UUID defaults, version
policy values, mailbox cursor and production cron schedules/states are retained.
New written-reply settings remain empty, which keeps the feature disabled.
The production-only index is retained. No staging data or test recipients are
copied. Queue controls use production job names and the existing production
vault secret name; no secret value is embedded in the scripts.

## Evidence and limits

- Both forward and recovery scripts parse successfully.
- Forward migration installs in an isolated PGlite reconstruction of production.
- Synthetic authenticated-member profile reads, notification reads/read-state
  updates, saved filters and push-token registration pass after the migration.
- Audit entries are created; recovery preserves audit and member records.
- Recovery restores all 301 original production function definitions exactly.
- 89 server/auth/import/invitation tests passed. Another 7 invitation claim
  tests passed using the identical staging test file and its reference fixtures.
  The production checkout currently lacks those reference SQL fixtures; this is
  a test-harness portability issue to tidy separately, not a database failure.
- Production email worker: 88 local tests passed using mocked database/Graph,
  including ordinary replies with reminder settings disabled or absent, sender
  validation delegation, duplicates, mailbox restriction and rejected test modes.
- Fresh read-only comparison found no drift in the changed production functions.

This is not a full Supabase clone or device test: real member records, external
authentication, email delivery, storage, scheduled execution and exclusion
constraints were not exercised. The isolated environment blocks outbound HTTP.

## Deployment order

1. Verify a recent successful production backup and the restore procedure in
   Supabase Database / Backups. Definition snapshots are not a data backup.
2. Refresh the preflight against production immediately before deployment.
   Confirm project identity, expected schema, callable old signatures and active
   email/notification jobs. The migration checks original function definitions
   and grants and aborts on drift; it also fails if new tables already exist.
3. Check the agreed transition restrictions: no force deletion from either app,
   no external-player entries in production while older apps can edit those
   teams; temporary filter preference inconsistencies accepted.
4. Execute ONLY the timestamped reviewed SQL as one transaction. Do not run
   `supabase db push` on the historical staging migration collection. It uses a
   five-second lock timeout and a 90-second per-statement timeout; if blocked,
   roll back and investigate rather than retrying indefinitely.
   The deployment gate requires a session setting of
   `SET bowls.release_155_approved = 'yes'` after these checks are complete.
   No deployment runner or schedule has been set up to do this automatically.
5. Verify definitions, new structures, permissions and unchanged data counts,
   version-policy values, cron state and inbox cursor. Recheck Supabase advisors.
6. Review/deploy the five other server functions listed in edge-function-plan.json
   with their existing JWT settings; keep production secrets unchanged. Deploy
   import_members_csv only after audit_member_import exists.
7. The adapted process-email-responses source requires production project
   xfjelvvfoguzukgvxchh and bowls@totalleisure.com. Deploy it only AFTER the SQL
   migration, preserving verify_jwt=true and existing production secrets/cursor.
   Run its read-only {"mode":"verify"} probe with server authorization, then
   check scheduled ordinary replies. Staging test-send modes are rejected.
   Ordinary Accept/Decline replies work with written-reminder settings disabled
   or no settings row; the response RPC still validates credentials and sender.
   Written-reply reminders remain disabled pending separate activation. This
   server change does not require an Apple app rebuild. The existing deployed
   worker remains unchanged until this rollout step is executed.
8. Check the current live app: login, fixture/diary/member reads, availability,
   team acceptance/decline, notification read-state and existing email replies.
   Then check the uploaded 1.5.5 with the same production backend. Keep release
   manual and the minimum app versions unchanged during store review.

## Recovery

A SQL error before COMMIT rolls the transaction back. After a successful commit,
use recovery.sql only after deciding to return existing apps to the earlier
behaviour. Restore previous Edge Function versions first if new workers depend
on the new function contracts. Saved sources and JWT metadata are in the Codex
workspace under outputs/database-1.5.5/edge-before and edge-recovery-source.

The recovery SQL removes newly added behaviour/capture triggers on existing
tables, restores prior functions, policies, grants and RLS settings, disables
written replies, and revokes client execution of new functions. It deliberately
keeps new fields, new tables and audit records. It does not undo messages already
sent or member actions completed after deployment. A full database restore is
an incident-recovery option with a downtime/data-loss window, not a routine
rollback. The recovery script has the same explicit deployment gate.

## Review files

- Timestamped SQL: proposed forward migration, outside the automatic migration queue.
- recovery.sql: restores earlier behaviour without dropping captured data.
- manifest.json: scope, validation, limitations and hashes.
- edge-function-plan.json: deployed version/JWT metadata and server rollout order.

No database, server-function, minimum-version or store-release changes were made
while preparing this package. The package is uncommitted review material in the
production source directory.
