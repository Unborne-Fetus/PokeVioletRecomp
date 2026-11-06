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
    Write-Output "Violet F9 per-draw probe: ($probe) in 0-1000 normalized scene coordinates; $Frames frames"
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
    # The native F9 probe hashes a 64x64 pixel region, but its PNG writer dumps
    # the entire render target. Crop around the watched pixel to keep the ZIP
    # practical and retain exact pixels; also keep a vertically reflected crop
    # because some render targets use a lower-left origin.
    Add-Type -AssemblyName System.Drawing
    $saved = 0
    foreach ($f in $images) {
        $source = [System.Drawing.Image]::FromFile($f.FullName)
        try {
            $cropW = [Math]::Min(64, $source.Width)
            $cropH = [Math]::Min(64, $source.Height)
            $cx = [int][Math]::Floor($source.Width * $X / 1000)
            $cy = [int][Math]::Floor($source.Height * $Y / 1000)
            $left = [Math]::Max(0, [Math]::Min($source.Width - $cropW, $cx - [int]($cropW / 2)))
            $top = [Math]::Max(0, [Math]::Min($source.Height - $cropH, $cy - [int]($cropH / 2)))
            $otherTop = [Math]::Max(0, [Math]::Min($source.Height - $cropH,
                $source.Height - $cy - [int]($cropH / 2)))
            $bmp = [System.Drawing.Bitmap]::new(2 * $cropW, $cropH)
            $graphics = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $graphics.Clear([System.Drawing.Color]::Black)
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
                $graphics.DrawImage($source,
                    [System.Drawing.Rectangle]::new(0, 0, $cropW, $cropH),
                    [System.Drawing.Rectangle]::new($left, $top, $cropW, $cropH),
                    [System.Drawing.GraphicsUnit]::Pixel)
                $graphics.DrawImage($source,
                    [System.Drawing.Rectangle]::new($cropW, 0, $cropW, $cropH),
                    [System.Drawing.Rectangle]::new($left, $otherTop, $cropW, $cropH),
                    [System.Drawing.GraphicsUnit]::Pixel)
                $bmp.Save((Join-Path $dest $f.Name), [System.Drawing.Imaging.ImageFormat]::Png)
                $saved++
            } finally {
                $graphics.Dispose()
                $bmp.Dispose()
            }
        } finally {
            $source.Dispose()
        }
    }
    @(
        "F9 per-draw probe frame: $($group.Name)"
        "Normalized location: $probe"
        "Images: $saved"
        'The probe tests a 64x64 region for changes, then saves its full-color render target.'
        'Each PNG here contains two crops of that target: direct Y at left, vertically flipped Y at right.'
        'The original full-frame PNGs remain in build/ and are NOT overwritten.'
        'The stderr [probe] line names the vertex and fragment shaders for each draw.'
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
    Write-Output "Captured $saved cropped images from the changed 3D pixel region on frame $($group.Name)."
    if ($runtimeError) { throw $runtimeError }
} finally {
    [Environment]::SetEnvironmentVariable('LARECOMP_PROBE', $previousProbe, 'Process')
    [Environment]::SetEnvironmentVariable('LARECOMP_DEBUG_FRAMES', $previousFrames, 'Process')
}
