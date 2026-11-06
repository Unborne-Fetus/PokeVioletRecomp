# Compare Violet renderer paths without altering the working default, saves, or settings.
# A single run uses temporary environment variables, restored on exit.
[CmdletBinding()]
param(
    [ValidateSet('Baseline', 'PackagedZero', 'ConservativeUploads', 'BC5Unsigned', 'Depth32')]
    [string]$Mode = 'PackagedZero',
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$vars = @(
    'LARECOMP_PACKAGED_ZERO_BH',
    'LARECOMP_LOG_PACKAGED',
    'LARECOMP_TEX_UNPACK_THREADS',
    'LARECOMP_VK_TEX_WATCH',
    'LARECOMP_TEX_FULLHASH',
    'LARECOMP_BC5_UNORM',
    'LARECOMP_VK_D24'
)
$old = @{}
foreach ($name in $vars) { $old[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$chosen = @{}
switch ($Mode) {
    'Baseline' {
        # Clear all temporary graphics investigation variables so this is
        # directly comparable with a normal Play Violet.cmd launch.
    }
    'PackagedZero' {
        # Test an explicit zero GOB block height when the NVN builder has
        # packaged texture data. Incorrect block heights weave BC/ASTC blocks.
        $chosen['LARECOMP_PACKAGED_ZERO_BH'] = '1'
        $chosen['LARECOMP_LOG_PACKAGED'] = '1'
    }
    'ConservativeUploads' {
        # Diagnostic only: costly. Rules out stale uploads and parallel unpacking.
        $chosen['LARECOMP_TEX_UNPACK_THREADS'] = '0'
        $chosen['LARECOMP_VK_TEX_WATCH'] = '0'
        $chosen['LARECOMP_TEX_FULLHASH'] = '1'
    }
    'BC5Unsigned' {
        # Diagnostic only: reinterpret signed BC5 normal maps as unsigned.
        $chosen['LARECOMP_BC5_UNORM'] = '1'
    }
    'Depth32' {
        # Diagnostic only: use D32S8 instead of D24S8 on capable GPUs.
        $chosen['LARECOMP_VK_D24'] = '0'
    }
}
try {
    foreach ($name in $vars) {
        $value = if ($chosen.ContainsKey($name)) { $chosen[$name] } else { $null }
        [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    }
    Write-Output "Violet graphics test: $Mode"
    Write-Output 'Compare the SAME scene with the baseline screenshots, especially Eevee and the bedroom.'
    if ($Mode -eq 'ConservativeUploads') {
        Write-Warning 'ConservativeUploads can be much slower than normal. This is only a diagnostic.'
    }
    if ($chosen.Count -eq 0) { Write-Output 'Overrides: none (normal texture paths)' }
    foreach ($name in @($chosen.Keys | Sort-Object)) { Write-Output ("Override: {0}={1}" -f $name, $chosen[$name]) }
    if ($DryRun) { return }
    $launcher = Join-Path $PSScriptRoot 'run.ps1'
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
        throw "Violet native launcher is missing: $launcher"
    }
    # -RebuildRuntime refreshes source once when needed. The game packages
    # are untouched; the separate crash log remains under build/violet-launch-logs.
    & $launcher -Play -RebuildRuntime -CaptureCrash
} finally {
    foreach ($name in $vars) {
        [Environment]::SetEnvironmentVariable($name, $old[$name], 'Process')
    }
}
