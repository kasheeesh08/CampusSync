<#
.SYNOPSIS
  Builds the CampusSync Android release APK for an explicitly chosen backend,
  then confirms the APK really was built for that backend.

.DESCRIPTION
  A plain `flutter build apk --release` produces a DEMO build (bundled data,
  nothing saved to a server). This script makes the backend a required choice
  and reads the "campussync.backend" manifest entry (written by
  app/android/app/build.gradle.kts) back from the finished APK. It exits with
  an error if the build failed, the APK is stale, or the recorded backend does
  not match the one requested.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Backend live
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Backend demo
.EXAMPLE
  # Report which backend an existing APK was built for (builds nothing).
  powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Verify app\build\app\outputs\flutter-apk\app-release.apk
#>
[CmdletBinding(DefaultParameterSetName = 'Build')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Build')]
    [ValidateSet('demo', 'live')]
    [string]$Backend,

    [Parameter(Mandatory = $true, ParameterSetName = 'Verify')]
    [string]$Verify
)

$ErrorActionPreference = 'Stop'
$appDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'app'
$flutter = Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat'
$apk = Join-Path $appDir 'build\app\outputs\flutter-apk\app-release.apk'

# Backend recorded in the APK's manifest, or $null if absent (built before this check existed).
function Get-ApkBackend([string]$path) {
    $buildTools = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Android\Sdk\build-tools') -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'aapt.exe') } |
        Sort-Object { [version]($_.Name -replace '-.*$', '') } |
        Select-Object -Last 1
    if (-not $buildTools) { throw 'aapt.exe not found under the Android SDK build-tools.' }
    $lines = @(& (Join-Path $buildTools.FullName 'aapt.exe') dump xmltree $path AndroidManifest.xml)
    if ($LASTEXITCODE -ne 0) { throw "aapt could not read $path" }
    for ($i = 0; $i -lt $lines.Count - 1; $i++) {
        if ($lines[$i] -match 'android:name\(0x[0-9a-f]+\)="campussync\.backend"' -and
            $lines[$i + 1] -match 'android:value\(0x[0-9a-f]+\)="([^"]*)"') {
            return $Matches[1]
        }
    }
    return $null
}

function Show-Apk([string]$path, [string]$recorded) {
    $f = Get-Item $path
    Write-Host "APK:     $($f.FullName)"
    Write-Host "Built:   $($f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host "Size:    $($f.Length) bytes"
    Write-Host "SHA-256: $((Get-FileHash $path -Algorithm SHA256).Hash.ToLower())"
    Write-Host "Backend: $(if ($recorded) { $recorded } else { 'not recorded (APK predates this check)' })"
}

if ($PSCmdlet.ParameterSetName -eq 'Verify') {
    if (-not (Test-Path $Verify)) { throw "No such file: $Verify" }
    $recorded = Get-ApkBackend $Verify
    Show-Apk $Verify $recorded
    if (-not $recorded) { exit 1 }
    exit 0
}

$started = Get-Date
Push-Location $appDir
try {
    & $flutter build apk --release "--dart-define=CAMPUSSYNC_BACKEND=$Backend"
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit code $LASTEXITCODE)." }
} finally {
    Pop-Location
}

if (-not (Test-Path $apk) -or (Get-Item $apk).LastWriteTime -lt $started) {
    throw "No fresh APK at $apk; refusing to report a stale build."
}
$recorded = Get-ApkBackend $apk
Show-Apk $apk $recorded
if ($recorded -ne $Backend) {
    Write-Host "FAILED: requested backend '$Backend' but the APK records '$recorded'. Do not distribute this APK." -ForegroundColor Red
    exit 1
}
Write-Host "OK: release APK verified for the '$Backend' backend."
