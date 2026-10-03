# Release 1.5.5 (26) — source integration

Production source: C:/src/bowls_saas. Staging application and Edge Function
changes integrated; production startup, client configuration, platform
identities and signing settings retained. Windows installer defaults updated.
The 1.5.4 venue correction is retained. Staging working directory is unchanged.

Validation: 66 focused Flutter tests passed. Offline dependency resolution
passed. App analysis has no errors but retains warnings and information notices.
Platform packages have not been built or submitted by this integration.

## Database deployment is separate

The database-review/staging-migrations directory is reference material, NOT an
executable production migration plan. It contains staging-specific URLs, vault
names, historical changes and synthetic-test restrictions. Reconcile against
production before creating the deployment migration. Existing production
supabase/migrations files were preserved. No database or Edge Function was
deployed, and no minimum-version policy was changed.

## Git status

Git metadata writes are blocked by Windows permissions in this session, even
after a filesystem access grant. Branch creation/merge/commit did NOT happen.
The current branch remains release/production-preaudit-timeout; integrated
files are uncommitted. Reconcile the release/1.5.5 branch with
hotfix/away-venue-1.5.4 before sharing the source to the Mac or creating a tag.
The pre-integration working files and patch are backed up in the Codex workspace
under outputs/production-integration-1.5.5. Do not reset this working tree.
