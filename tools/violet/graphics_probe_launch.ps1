# Capture the first draw that changes a 64x64 striped portion of Violet's 3D scene.
# This uses the native renderer's existing F9 pixel probe. The underlying
# game/rendering behavior is unchanged outside this opt-in diagnostic.
[CmdletBinding()]
param(
    [ValidateRange(0,1000)][int]$X = 400,
    [ValidateRange(0,1000)][int]$Y = 780,
    [ValidateRange(2,3)][int]$Frames = 2,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$build = Join-Path $root 'build'
$runner = Join-Path $PSScriptRoot 'run.ps1'
$previousProbe = [Environment]::GetEnvironmentVariable('LARECOMP_PROBE', 'Process')
$previousFrames = [Environment]::GetEnvironmentVariable('LARECOMP_DEBUG_FRAMES', 'Process')
$probe = "$X,$Y"
try {
    [Environment]::SetEnvironmentVariable('LARECOMP_PROBE', $probe, 'Process')
    [Environment]::SetEnvironmentVariable('LARECOMP_DEBUG_FRAMES', [string]$Frames, 'Process')
    Write-Output "Violet F9 per-draw probe: ($probe) in 0–1000 normalized scene coordinates; $Frames frames"
    Write-Output 'At a visibly striped room or floor, move the camera slightly and press F9 once.'
    Write-Output 'The game may pause while probing individual draws. Close the game to package the results.'
    if ($DryRun) { return }
    if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) { throw "Native launcher missing: $runner" }
    $since = (Get-Date).AddSeconds(-2)
    $runtimeError = $null
    try { & $runner -Play -RebuildRuntime -CaptureCrash }
    catch {
        $runtimeError = $_
        Write-Warning ("Violet exited during probing: " + $_.Exception.Message)
    }
    $new = @(Get-ChildItem -LiteralPath $build -Filter 'probe_*.png' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $since -and $_.Name -match '^probe_\d+_\d+\.png$' })
    if (-not $new.Count) {
        Write-Warning 'No new probe images found; check game focus and press F9 once while the 3D scene is visible.'
        if ($runtimeError) { throw $runtimeError }
        return
    }
    $group = $new | Group-Object {
        if ($_.Name -match '^probe_(\d+)_\d+\.png$') { $Matches[1] }
    } | Sort-Object @{Expression = {$_.Count}; Descending = $true} | Select-Object -First 1
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dest = Join-Path $build "violet-probe-$stamp"
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $images = @($group.Group | Sort-Object Name | Select-Object -First 80)
    foreach ($f in $images) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $dest $f.Name) }
    @(
        "F9 per-draw probe frame: $($group.Name)"
        "Normalized location: $probe"
        "Images: $($images.Count)"
        'Each PNG is a 64x64 region after a draw; the stderr [probe] line names its vertex and fragment shaders.'
        'Compare consecutive images to locate the first draw that adds stripes.'
        'Do not upload this ZIP or game data to a public GitHub repository.'
    ) | Set-Content -LiteralPath (Join-Path $dest 'readme.txt') -Encoding UTF8
    $logDir = Join-Path $build 'violet-launch-logs'
    $log = Get-ChildItem -LiteralPath $logDir -Filter '*-stderr.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($log) {
        $matches = @(Select-String -LiteralPath $log.FullName -Pattern '^\[probe\]', '^\[vtxstate\]', '^\[vk\].*fault' -ErrorAction SilentlyContinue)
        if ($matches.Count) {
            $matches | Select-Object -Last 16000 | ForEach-Object { $_.Line } |
                Set-Content -LiteralPath (Join-Path $dest 'draw-origin.log') -Encoding UTF8
        }
    }
    $zip = "$dest.zip"
    Compress-Archive -Path (Join-Path $dest '*') -DestinationPath $zip -CompressionLevel Optimal
    Write-Output "F9 per-draw probe report: $zip"
    Write-Output "Captured $($images.Count) changes to 64x64 scene pixels on frame $($group.Name)."
    if ($runtimeError) { throw $runtimeError }
} finally {
    [Environment]::SetEnvironmentVariable('LARECOMP_PROBE', $previousProbe, 'Process')
    [Environment]::SetEnvironmentVariable('LARECOMP_DEBUG_FRAMES', $previousFrames, 'Process')
}
