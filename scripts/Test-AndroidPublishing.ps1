# Offline contract tests: no credentials, builds or Google requests.
$ErrorActionPreference = 'Stop'
$publisher = Join-Path $PSScriptRoot 'Publish-AndroidRelease.ps1'
$root = Join-Path (Split-Path $PSScriptRoot -Parent) ('tmp/play-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$cloud = Join-Path $root 'fake-cloud.ps1'
'$global:LASTEXITCODE=0; "fake-local-token"' | Set-Content -LiteralPath $cloud
$state = @{ cases=0; calls=@(); mode=""; hash=""; payload=$null }
function Assert($Condition, $Message) { if (!$Condition) { throw $Message } }
function Invoke-RestMethod {
    param($Method,$Uri,$Headers,$ContentType,$Body,$InFile,$TimeoutSec)
    $state.calls += "$Method $Uri"
    if ($Uri -like '*generateAccessToken') {
        Assert (($Body | ConvertFrom-Json).scope[0] -eq 'https://www.googleapis.com/auth/androidpublisher') 'Wrong scope'
        return @{accessToken='fake-publisher-token'}
    }
    if ($Method -eq 'Delete') { return }
    if ($Uri -match '/edits$') { return @{id='test-edit'} }
    if ($Uri -match '/tracks$') {
        $status = 'completed'; if ($state.mode -eq 'unfinished') { $status='draft' }
        return @{tracks=@(@{track='production';releases=@(@{name='old';status=$status;versionCodes=@('34')})})}
    }
    if ($Uri -match '/apks$') { return @{apks=@()} }
    if ($Uri -match '/bundles$') {
        if ($state.mode -eq 'duplicate') { return @{bundles=@(@{versionCode=35})} }
        return @{bundles=@(@{versionCode=34})}
    }
    if ($Uri -like '*uploadType=media') {
        Assert ($TimeoutSec -ge 120) 'Upload timeout too short'
        $returnedHash = $state.hash
        if ($state.mode -eq 'bad-upload') { $returnedHash='wrong' }
        return @{versionCode=35;sha256=$returnedHash}
    }
    if ($Method -eq 'Put') {
        $state.payload = [Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
        return $state.payload
    }
    if ($Uri -like '*:validate') { return @{} }
    if ($Uri -like '*:commit*') {
        Assert ($Uri -like '*changesInReviewBehavior=ERROR_IF_IN_REVIEW') 'Review guard missing'
        if ($state.mode -eq 'in-review') { throw 'Simulated changes already in review' }
        return @{id='test-edit'}
    }
    throw "Unexpected request $Method $Uri"
}
function Run-Case($Mode, [switch]$Submit, [switch]$Validate) {
    $state.mode=$Mode; $state.calls=@(); $state.payload=$null
    $dir=Join-Path $root $Mode
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $aab=Join-Path $dir 'release.aab'; 'test-bundle' | Set-Content -LiteralPath $aab
    $state.hash=(Get-FileHash $aab -Algorithm SHA256).Hash
    $manifest=Join-Path $dir 'manifest.json'
    @{version='1.6.9';build=35;artifact='release.aab';sha256=$state.hash;package='totalleisuresolutions.bowls';entry_point='lib/main.dart';tests='passed';signature='verified'} | ConvertTo-Json | Set-Content $manifest
    $notes=Join-Path $dir 'notes.txt'; 'Booking improvements.' | Set-Content -LiteralPath $notes
    if ($Mode -eq 'tampered') { 'changed' | Set-Content -LiteralPath $aab }
    if ($Mode -eq 'long-notes') { ('x'*501) | Set-Content -LiteralPath $notes }
    $failed=$false
    try { & $publisher -ManifestPath $manifest -ReleaseNotesPath $notes -CloudExecutable $cloud -SubmitForReview:$Submit -ValidateOnly:$Validate | Out-Null }
    catch { $failed=$true }
    $expectedFailure=$Mode -in @('duplicate','unfinished','bad-upload','in-review','tampered','long-notes')
    Assert ($failed -eq $expectedFailure) "Unexpected outcome for $Mode"
    if ($Validate -or $Mode -in @('tampered','long-notes')) { Assert ($state.calls.Count -eq 0) "$Mode made network requests" }
    if ($expectedFailure) {
        if ($Mode -ne 'in-review') { Assert (@($state.calls | Where-Object {$_ -like '*:commit*'}).Count -eq 0) "$Mode committed" }
        if ($Mode -in @('duplicate','unfinished','bad-upload','in-review')) { Assert ($state.calls[-1] -like 'Delete *') 'Failed edit not cleaned up' }
    } elseif (!$Validate) {
        Assert ($state.calls[-1] -like 'Post *:commit*') 'Commit missing'
        $receipt=Get-Content (Join-Path $dir 'play-production.json') -Raw | ConvertFrom-Json
        Assert ($receipt.state -eq 'committed') 'Receipt missing'
        if ($Submit) { Assert ($state.payload.releases.Count -eq 1 -and $state.payload.releases[0].status -eq 'completed') 'Wrong full rollout' }
        else { Assert ($state.payload.releases.Count -eq 2 -and $state.payload.releases[0].versionCodes[0] -eq '34' -and $state.payload.releases[1].status -eq 'draft') 'Draft lost current release' }
        $previousCalls=$state.calls.Count
        $retryFailed=$false
        try { & $publisher -ManifestPath $manifest -ReleaseNotesPath $notes -CloudExecutable $cloud | Out-Null } catch { $retryFailed=$true }
        Assert ($retryFailed -and $previousCalls -eq $state.calls.Count) 'Receipt did not block resubmission'
    }
    $state.cases++
    Write-Output "PASS: $Mode"
}
Run-Case 'draft'
Run-Case 'submit' -Submit
Run-Case 'validate' -Validate
Run-Case 'duplicate'
Run-Case 'unfinished'
Run-Case 'bad-upload'
Run-Case 'in-review' -Submit
Run-Case 'tampered'
Run-Case 'long-notes'
Write-Output "PASS: $($state.cases) offline publishing cases (including duplicate-retry checks)."

# Exercise the real entry point using a fake builder and publisher.
$wrapperDir=Join-Path $root 'wrapper'
New-Item -ItemType Directory -Path $wrapperDir | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Release-Android.ps1') -Destination $wrapperDir
@'
param($ProjectRoot,$StagingRoot,$FlutterExecutable,[switch]$PassThru)
if ($FlutterExecutable -eq 'fail') { throw 'Simulated build failure' }
if (!$PassThru) { throw 'Manifest not requested' }
Write-Output 'Build progress'
[pscustomobject]@{ManifestPath='verified-manifest.json'}
'@ | Set-Content (Join-Path $wrapperDir 'Build-AndroidRelease.ps1')
@'
param($ManifestPath,$ReleaseNotesPath,[switch]$SubmitForReview)
@{manifest=$ManifestPath;submit=[bool]$SubmitForReview} | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot 'called.json')
'@ | Set-Content (Join-Path $wrapperDir 'Publish-AndroidRelease.ps1')
$wrapper=Join-Path $wrapperDir 'Release-Android.ps1'
$notes=Join-Path $root 'draft/notes.txt'
& $wrapper -ReleaseNotesPath $notes -SubmitForReview
$called=Get-Content (Join-Path $wrapperDir 'called.json') -Raw | ConvertFrom-Json
Assert ($called.submit -and $called.manifest -eq 'verified-manifest.json') 'Wrapper failed to pass verified build and submit option'
& $wrapper -ReleaseNotesPath $notes
$called=Get-Content (Join-Path $wrapperDir 'called.json') -Raw | ConvertFrom-Json
Assert (!$called.submit) 'Wrapper did not default to draft'
Remove-Item -LiteralPath (Join-Path $wrapperDir 'called.json')
$failed=$false
try { & $wrapper -ReleaseNotesPath $notes -FlutterExecutable 'fail' } catch { $failed=$true }
Assert ($failed -and !(Test-Path (Join-Path $wrapperDir 'called.json'))) 'Build failure did not prevent upload'
Write-Output 'PASS: one-command submit, draft and build-failure workflows.'
