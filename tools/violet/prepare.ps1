# Read the player's packages and optionally generate C. No manual game extraction is needed.
[CmdletBinding()]
param(
    [string]$GameFolder,
    [string[]]$Package,
    [string]$Keys,
    [string]$Output,
    [switch]$InspectOnly,
    [switch]$Generate
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $GameFolder) { $GameFolder = $root }
if (-not $Output) { $Output = Join-Path $root $(if ($InspectOnly) { 'build\violet-inspect' } else { 'extracted' }) }
if (-not $Package) {
    $Package = @(Get-ChildItem -LiteralPath $GameFolder -File |
        Where-Object { $_.Extension -in '.xci', '.nsp' } | Sort-Object Name | ForEach-Object FullName)
}
if (-not $Package.Count) { throw 'No XCI/NSP packages found. Use -GameFolder or -Package.' }
$Package = @($Package | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })
$Output = [IO.Path]::GetFullPath($Output)
if (-not $Keys) {
    $candidates = @((Join-Path $GameFolder 'prod.keys'), (Join-Path $GameFolder 'keys\prod.keys'))
    if ($env:APPDATA) { $candidates += Join-Path $env:APPDATA 'Ryujinx\system\prod.keys' }
    if ($env:USERPROFILE) { $candidates += Join-Path $env:USERPROFILE '.switch\prod.keys' }
    $Keys = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $Keys -or -not (Test-Path -LiteralPath $Keys -PathType Leaf)) {
    throw 'Pass -Keys with the path to prod.keys from your Switch.'
}
$Keys = (Resolve-Path -LiteralPath $Keys).Path
$dotnet = Join-Path $root 'build\toolchain\dotnet\dotnet.exe'
if (-not (Test-Path -LiteralPath $dotnet)) { $dotnet = (Get-Command dotnet -ErrorAction Stop).Source }
if (-not (& $dotnet --list-sdks)) { throw 'The importer build needs the .NET 8 SDK (a runtime alone is insufficient).' }

Push-Location $root
try {
    $env:DOTNET_CLI_HOME = Join-Path $root 'build\dotnet-home'
    $env:NUGET_PACKAGES = Join-Path $root 'build\nuget'
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
    & $dotnet publish tools\zaimport\zaimport.csproj -c Release -r win-x64 --self-contained true `
        -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true -p:DebugType=none -o build\zaimport
    if ($LASTEXITCODE) { throw 'Importer build failed.' }
    $importArgs = @()
    if ($InspectOnly) { $importArgs += '--exefs-only' }
    $importArgs += @($Keys, $Output) + $Package
    & .\build\zaimport\zaimport.exe @importArgs
    if ($LASTEXITCODE) { throw 'Game import failed.' }
    if ($Generate) {
        $python = Join-Path $root 'tools\venv\Scripts\python.exe'
        if (-not (Test-Path -LiteralPath $python)) {
            python -m venv tools\venv
            & $python -m pip install lz4 capstone unicorn
            if ($LASTEXITCODE) { throw 'Generator dependency setup failed.' }
        }
        & $python tools\gen_all.py (Join-Path $Output 'exefs') generated
        if ($LASTEXITCODE) { throw 'Code generation failed.' }
    }
    Write-Host "Violet preparation complete: $Output"
} finally {
    Pop-Location
}
