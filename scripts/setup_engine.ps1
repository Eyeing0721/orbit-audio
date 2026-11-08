param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$appRoot = Split-Path -Parent $PSScriptRoot
if (Test-Path -LiteralPath (Join-Path $appRoot 'app\backend')) { $appRoot = Join-Path $appRoot 'app' }
$runtime = Join-Path $appRoot 'runtime'
& $Python -m venv --system-site-packages $runtime
if ($LASTEXITCODE -ne 0) { throw 'Python 3.11 or newer is required.' }
$enginePython = Join-Path $runtime 'Scripts\python.exe'
& $enginePython -m pip install -r (Join-Path $appRoot 'backend\requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Audio dependency installation failed.' }
Write-Host 'ORBIT engine is ready. Audio is processed locally. AI weights download on first use.'
