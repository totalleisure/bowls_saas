param(
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$StagingRoot = 'C:\src\bowls_staging',
    [string]$FlutterExecutable = 'flutter',
    [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$pubspec = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'pubspec.yaml'))
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
    throw 'A release version and build number are required in pubspec.yaml.'
}
$releaseName = $Matches[1]
$releaseBuild = $Matches[2]
$gitArgs = @('-c', "safe.directory=$ProjectRoot", '-C', $ProjectRoot)
$remote = & git @gitArgs remote get-url origin
if ($LASTEXITCODE -ne 0 -or $remote -notmatch '[/ :]bowls_saas(?:\.git)?$') {
    throw 'Run this against the production bowls_saas checkout.'
}
$gradle = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'android/app/build.gradle.kts'))
if ($gradle -notmatch 'applicationId\s*=\s*"totalleisuresolutions\.bowls"' -or
    $gradle -notmatch '(?s)buildTypes\s*\{\s*release\s*\{\s*signingConfig\s*=\s*signingConfigs.getByName\("release"\)') {
    throw 'Production Android identity and release signing must be configured first.'
}
$keyFile = Join-Path $ProjectRoot 'android/key.properties'
if (!(Test-Path -LiteralPath $keyFile)) { throw 'Android signing file android/key.properties is missing.' }
$signing = @{}
foreach ($line in [IO.File]::ReadAllLines($keyFile)) {
    if ($line -match '^\s*(storeFile|storePassword|keyAlias|keyPassword)\s*=\s*(.*)$') {
        $signing[$Matches[1]] = $Matches[2].Trim()
    }
}
foreach ($key in @('storeFile', 'storePassword', 'keyAlias', 'keyPassword')) {
    if ([string]::IsNullOrWhiteSpace($signing[$key])) { throw "Android signing setting $key is missing." }
}
$keyPath = $signing.storeFile.Replace('\\', '\').Replace('\:', ':')
if (![IO.Path]::IsPathRooted($keyPath)) { $keyPath = Join-Path $ProjectRoot "android/app/$keyPath" }
if (!(Test-Path -LiteralPath $keyPath)) { throw 'The configured Android signing keystore cannot be found.' }
$signing.Clear()
$jarsigner = Join-Path ${env:ProgramFiles} 'Android/Android Studio/jbr/bin/jarsigner.exe'
if (!(Test-Path -LiteralPath $jarsigner)) {
    $jarsigner = (Get-Command jarsigner -ErrorAction Stop).Source
}
Get-Command $FlutterExecutable -ErrorAction Stop | Out-Null
$comparison = Join-Path $StagingRoot 'scripts/Compare-AppSources.ps1'
if (!(Test-Path -LiteralPath $comparison)) { throw 'Staging source-comparison script was not found.' }
& $comparison -Production $ProjectRoot -Staging $StagingRoot
Write-Output "Release checks passed: production Android $releaseName ($releaseBuild), release signing files present."
if ($ValidateOnly) { return }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$output = Join-Path $ProjectRoot "tmp/releases/android/$releaseName-$releaseBuild/$stamp"
New-Item -ItemType Directory -Force -Path $output | Out-Null
$oldJavaOptions = $env:JAVA_TOOL_OPTIONS
$oldAndroidHome = $env:ANDROID_USER_HOME
$socketDirectory = Join-Path $ProjectRoot 'tmp'
$env:JAVA_TOOL_OPTIONS = "$oldJavaOptions -Djdk.net.unixdomain.tmpdir=`"$socketDirectory`" -Duser.home=`"$env:USERPROFILE`""
$env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE '.android'
function Invoke-ReleaseFlutter([string[]]$Arguments, [string]$LogName) {
    & $FlutterExecutable @Arguments 2>&1 | Tee-Object -FilePath (Join-Path $output $LogName)
    if ($LASTEXITCODE -ne 0) { throw "Release step failed. See $LogName in $output" }
}
Push-Location $ProjectRoot
try {
    Invoke-ReleaseFlutter -Arguments @('pub', 'get') -LogName 'dependencies.log'
    Invoke-ReleaseFlutter -Arguments @('test', '--no-pub') -LogName 'tests.log'
    $buildStarted = Get-Date
    Invoke-ReleaseFlutter -Arguments @(
        'build', 'appbundle', '--release', '--no-pub', '--target', 'lib/main.dart',
        "--build-name=$releaseName", "--build-number=$releaseBuild",
        '--dart-define=ACCOUNT_USERNAME_ENABLED=false',
        '--dart-define=PROFILE_PHOTOS_ENABLED=false',
        '--dart-define=QUICK_UNLOCK_ENABLED=false'
    ) -LogName 'build.log'
    $bundle = Join-Path $ProjectRoot 'build/app/outputs/bundle/release/app-release.aab'
    if (!(Test-Path -LiteralPath $bundle) -or (Get-Item -LiteralPath $bundle).LastWriteTime -lt $buildStarted) {
        throw 'A fresh Android App Bundle was not produced.'
    }
    $verification = & $jarsigner -verify $bundle 2>&1
    $verification | Set-Content -LiteralPath (Join-Path $output 'signature.log')
    if ($LASTEXITCODE -ne 0 -or ($verification -join "`n") -notmatch 'jar verified') {
        throw 'Android App Bundle signature verification failed.'
    }
    $artifact = Join-Path $output "bowls-$releaseName-$releaseBuild.aab"
    Copy-Item -LiteralPath $bundle -Destination $artifact
    $commit = & git @gitArgs rev-parse HEAD
    $workingChanges = @(& git @gitArgs status --porcelain)
    $notes = Join-Path $ProjectRoot "Docs/releases/$releaseName-$releaseBuild/whats-new.txt"
    if (Test-Path -LiteralPath $notes) { Copy-Item -LiteralPath $notes -Destination (Join-Path $output 'whats-new.txt') }
    [ordered]@{
        version = $releaseName; build = [int]$releaseBuild
        package = 'totalleisuresolutions.bowls'; entry_point = 'lib/main.dart'
        commit = "$commit"; working_changes = $workingChanges
        tests = 'passed'; signature = 'verified'
        artifact = (Split-Path $artifact -Leaf)
        sha256 = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
        built_at = (Get-Date).ToUniversalTime().ToString('o')
        uploaded = $false
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'manifest.json')
    Write-Output "READY: $artifact"
    Write-Output 'No upload performed. Check the version code and upload certificate in Google Play Console before upload.'
} finally {
    Pop-Location
    $env:JAVA_TOOL_OPTIONS = $oldJavaOptions
    $env:ANDROID_USER_HOME = $oldAndroidHome
}
