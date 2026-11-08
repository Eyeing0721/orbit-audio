param([string]$Destination = '')
$ErrorActionPreference = 'Stop'
$appRoot = Split-Path -Parent $PSScriptRoot
if (-not $Destination) {
    $Destination = Join-Path (Split-Path -Parent $appRoot) 'outputs\ORBIT_Source_0.7.1_M3.zip'
}
if (Test-Path -LiteralPath $Destination) { throw "Archive already exists: $Destination" }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stream = [System.IO.File]::Open($Destination, [System.IO.FileMode]::CreateNew)
$archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $files = @()
    foreach ($folder in @('lib', 'backend', 'assets', 'projects', 'scripts', 'test', 'windows', 'docs', 'third_party')) {
        $files += Get-ChildItem -LiteralPath (Join-Path $appRoot $folder) -File -Recurse |
            Where-Object { $_.FullName -notmatch '[\\/](__pycache__|ephemeral)[\\/]' }
    }
    foreach ($name in @('.gitignore', '.metadata', 'analysis_options.yaml', 'pubspec.yaml', 'pubspec.lock', 'README.md', 'USER_GUIDE.md', 'AUTOMATION.md', 'WORKFLOWS.md', 'NODES.md', 'RELEASE_NOTES.md', 'orbit.cmd', 'QA.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md')) {
        $files += Get-Item -LiteralPath (Join-Path $appRoot $name)
    }
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($appRoot.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $file.FullName, "spatial_audio_editor/$relative",
            [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
} finally {
    $archive.Dispose()
    $stream.Dispose()
}
Write-Host "Source archive: $Destination"
