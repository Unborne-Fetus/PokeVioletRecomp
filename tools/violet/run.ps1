# Run Violet from this checkout with its extracted game directory and private dependency DLLs.
# -Play skips the import/start screen; without it, the player sees the launcher.
[CmdletBinding()]
param([switch]$Play, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exe = Join-Path $root 'build\violet-gnu\lasrecomp.exe'
$gameDll = Join-Path $root 'build\violet-gnu\lasgame.dll'
$gameRoot = Join-Path $root 'extracted'
$exefs = Join-Path $gameRoot 'exefs'
$depDir = Join-Path $root 'build\msys-deps\ucrt64\bin'

if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "Violet's native executable is missing: $exe. Run .\tools\violet\build.ps1 -Game."
}
if (-not (Test-Path -LiteralPath $depDir -PathType Container)) {
    throw "The runtime DLL directory is missing: $depDir. Restore the private build dependencies."
}
if ($Play -or $CheckOnly) {
    $required = @(
        (Join-Path $exefs 'main'),
        (Join-Path $exefs 'subsdk0'),
        (Join-Path $exefs 'sdk'),
        (Join-Path $exefs 'main.npdm'),
        (Join-Path $gameRoot 'romfs.bin'),
        $gameDll
    )
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missing.Count) {
        throw ("Violet is not prepared to launch. Missing files:`n  " + ($missing -join "`n  ") +
            "`nPrepare your own game with .\tools\violet\prepare.ps1 -Generate and build with .\tools\violet\build.ps1 -Game.")
    }
}
if ($CheckOnly) {
    Write-Host 'Violet launch inputs present. This does not prove that guest startup succeeds.'
    Write-Host "Game data: $gameRoot"
    Write-Host "Runtime: $exe"
    return
}

$oldPath = $env:PATH
Push-Location $root
try {
    $env:PATH = $depDir + ';' + $env:PATH
    # The runtime changes its working directory to the user data root; it must get an absolute game directory.
    # The controlled test_boot.ps1 already passes this path, but the regular runner previously did not.
    $runArgs = @($gameRoot)
    if ($Play) { $runArgs += '--play' }
    & $exe @runArgs
    if ($LASTEXITCODE) {
        throw "Violet Recomp exited with code $LASTEXITCODE. Check the program's logs/play.log or run tools\violet\test_boot.ps1 for a scratch boot report."
    }
} finally {
    $env:PATH = $oldPath
    Pop-Location
}
