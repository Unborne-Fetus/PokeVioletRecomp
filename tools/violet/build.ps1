# Rebuild using the private dependencies/compiler prepared in this checkout.
[CmdletBinding()]
param([switch]$Game, [ValidateRange(1, 32)][int]$Jobs = 4)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$bash = 'C:\msys64\usr\bin\bash.exe'
foreach ($required in @($bash, (Join-Path $root 'build\zig\zig.exe'),
        (Join-Path $root 'build\msys-deps\ucrt64\include\SDL3\SDL.h'))) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing local build dependency: $required" }
}
$savedEnvironment = @{}
foreach ($name in @('PATH','TEMP','TMP','ZIG_GLOBAL_CACHE_DIR','ZIG_LOCAL_CACHE_DIR')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
Push-Location $root
try {
    $env:PATH = 'C:\msys64\ucrt64\bin;C:\msys64\usr\bin;' + $env:PATH
    $env:TEMP = Join-Path $root 'build\tmp'
    $env:TMP = $env:TEMP
    $env:ZIG_GLOBAL_CACHE_DIR = Join-Path $root 'build\zig-cache'
    $env:ZIG_LOCAL_CACHE_DIR = Join-Path $root 'build\zig-local-cache'
    New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
    # Do not marshal space-containing CC/CXX/GENOPT values through bash -c "$@" from PowerShell.
    # Windows native argument passing can strip those quotes, so make sees -target or -DGUEST_VOLATILE
    # as flags instead of parts of a single VAR=value argument. Use a real Bash script and array.
    $makeScript = 'tools/violet/make_local.sh'
    if (-not (Test-Path -LiteralPath $makeScript -PathType Leaf)) {
        throw "Missing $makeScript. Update the pokemon-za checkout before building."
    }
    & $bash --noprofile --norc $makeScript $Jobs objects
    if ($LASTEXITCODE) { throw 'Runtime object compilation failed.' }
    python tools\violet\build_config.py
    if ($LASTEXITCODE) { throw 'Local build configuration failed.' }
    $target = if ($Game) { 'build/violet-gnu/lasgame.dll' } else { 'build/violet-gnu/lasrecomp.exe' }
    if ($Game -and -not (Test-Path -LiteralPath generated\main\main_build_id.txt)) {
        throw 'Generate Violet first with tools\violet\prepare.ps1 -Generate.'
    }
    & $bash --noprofile --norc $makeScript $Jobs link $target
    if ($LASTEXITCODE) { throw 'Native build/link failed.' }
} finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
    Pop-Location
}
