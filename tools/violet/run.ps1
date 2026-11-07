# Run Violet from this checkout with its extracted game directory and private dependency DLLs.
# -Play skips the import/start screen; without it, the player sees the launcher.
[CmdletBinding()]
param([switch]$Play, [switch]$OpenControls, [switch]$CheckOnly, [switch]$RebuildRuntime, [switch]$CaptureCrash)
if ($Play -and $OpenControls) { throw 'Choose either -Play or -OpenControls, not both.' }
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exe = Join-Path $root 'build\violet-gnu\lasrecomp.exe'
$gameDll = Join-Path $root 'build\violet-gnu\lasgame.dll'
$gameRoot = Join-Path $root 'extracted'
$exefs = Join-Path $gameRoot 'exefs'
$depDir = Join-Path $root 'build\msys-deps\ucrt64\bin'

if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "Violet's native executable is missing: $exe. Run .\tools\violet\build.ps1 -Game."
}
if (-not (Test-Path -LiteralPath $depDir -PathType Container)) {
    throw "The runtime DLL directory is missing: $depDir. Restore the private build dependencies."
}
if ($Play -or $OpenControls -or $CheckOnly) {
    $required = @(
        (Join-Path $exefs 'main'),
        (Join-Path $exefs 'subsdk0'),
        (Join-Path $exefs 'sdk'),
        (Join-Path $exefs 'main.npdm'),
        (Join-Path $gameRoot 'romfs.bin'),
        $gameDll
    )
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missing.Count) {
        throw ("Violet is not prepared to launch. Missing files:`n  " + ($missing -join "`n  ") +
            "`nPrepare your own game with .\tools\violet\prepare.ps1 -Generate and build with .\tools\violet\build.ps1 -Game.")
    }
}
if ($CheckOnly) {
    Write-Host 'Violet launch inputs present. This does not prove that guest startup succeeds.'
    Write-Host "Game data: $gameRoot"
    Write-Host "Runtime: $exe"
    return
}

$oldPath = $env:PATH
$oldOpenControls = $env:VIOLET_LAUNCHER_OPEN_CONTROLS
$oldBadLayout = [Environment]::GetEnvironmentVariable('LARECOMP_SKIP_BAD_LAYOUT', 'Process')
Push-Location $root
try {
    $env:PATH = $depDir + ';' + $env:PATH
    # For Violet, a missing vertex attribute is already bound to (0,0,0,1)
    # via ZERO_BINDING in vulkan/exec.c. The older Z-A workaround that drops
    # those draws creates missing floors/walls in Violet. Apply this only to
    # the Violet launcher, and honor any explicit developer override.
    if ($null -eq $oldBadLayout) {
        [Environment]::SetEnvironmentVariable('LARECOMP_SKIP_BAD_LAYOUT', '0', 'Process')
        Write-Host 'Violet vertex compatibility: using constant defaults for missing attributes.'
    }
    if ($OpenControls) { $env:VIOLET_LAUNCHER_OPEN_CONTROLS = '1' }
    else { Remove-Item Env:VIOLET_LAUNCHER_OPEN_CONTROLS -ErrorAction SilentlyContinue }
    if ($RebuildRuntime) {
        # The native .exe contains the HLE service fixes. Merely pulling those source files does NOT update it.
        # Rebuild only when the checkout revision or runtime sources have changed since the last successful refresh.
        $stamp = Join-Path $root 'build\violet-gnu\source-head.txt'
        $revision = ''
        $git = Get-Command git -ErrorAction SilentlyContinue
        if ($git) {
            $revOutput = & $git.Source -C $root rev-parse HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and $revOutput) { $revision = [string]($revOutput | Select-Object -First 1) }
        }
        $oldRevision = if (Test-Path -LiteralPath $stamp) {
            (Get-Content -LiteralPath $stamp -Raw).Trim()
        } else { '' }
        $sources = @('runtime\kernel.c', 'runtime\services\am.c', 'runtime\services\bluetooth.c',
                     'runtime\ipc.c', 'runtime\main.c', 'runtime\gamelib.c')
        $exeTime = (Get-Item -LiteralPath $exe).LastWriteTimeUtc
        $newerSources = @($sources | ForEach-Object {
            $sourceFile = Join-Path $root $_
            if (Test-Path -LiteralPath $sourceFile) {
                (Get-Item -LiteralPath $sourceFile).LastWriteTimeUtc -gt $exeTime
            }
        } | Where-Object { $_ }).Count -gt 0
        # A new commit containing only tests, docs or log tooling should not
        # rebuild the large native runtime. Preserve the exact EXE/PDB pairing
        # so a previously captured fault can still be symbolicated reliably.
        $rebuild = $newerSources -or -not $revision -or -not $oldRevision
        if ($git -and $revision -and $oldRevision -and $revision -ne $oldRevision) {
            $buildInputs = @('runtime', 'Makefile', 'tools/gen.py', 'tools/gamelib_entry.c',
                             'tools/violet/build.ps1', 'tools/violet/build_config.py',
                             'tools/violet/make_local.sh')
            $changed = @(& $git.Source -C $root diff --name-only $oldRevision $revision -- $buildInputs)
            if ($LASTEXITCODE -ne 0 -or $changed.Count -gt 0) { $rebuild = $true }
        }
        if ($rebuild) {
            $build = Join-Path $PSScriptRoot 'build.ps1'
            if (-not (Test-Path -LiteralPath $build)) {
                throw "The source checkout is too old to rebuild Violet. Update the pokemon-za checkout before retrying."
            }
            Write-Host 'Refreshing native Violet runtime to include boot fixes...'
            & $build
            if (-not (Test-Path -LiteralPath $exe)) { throw 'Runtime rebuild did not produce an executable.' }
        }
        if ($revision) { [IO.File]::WriteAllText($stamp, $revision + "`n") }
    }
    # The runtime changes its working directory to the user data root: always give it an absolute game path.
    $argString = '"' + $gameRoot + '"' + $(if ($Play) { ' --play' } else { '' })
    if ($CaptureCrash) {
        # Distinct logs: do not touch player saves, existing crash reports or old diagnostic sessions.
        $dir = Join-Path $root 'build\violet-launch-logs'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $attempt = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss-fffffff')
        $out = Join-Path $dir "$attempt-stdout.log"
        $err = Join-Path $dir "$attempt-stderr.log"
        Write-Host "Launching Violet; crash log: $err"
        $process = Start-Process -FilePath $exe -ArgumentList $argString -WorkingDirectory $root `
            -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $triage = Join-Path $PSScriptRoot 'boot_triage.py'
        $python = Get-Command python -ErrorAction SilentlyContinue
        if ($python -and (Test-Path -LiteralPath $triage) -and (Test-Path -LiteralPath $err)) {
            & $python.Source $triage $err --json (Join-Path $dir "$attempt-summary.json")
        }
        if ($exitCode -ne 0) {
            Write-Host "Violet exited with code $exitCode; last diagnostic lines:"
            if (Test-Path -LiteralPath $err) { Get-Content -LiteralPath $err -Tail 35 }
            # Symbolize the *same* EXE that just crashed. This works with Zig/MinGW PE
            # exports even when the PDB has no usable DbgHelp/CodeView records.
            # It must never mask the original error or trigger another rebuild.
            $symbolizer = Join-Path $PSScriptRoot 'addr2line_crash.py'
            if ($python -and (Test-Path -LiteralPath $symbolizer -PathType Leaf) -and (Test-Path -LiteralPath $err -PathType Leaf)) {
                $symbolPath = Join-Path $dir "$attempt-symbols.log"
                try {
                    $symbolLines = @(& $python.Source $symbolizer --log $err --exe $exe 2>&1)
                    $symbolLines | Set-Content -LiteralPath $symbolPath -Encoding UTF8
                    Write-Host "Native crash symbol candidates saved at: $symbolPath"
                    $symbolLines | ForEach-Object { Write-Host $_ }
                } catch {
                    Write-Warning ("Could not symbolize the native crash: " + $_.Exception.Message)
                }
            }
            throw "Native launch or guest boot failed. Send the log at $err to diagnose the next blocker."
        }
    } else {
        $runArgs = @($gameRoot)
        if ($Play) { $runArgs += '--play' }
        & $exe @runArgs
        if ($LASTEXITCODE) { throw "Violet Recomp exited with code $LASTEXITCODE. Use -CaptureCrash to save logs." }
    }
} finally {
    $env:PATH = $oldPath
    [Environment]::SetEnvironmentVariable('LARECOMP_SKIP_BAD_LAYOUT', $oldBadLayout, 'Process')
    if ($null -ne $oldOpenControls) { $env:VIOLET_LAUNCHER_OPEN_CONTROLS = $oldOpenControls }
    else { Remove-Item Env:VIOLET_LAUNCHER_OPEN_CONTROLS -ErrorAction SilentlyContinue }
    Pop-Location
}
