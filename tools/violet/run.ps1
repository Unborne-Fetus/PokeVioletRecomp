# Run the local development build with its private dependency DLLs on PATH.
[CmdletBinding()]
param([switch]$Play)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exe = Join-Path $root 'build\violet-gnu\lasrecomp.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'The native runtime has not been built in build/violet-gnu.' }
$oldPath = $env:PATH
Push-Location $root
try {
    $env:PATH = (Join-Path $root 'build\msys-deps\ucrt64\bin') + ';' + $env:PATH
    $runArgs = @()
    if ($Play) { $runArgs += '--play' }
    & $exe @runArgs
    if ($LASTEXITCODE) { throw "Violet Recomp exited with code $LASTEXITCODE. Check logs/play.log." }
} finally {
    $env:PATH = $oldPath
    Pop-Location
}
