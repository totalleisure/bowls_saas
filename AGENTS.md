# Staging and production changes

User requirement: keep staging and production aligned, including emergency production fixes.

- Develop and verify shared changes in staging first, then apply the same reviewed amendment to production.
- An emergency production fix must also reach staging in the same task. If blocked, report the exact outstanding difference; do not describe the environments as synchronized.
- Preserve environment-specific entry points, project IDs, credentials, mailbox settings and deployment configuration. Never copy production secrets into staging or the reverse.
- Before promoting staging, compare against production-only amendments. Git ancestry and passing helper tests alone do not prove that fixes survived integration.
- Compare live database function definitions as well as source references. Use new corrective migrations; do not rewrite an already-applied migration. Keep recovery definitions and verify deployed results in both projects.
- Run scripts/Compare-AppSources.ps1 before release and inspect every unexplained difference. Test call sites and user workflows as well as isolated helpers.
- Preserve existing unrelated working changes; do not stage or commit them incidentally. State source, database and store deployment status separately.
