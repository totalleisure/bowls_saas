param([string]$Production = 'C:\src\bowls_saas', [string]$Staging = 'C:\src\bowls_staging')
$ErrorActionPreference = 'Stop'
$allowed = @('main.dart', 'secrets.dart', 'staging_main.dart')
$prodRoot = Join-Path $Production 'lib'
$stageRoot = Join-Path $Staging 'lib'
$paths = @(@(Get-ChildItem -LiteralPath $prodRoot -Recurse -Filter *.dart | ForEach-Object { $_.FullName.Substring($prodRoot.Length + 1) }) + @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Filter *.dart | ForEach-Object { $_.FullName.Substring($stageRoot.Length + 1) })) | Sort-Object -Unique
$differences = @()
foreach ($relative in $paths) {
 if ($relative -in $allowed) { continue }
 $p = Join-Path $prodRoot $relative
 $s = Join-Path $stageRoot $relative
 if (!(Test-Path -LiteralPath $p) -or !(Test-Path -LiteralPath $s)) { $differences += $relative; continue }
 if ([IO.File]::ReadAllText($p).Replace("`r", '') -cne [IO.File]::ReadAllText($s).Replace("`r", '')) { $differences += $relative }
}
if ($differences.Count) { $differences; throw 'Shared app source differs. Review before promotion.' }
Write-Output 'PASS: shared Dart sources match. Environment entry points and secrets are excluded and must be reviewed separately.'
