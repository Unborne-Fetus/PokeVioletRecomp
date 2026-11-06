# Resolve native Violet crash addresses against THIS PC's matching EXE/PDB.
# Read-only: does not recompile, launch the game, change saves, upload files, or invoke a debugger.
[CmdletBinding()]
param([string]$LogPath, [switch]$ScanOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exe = Join-Path $root 'build\violet-gnu\lasrecomp.exe'
$pdb = Join-Path $root 'build\violet-gnu\lasrecomp.pdb'
if (-not $LogPath) {
    $logs = Join-Path $root 'build\violet-launch-logs'
    $latest = Get-ChildItem -LiteralPath $logs -Filter '*-stderr.log' -File -ErrorAction Stop |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $latest) { throw "No captured crash log found in $logs" }
    $LogPath = $latest.FullName
}
if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
    throw "Crash log missing: $LogPath"
}
$content = Get-Content -LiteralPath $LogPath -Raw
# The printed host backtrace is from the crash handler; lasrecomp offsets are
# relative to this EXE and independent of Windows ASLR. Never use guest addresses
# such as 7000cd27c4 as EXE offsets.
$hits = [regex]::Matches($content, '(?im)^\s*#\d+\s+[0-9a-f]+\s+lasrecomp\+([0-9a-f]+)')
$offsets = New-Object 'System.Collections.Generic.List[UInt64]'
$seen = New-Object 'System.Collections.Generic.HashSet[UInt64]'
foreach ($hit in $hits) {
    $rva = [Convert]::ToUInt64($hit.Groups[1].Value, 16)
    if ($seen.Add($rva)) { [void]$offsets.Add($rva) }
}
if (-not $offsets.Count) { throw 'No native lasrecomp+RVA entries in the supplied log.' }
Write-Output "Crash log: $LogPath"
Write-Output ("Native executable offsets: " + (($offsets | ForEach-Object { '0x{0:x}' -f $_ }) -join ', '))
if ($ScanOnly) { return }
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Native exe missing: $exe" }
if (-not (Test-Path -LiteralPath $pdb -PathType Leaf)) {
    throw "Matching debug symbols missing: $pdb (do not use a PDB from another build)."
}
$source = Join-Path $PSScriptRoot 'VioletNativeSymbols.cs'
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw 'VioletNativeSymbols.cs missing; update pokemon-za before running.'
}
if (-not ([System.Management.Automation.PSTypeName]'VioletNativeSymbols').Type) {
    Add-Type -Path $source -ErrorAction Stop
}
Write-Output "Resolving native call stack using local Windows DbgHelp and $pdb"
Write-Output '(no game data or debug symbols are uploaded)'
try {
    $results = [VioletNativeSymbols]::Resolve($exe, [UInt64[]]$offsets.ToArray())
    foreach ($line in $results) { Write-Output $line }
} catch {
    Write-Output ('Symbolization unavailable: ' + $_.Exception.Message)
    Write-Output 'Keep the EXE and matching PDB together. If this still fails, share the PDB only if comfortable.'
    throw
}
