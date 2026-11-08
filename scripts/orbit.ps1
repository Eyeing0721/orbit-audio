param([Parameter(ValueFromRemainingArguments=$true)][string[]]$OrbitArguments)
$ErrorActionPreference = 'Stop'
$appRoot = Split-Path -Parent $PSScriptRoot
if (Test-Path -LiteralPath (Join-Path $appRoot 'app\backend\cli.py')) { $appRoot = Join-Path $appRoot 'app' }
$enginePython = 'python'
$localPython = Join-Path $appRoot 'runtime\Scripts\python.exe'
if (Test-Path -LiteralPath $localPython) { $enginePython = $localPython }
if ($env:ORBIT_PYTHON) { $enginePython = $env:ORBIT_PYTHON }
& $enginePython -u (Join-Path $appRoot 'backend\cli.py') @OrbitArguments
exit $LASTEXITCODE
