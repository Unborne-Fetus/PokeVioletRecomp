# Bundle the latest F9 render-pass capture into small contact sheets + draw-state log.
# F9 is already implemented in runtime/hle/input.c and runtime/nvn/vulkan/device.c.
# No game launch, recompilation, save edits, or uploads. Photos stay local.
[CmdletBinding()]
param(
    [int]$MaxImages = 256,
    [int]$Minutes = 3,
    [switch]$IndexOnly
)
$ErrorActionPreference = 'Stop'
if ($MaxImages -lt 1 -or $MaxImages -gt 512) { throw 'MaxImages must be between 1 and 512.' }
if ($Minutes -lt 1 -or $Minutes -gt 30) { throw 'Minutes must be between 1 and 30.' }
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$build = Join-Path $root 'build'
$found = @(Get-ChildItem -LiteralPath $build -File -Filter 'pass_*.png' -ErrorAction Stop |
    Where-Object { $_.Name -match '^pass_(\d+)(?:_\d+)?(?:_c\d+)?\.png$' })
if (-not $found.Count) {
    throw 'No per-pass images found in build/. Run Violet, enter a striped scene, press F9 once, then close the game.'
}
$latest = $found | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
$frame = $null
# When F9 records multiple frames, prefer the recent frame with the most
# pass images (an idle frame can contain only a couple of black point passes).
$minimum = $latest.LastWriteTimeUtc.AddMinutes(-$Minutes)
$recent = @($found | Where-Object { $_.LastWriteTimeUtc -ge $minimum })
$groups = @($recent | Where-Object { $_.Name -match '^pass_\d+_\d{3}(?:_c\d+)?\.png$' } |
    Group-Object { if ($_.Name -match '^pass_(\d+)_\d{3}(?:_c\d+)?\.png$') { $Matches[1] } })
if ($groups.Count) {
    $best = $groups | Sort-Object @{Expression = {$_.Count}; Descending = $true},
        @{Expression = { ($_.Group | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc }; Descending = $true} |
        Select-Object -First 1
    $frame = $best.Name
    $chosen = @($best.Group)
} else {
    $chosen = @($recent)
}
$chosen = @($chosen | Sort-Object Name | Select-Object -First $MaxImages)
if (-not $chosen.Count) { throw 'No recent capture images found.' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$report = Join-Path $build "violet-graphics-report-$stamp"
New-Item -ItemType Directory -Path $report -Force | Out-Null
$index = New-Object System.Collections.Generic.List[string]
$index.Add("Violet F9 render-pass capture: $($latest.LastWriteTimeUtc.ToString('u'))")
$index.Add("Files indexed: $($chosen.Count) (maximum $MaxImages)")
$index.Add("Scene: compare stages to find the FIRST pass whose image has diagonal stripes.")
$index.Add("Generated previews do not modify the source PNGs.")
if ($frame) { $index.Add("Captured frame: $frame") }
if ($chosen.Count -lt 4) {
    $index.Add("WARNING: Very few passes were captured; the actual 3D scene may be missing. Do not infer the cause of striping.")
    Write-Warning "Only $($chosen.Count) passes captured. Move the camera during F9 capture and use LARECOMP_DEBUG_FRAMES=3."
}
foreach ($f in $chosen) { $index.Add($f.Name) }
$index | Set-Content -LiteralPath (Join-Path $report 'pass-index.txt') -Encoding UTF8
if (-not $IndexOnly) {
    Add-Type -AssemblyName System.Drawing
    $columns = 4
    $rows = 8
    $perSheet = $columns * $rows
    $tileW = 270; $tileH = 190
    $thumbW = 254; $thumbH = 153
    $font = [System.Drawing.Font]::new('Consolas', 9)
    $brush = [System.Drawing.Brushes]::White
    try {
        for ($page = 0; $page -lt [int][Math]::Ceiling($chosen.Count / [double]$perSheet); $page++) {
            $bmp = [System.Drawing.Bitmap]::new($columns * $tileW, $rows * $tileH)
            $graphics = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $graphics.Clear([System.Drawing.Color]::FromArgb(24, 30, 45))
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
                for ($n = 0; $n -lt $perSheet; $n++) {
                    $i = $page * $perSheet + $n
                    if ($i -ge $chosen.Count) { break }
                    $file = $chosen[$i]
                    $x = ($n % $columns) * $tileW + 8
                    $y = [int][Math]::Floor($n / $columns) * $tileH + 7
                    $img = [System.Drawing.Image]::FromFile($file.FullName)
                    try {
                        $scale = [Math]::Min($thumbW / [double]$img.Width, $thumbH / [double]$img.Height)
                        $w = [int][Math]::Max(1, [Math]::Round($img.Width * $scale))
                        $h = [int][Math]::Max(1, [Math]::Round($img.Height * $scale))
                        $graphics.DrawImage($img, [System.Drawing.Rectangle]::new($x, $y, $w, $h))
                    } finally {
                        $img.Dispose()
                    }
                    $graphics.DrawString($file.Name, $font, $brush, [float]$x, [float]($y + $thumbH + 3))
                }
                $out = Join-Path $report ('contact-sheet-{0:D2}.png' -f ($page + 1))
                $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
            } finally {
                $graphics.Dispose()
                $bmp.Dispose()
            }
        }
    } finally { $font.Dispose() }
}
$logs = Join-Path $build 'violet-launch-logs'
$latestLog = Get-ChildItem -LiteralPath $logs -Filter '*-stderr.log' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
if ($latestLog) {
    $match = @(Select-String -LiteralPath $latestLog.FullName -Pattern '^\[draw\]', '^\[pass\]', '^\[vtxstate\]', '^===== debug frame', '^\[vk\].*fault' -ErrorAction SilentlyContinue)
    if ($match.Count) {
        $match | Select-Object -Last 16000 | ForEach-Object { $_.Line } |
            Set-Content -LiteralPath (Join-Path $report 'draw-state.log') -Encoding UTF8
    }
    "Source log: $($latestLog.FullName)" | Add-Content -LiteralPath (Join-Path $report 'pass-index.txt')
}
$zip = "$report.zip"
Compress-Archive -Path (Join-Path $report '*') -DestinationPath $zip -CompressionLevel Optimal
Write-Output "F9 capture report: $zip"
Write-Output "Indexed $($chosen.Count) pass images in $([Math]::Ceiling($chosen.Count / 32)) contact sheets."
$reporter = Join-Path $PSScriptRoot 'graphics_local_report.py'
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python -and (Test-Path -LiteralPath $reporter)) {
    try {
        & $python.Source $reporter --build $build | Out-Null
        Write-Output 'Private graphics summary refreshed in build/violet-graphics-diagnostics/latest-summary.json'
    } catch {
        Write-Warning ("Could not refresh private graphics summary: " + $_.Exception.Message)
    }
}
Write-Output 'No manual ZIP upload is needed. The connected local project bridge can inspect the JSON summary while online.'
