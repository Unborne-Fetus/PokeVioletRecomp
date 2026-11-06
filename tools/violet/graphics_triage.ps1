# Compare Violet renderer paths without altering the working default, saves, or settings.
# A single run uses temporary environment variables, restored on exit.
[CmdletBinding()]
param(
    [ValidateSet('Baseline', 'PackagedZero', 'ConservativeUploads', 'BC5Unsigned', 'Depth32', 'ShadowCompareOff', 'ShaderQuadDerivatives', 'ShaderQuadControl', 'DepthEqualTolerance', 'NoDepthTest')]
    [string]$Mode = 'Baseline',
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
    'LARECOMP_VK_D24',
    'LARECOMP_NO_SHADOW',
    'LARECOMP_SHADER_QUAD_DERIV',
    'LARECOMP_SHADER_QUAD_CONTROL',
    'LARECOMP_VK_EQUAL_TOL',
    'LARECOMP_NO_DEPTH_TEST'
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
    'ShadowCompareOff' {
        # Diagnostic for diagonal surface striping: the Vulkan sampler keeps
        # comparison enabled but tests ALWAYS instead of reading the shadow
        # depth value. If diagonal stripes disappear, investigate shadow acne,
        # depth bias, and comparison reference values. This is not a final fix.
        $chosen['LARECOMP_NO_SHADOW'] = '1'
    }
    'ShaderQuadDerivatives' {
        # NVIDIA normally uses subgroup quad swaps for the Switch game's
        # SHFL -> FSWZADD derivatives. Pixel-sized stripes can result when a
        # fragment's quad partners have diverged or are helper invocations.
        # Force dFdxFine/dFdyFine recovery and disable quad control for this
        # comparison. The translator caches this variant under a different key.
        $chosen['LARECOMP_SHADER_QUAD_DERIV'] = '1'
        $chosen['LARECOMP_SHADER_QUAD_CONTROL'] = '0'
    }
    'ShaderQuadControl' {
        # If VK_KHR_shader_quad_control and maximal reconvergence are present,
        # keep full 2x2 pixel quads participating in shader branches/loops.
        # Hardware without those extensions safely ignores this request.
        $chosen['LARECOMP_SHADER_QUAD_CONTROL'] = '1'
        $chosen['LARECOMP_SHADER_QUAD_DERIV'] = '0'
    }
    'DepthEqualTolerance' {
        # Existing renderer workaround (exec.c fixed_state): a depth pre-pass
        # rendered by a different vertex shader can differ by a few ULPs from
        # its equal-depth color pass, causing thin black slash patterns.
        # Compare LESS_OR_EQUAL with a small near-camera bias for EQUAL draws.
        $chosen['LARECOMP_VK_EQUAL_TOL'] = '1'
    }
    'NoDepthTest' {
        # This is a diagnosis, NOT a rendering fix. No occlusion is guaranteed;
        # surfaces may appear in front of one another incorrectly. If the
        # striped pattern remains, the source likely lies outside depth testing.
        $chosen['LARECOMP_NO_DEPTH_TEST'] = '1'
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
    if ($Mode -eq 'ShadowCompareOff') {
        Write-Warning 'Shadow depth comparisons are bypassed in this diagnostic; lighting may look too bright.'
    }
    if ($Mode -eq 'DepthEqualTolerance') {
        Write-Output 'Testing depth pre-pass EQUAL tolerance for thin black slashes; no permanent shader or setting changes.'
    }
    if ($Mode -eq 'NoDepthTest') {
        Write-Warning 'Depth testing is bypassed for this diagnostic, so occlusion will be incorrect. Do not save while testing.'
    }
    if ($Mode -eq 'ShaderQuadDerivatives' -or $Mode -eq 'ShaderQuadControl') {
        Write-Output 'Shader variant may compile new GLSL/SPIR-V pipelines. Normal graphics are restored on the next launch.'
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
