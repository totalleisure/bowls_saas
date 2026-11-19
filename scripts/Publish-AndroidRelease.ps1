<# Upload a verified build. Default: Production draft; -SubmitForReview requests full rollout. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$ReleaseNotesPath,
    [ValidateSet('production', 'internal')][string]$Track = 'production',
    [switch]$SubmitForReview,
    [switch]$ValidateOnly,
    [string]$CloudExecutable = '',
    [string]$Account = 'wayne.s.sayers@gmail.com'
)
$ErrorActionPreference = 'Stop'
$ManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$package = 'totalleisuresolutions.bowls'
if ($manifest.package -ne $package -or $manifest.entry_point -ne 'lib/main.dart' -or
    $manifest.tests -ne 'passed' -or $manifest.signature -ne 'verified' -or
    [long]$manifest.build -le 0 -or $manifest.version -notmatch '^\d+\.\d+\.\d+$') {
    throw 'A verified production build manifest is required.'
}
if ([IO.Path]::GetFileName($manifest.artifact) -ne $manifest.artifact -or $manifest.artifact -notlike '*.aab') {
    throw 'Invalid bundle filename in manifest.'
}
$folder = Split-Path $ManifestPath -Parent
$bundle = Join-Path $folder $manifest.artifact
$hash = (Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash
if ($hash -ne $manifest.sha256) { throw 'Bundle checksum differs from the verified build.' }
$notes = (Get-Content -LiteralPath $ReleaseNotesPath -Raw -Encoding UTF8).Trim()
if (!$notes -or $notes.Length -gt 500 -or $notes -match '</?en-') {
    throw 'Use plain release notes (no language tags), between 1 and 500 characters.'
}
$receiptPath = Join-Path $folder "play-$Track.json"
if (Test-Path -LiteralPath $receiptPath) {
    throw "A publishing receipt already exists at $receiptPath. Inspect it before retrying; do not submit twice."
}
Write-Output "Verified: $($manifest.version) ($($manifest.build)), $Track, SHA256 $hash"
if ($ValidateOnly) { Write-Output 'Local validation passed. No Google Play requests made.'; return }
if (!$CloudExecutable) {
    $cloudCommand = Get-Command gcloud.cmd -ErrorAction SilentlyContinue
    if ($cloudCommand) { $CloudExecutable = $cloudCommand.Source }
    else { $CloudExecutable = Join-Path $env:LOCALAPPDATA 'Google/Cloud SDK/google-cloud-sdk/bin/gcloud.cmd' }
}
if (!(Test-Path -LiteralPath $CloudExecutable)) { throw 'Google Cloud CLI not found. Install it and run gcloud auth login.' }
$sourceToken = $null; $mint = $null; $headers = $null; $edit = $null; $committed = $false
$base = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$package/edits"
try {
    $sourceToken = (& $CloudExecutable auth print-access-token "--account=$Account" --quiet | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or !$sourceToken) { throw 'Google sign-in expired. Run gcloud auth login and retry.' }
    $service = 'bowls-play-publisher@project-b887e914-dd44-4a28-9ec.iam.gserviceaccount.com'
    $mint = Invoke-RestMethod -Method Post -Uri "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${service}:generateAccessToken" -Headers @{Authorization="Bearer $sourceToken"} -ContentType 'application/json' -Body '{"scope":["https://www.googleapis.com/auth/androidpublisher"],"lifetime":"3600s"}'
    $sourceToken = $null
    $headers = @{Authorization="Bearer $($mint.accessToken)"}
    $edit = Invoke-RestMethod -Method Post -Uri $base -Headers $headers -ContentType 'application/json' -Body '{}'
    $editUrl = "$base/$($edit.id)"
    $tracks = Invoke-RestMethod -Method Get -Uri "$editUrl/tracks" -Headers $headers
    $target = @($tracks.tracks | Where-Object { $_.track -eq $Track })
    if (@($target.releases | Where-Object { $_.status -in @('draft','inProgress','halted') }).Count) {
        throw 'The target track has an unfinished release. Resolve it in Play Console before creating another.'
    }
    $bundles = Invoke-RestMethod -Method Get -Uri "$editUrl/bundles" -Headers $headers
    $apks = Invoke-RestMethod -Method Get -Uri "$editUrl/apks" -Headers $headers
    $codes = @($bundles.bundles | ForEach-Object { [long]$_.versionCode }) +
        @($apks.apks | ForEach-Object { [long]$_.versionCode }) +
        @($tracks.tracks.releases.versionCodes | ForEach-Object { [long]$_ })
    if (@($codes | Where-Object { $_ -ge [long]$manifest.build }).Count) {
        throw 'This version code is already used, or a newer build exists. Increase pubspec.yaml build number and rebuild.'
    }
    Write-Output 'Uploading signed bundle to Google Play...'
    $uploaded = Invoke-RestMethod -Method Post -Uri "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$package/edits/$($edit.id)/bundles?uploadType=media" -Headers $headers -ContentType 'application/octet-stream' -InFile $bundle -TimeoutSec 1800
    if ([long]$uploaded.versionCode -ne [long]$manifest.build -or $uploaded.sha256 -ne $hash) {
        throw 'Google Play returned a different version code or checksum. Edit will not be committed.'
    }
    $status = 'draft'
    if ($SubmitForReview) { $status = 'completed' }
    $release = @{name="$($manifest.version) ($($manifest.build))"; versionCodes=@("$($manifest.build)"); status=$status; releaseNotes=@(@{language='en-GB';text=$notes})}
    # A draft must retain the currently completed release. Full rollout replaces it.
    $releases = @($release)
    if (!$SubmitForReview) { $releases = @($target.releases | Where-Object { $null -ne $_ }) + @($release) }
    $body = @{track=$Track; releases=$releases} | ConvertTo-Json -Depth 12
    Invoke-RestMethod -Method Put -Uri "$editUrl/tracks/$Track" -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) | Out-Null
    Invoke-RestMethod -Method Post -Uri "${editUrl}:validate" -Headers $headers | Out-Null
    $receipt = [ordered]@{version=$manifest.version;build=$manifest.build;sha256=$hash;track=$Track;release_status=$status;state='commit_started';edit_id=$edit.id;time_utc=[DateTime]::UtcNow.ToString('o')}
    $receipt | ConvertTo-Json | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    # Never cancel another review. Do not silently fall back to a less safe commit mode.
    Invoke-RestMethod -Method Post -Uri "${editUrl}:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW" -Headers $headers | Out-Null
    $committed = $true
    $receipt.state = 'committed'
    $receipt | ConvertTo-Json | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    if ($SubmitForReview) { Write-Output 'Submitted for Google Play review/full rollout. Approval and availability are controlled by Google and managed publishing settings.' }
    else { Write-Output 'Production/testing draft saved. No rollout requested. Open Play Console to review and submit it.' }
    Write-Output "Receipt: $receiptPath"
} finally {
    if ($edit -and !$committed) {
        try { Invoke-RestMethod -Method Delete -Uri "$base/$($edit.id)" -Headers $headers | Out-Null }
        catch { Write-Warning 'Could not remove the temporary edit. Check Play Console before retrying.' }
    }
    $sourceToken = $null; $mint = $null; $headers = $null
}
