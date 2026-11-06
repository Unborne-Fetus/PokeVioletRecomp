# Start Violet with a short, frame-accurate F9 capture; report when the game exits.
# This uses the existing launcher and does not alter any saves or game assets.
[CmdletBinding()]
param(
    [ValidateRange(2, 5)][int]$Frames = 3,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runner = Join-Path $PSScriptRoot 'run.ps1'
$reporter = Join-Path $PSScriptRoot 'graphics_capture_report.ps1'
$build = Join-Path $root 'build'
$old = [Environment]::GetEnvironmentVariable('LARECOMP_DEBUG_FRAMES', 'Process')
try {
    [Environment]::SetEnvironmentVariable('LARECOMP_DEBUG_FRAMES', [string]$Frames, 'Process')
    Write-Output "Violet F9 diagnostic: $Frames consecutive rendering frames"
    Write-Output 'Move the camera in a striped 3D scene, press F9 exactly once, and then close the game.'
    Write-Output 'The images and report remain under build/; they are not uploaded automatically.'
    if ($DryRun) { return }
    if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) { throw "Missing runner: $runner" }
    if (-not (Test-Path -LiteralPath $reporter -PathType Leaf)) { throw "Missing reporter: $reporter" }
    $since = Get-Date
    $gameError = $null
    try {
        & $runner -Play -RebuildRuntime -CaptureCrash
    } catch {
        $gameError = $_
        Write-Warning ("Violet exited with an error: " + $_.Exception.Message)
    }
    $newPasses = @(Get-ChildItem -LiteralPath $build -File -Filter 'pass_*.png' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $since })
    if ($newPasses.Count) {
        Write-Output "Found $($newPasses.Count) new render-pass images."
        & $reporter -Minutes 30
    } else {
        Write-Warning 'No new F9 pass images were found. Ensure the game has focus, move the camera, then press F9.'
    }
    if ($gameError) { throw $gameError }
} finally {
    [Environment]::SetEnvironmentVariable('LARECOMP_DEBUG_FRAMES', $old, 'Process')
}
