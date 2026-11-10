# Remaining production source reconciliation

The release branch now includes the remaining reviewed CSV import, branded invitation/mailing renderer, registration and Graph inline-attachment changes, along with their supporting SQL source, recovery tools and tests. This closes the missing clubMessageHtml dependency in the committed email worker.

The live production import_members_csv (v31), register_member (v13), send-graph-email (v8) and process-email-queue (v22) bundles were retrieved and checked against the local runtime files. Their compared files match. The email renderer matches the worker v22 bundle; member_invitations v5 retains its older bundled renderer, whose invitation-only footer output is equivalent. This Git reconciliation does not redeploy either function or alter member accounts, fixtures, mailboxes or live database definitions.

The production mailbox_config.ts contains the public production notification address, not an authentication credential. Its staging counterpart deliberately keeps its own configuration. No production configuration was copied into staging. Existing database function comparisons and the green staging/production release tests remain applicable. Additional offline backend and Flutter tests are recorded under tmp/release-32 after reconciliation.

Generated root output/, outputs/ and tmp/ material is now ignored. Historical deployment manifests, pre-change worker JSON bundles and captured recovery snapshots remain local and outside this commit. Reviewed source, synthetic SQL fixtures, authored recovery scripts and release documentation are included. Credentials, key stores, local lib/secrets.dart, server environment settings and signing material remain excluded. The earlier production-source claim was too broad: this follow-up makes Git contain the required backend dependency and previously uncommitted operational source.

Mac workflow: fetch/pull codex/release-1.6.6-32, retain the existing ignored production configuration and signing settings, then run bash Docs/releases/1.6.6-32/build-ios-release.sh. Version remains 1.6.6+32. No new store build, upload or public release has been performed by this reconciliation.
