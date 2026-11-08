param([string]$Flutter = 'flutter', [string]$Destination = '', [ValidateSet('m3', 'classic')][string]$VisualStyle = 'm3')
$ErrorActionPreference = 'Stop'
$appRoot = Split-Path -Parent $PSScriptRoot
if (-not $Destination) {
    $edition = if ($VisualStyle -eq 'm3') { 'ORBIT_M3_Preview_0.7.1' } else { 'ORBIT_Classic_0.7.1' }
    $Destination = Join-Path (Split-Path -Parent $appRoot) ('outputs\' + $edition)
}
Push-Location $appRoot
try {
    $m3Flag = if ($VisualStyle -eq 'm3') { 'true' } else { 'false' }
    & $Flutter build windows --release "--dart-define=ORBIT_M3=$m3Flag"
    if ($LASTEXITCODE -ne 0) { throw 'Flutter build failed.' }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $releaseRoot = Join-Path $appRoot 'build\windows\x64\runner\Release'
    foreach ($name in @('orbit_audio.exe', 'flutter_windows.dll', 'file_selector_windows_plugin.dll', 'data')) {
        Copy-Item -LiteralPath (Join-Path $releaseRoot $name) -Destination $Destination -Recurse -Force
    }
    foreach ($folder in @('backend', 'assets', 'projects')) {
        $target = Join-Path $Destination ('app\' + $folder)
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Get-ChildItem -LiteralPath (Join-Path $appRoot $folder) -File | Copy-Item -Destination $target -Force
    }
    New-Item -ItemType Directory -Path (Join-Path $Destination 'scripts') -Force | Out-Null
    foreach ($name in @('setup_engine.ps1', 'orbit.ps1', 'api_example.py')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $Destination 'scripts') -Force
    }
    foreach ($folder in @('docs', 'third_party')) {
        Copy-Item -LiteralPath (Join-Path $appRoot $folder) -Destination $Destination -Recurse -Force
    }
    foreach ($name in @('README.md', 'USER_GUIDE.md', 'AUTOMATION.md', 'WORKFLOWS.md', 'NODES.md', 'RELEASE_NOTES.md', 'orbit.cmd', 'QA.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md')) {
        Copy-Item -LiteralPath (Join-Path $appRoot $name) -Destination $Destination -Force
    }
    Write-Host "Built: $Destination\orbit_audio.exe"
} finally { Pop-Location }
