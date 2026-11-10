$ErrorActionPreference = 'Stop'
$repo = 'C:/src/bowls_saas'
function Invoke-ReleaseGit {
    & git -c "safe.directory=$repo" -C $repo @args
    if ($LASTEXITCODE -ne 0) { throw "Git failed. Stopping; inspect the message above." }
}
if ((Invoke-ReleaseGit branch --show-current) -ne 'release/1.5.5') { throw 'Unexpected branch. Stop and review before publishing.' }
$staged = @(Invoke-ReleaseGit diff --cached --name-only)
if ($staged.Count -gt 0) { throw 'There are already staged changes. Review them before running this script.' }
& "$repo/scripts/Compare-AppSources.ps1"
if (!(Select-String -Path "$repo/pubspec.yaml" -Pattern '^version: 1\.5\.6\+27$' -Quiet)) { throw 'Expected version 1.5.6+27' }
$files = @(
 'pubspec.yaml', 'AGENTS.md', 'scripts/Compare-AppSources.ps1',
 'lib/features/clubs/club_dashboard_screen.dart',
 'lib/features/communications/member_options_menu.dart',
 'lib/features/diary/rinks_day_view.dart',
 'lib/features/fixtures/create_fixture_page.dart',
 'lib/features/fixtures/fixture_details_page.dart',
 'test/peak_interval_usage_test.dart',
 'supabase/migrations/20261004023022_fix_fixture_creator_lifecycle.sql',
 'supabase/migrations/20261004203050_restore_production_amendments.sql',
 'test/sql/fixture_creator_lifecycle.test.mjs',
 'test/sql/restore_production_amendments.test.mjs',
 'test/sql/amendment-fixtures/before.json',
 'test/sql/amendment-fixtures/recovery.sql',
 'docs/releases/1.5.5/database-deployment/20261003110620_release_155_production_backend.sql'
)
Invoke-ReleaseGit add -- @files
Invoke-ReleaseGit diff --cached --stat
Invoke-ReleaseGit commit -m 'Prepare 1.5.6 build 27 with restored production fixes'
Invoke-ReleaseGit push origin HEAD:release/1.5.5
Invoke-ReleaseGit log -1 --oneline
Invoke-ReleaseGit status --short
