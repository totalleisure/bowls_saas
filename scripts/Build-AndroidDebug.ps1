param([string]$FlutterExecutable = 'flutter')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
# Windows packaged shells can expose a temporary path that Java cannot use
# for AF_UNIX selector sockets. Keep the override local to this build process.
$socketDirectory = Join-Path $projectRoot 'tmp'
New-Item -ItemType Directory -Force -Path $socketDirectory | Out-Null
$previousJavaOptions = $env:JAVA_TOOL_OPTIONS
$previousAndroidHome = $env:ANDROID_USER_HOME
try {
    $env:JAVA_TOOL_OPTIONS = "$previousJavaOptions -Djdk.net.unixdomain.tmpdir=`"$socketDirectory`" -Duser.home=`"$env:USERPROFILE`""
    $env:ANDROID_USER_HOME = Join-Path $env:USERPROFILE '.android'
    Push-Location $projectRoot
    try {
        & $FlutterExecutable build apk --debug
        if ($LASTEXITCODE -ne 0) { throw "Android debug build failed ($LASTEXITCODE)." }
    } finally { Pop-Location }
} finally {
    $env:JAVA_TOOL_OPTIONS = $previousJavaOptions
    $env:ANDROID_USER_HOME = $previousAndroidHome
}
