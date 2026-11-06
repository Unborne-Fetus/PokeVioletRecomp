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
    $common = @('--no-print-directory', "-j$Jobs", 'B=build/violet-gnu', 'DEPS=build/msys-deps/ucrt64',
        'CC=build/zig/zig.exe cc -target x86_64-windows-gnu',
        'CXX=build/zig/zig.exe c++ -target x86_64-windows-gnu',
        'GENARCH=-mcpu=x86_64_v3', 'GENOPT=-O1 -DGUEST_VOLATILE',
        'WINDRES=/c/msys64/ucrt64/bin/windres.exe')
    & $bash --noprofile --norc -c 'exec make "$@"' violet-build @common runtime-objs
    if ($LASTEXITCODE) { throw 'Runtime object compilation failed.' }
    python tools\violet\build_config.py
    if ($LASTEXITCODE) { throw 'Local build configuration failed.' }
    $target = if ($Game) { 'build/violet-gnu/lasgame.dll' } else { 'build/violet-gnu/lasrecomp.exe' }
    if ($Game -and -not (Test-Path -LiteralPath generated\main\main_build_id.txt)) {
        throw 'Generate Violet first with tools\violet\prepare.ps1 -Generate.'
    }
    & $bash --noprofile --norc -c 'exec make "$@"' violet-build @common -f Makefile `
        -f build/violet-gnu/toolchain.mk -f build/violet-gnu/giants.mk $target
    if ($LASTEXITCODE) { throw 'Native build/link failed.' }
} finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
    Pop-Location
}
