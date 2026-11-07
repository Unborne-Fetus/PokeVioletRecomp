# Capture only a small region over Violet's player hair.  No game archive
# or manually transferred ZIP is required; the local bridge can read the
# generated JSON after the game exits.
[CmdletBinding()]
param(
    [ValidateRange(0,1000)][int]$X = 320,
    [ValidateRange(0,1000)][int]$Y = 220,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$probe = Join-Path $PSScriptRoot 'graphics_probe_launch.ps1'
if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) {
    throw "Violet's F9 graphics probe is missing: $probe"
}
Write-Output 'Violet hair-material probe (local only):'
Write-Output ("  Target at {0}% across and {1}% down the GAME WINDOW." -f ($X / 10), ($Y / 10))
Write-Output '  Position the player so their hair covers this point, then press F9 once.'
Write-Output '  Close the game normally; no ZIP or screenshot needs to be sent.'
& $probe -X $X -Y $Y -Frames 2 -NoArchive -DryRun:$DryRun
