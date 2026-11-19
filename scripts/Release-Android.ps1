<# One command: verified production build, then Play upload. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ReleaseNotesPath,
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$StagingRoot = 'C:\src\bowls_staging',
    [string]$FlutterExecutable = 'flutter',
    [switch]$SubmitForReview
)
$ErrorActionPreference = 'Stop'
$ReleaseNotesPath = (Resolve-Path -LiteralPath $ReleaseNotesPath).Path
$text = (Get-Content -LiteralPath $ReleaseNotesPath -Raw -Encoding UTF8).Trim()
if (!$text -or $text.Length -gt 500 -or $text -match '</?en-') { throw 'Supply plain release notes, 1-500 characters, without language tags.' }
$built = @(& "$PSScriptRoot/Build-AndroidRelease.ps1" -ProjectRoot $ProjectRoot -StagingRoot $StagingRoot -FlutterExecutable $FlutterExecutable -PassThru | ForEach-Object {
    if ($_ -is [pscustomobject] -and $_.ManifestPath) { $_ }
    else { Write-Host $_ }
})
if ($built.Count -ne 1) { throw 'Build did not return one verified manifest. No upload attempted.' }
& "$PSScriptRoot/Publish-AndroidRelease.ps1" -ManifestPath $built[0].ManifestPath -ReleaseNotesPath $ReleaseNotesPath -SubmitForReview:$SubmitForReview
