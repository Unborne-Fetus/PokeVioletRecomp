# Controlled guest runs. A run's settings, saves, screenshots and logs stay in its own directory.
[CmdletBinding()]
param(
    [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$Name = 'boot',
    [ValidateRange(1, 300)][int]$Seconds = 30,
    [string]$InputScript,
    [string]$Shots = '1,30,120',
    [switch]$Launcher
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$data = Join-Path $root ('build\violet-tests\' + $Name)
New-Item -ItemType Directory -Force -Path $data | Out-Null
$names = @('PATH','LARECOMP_DATA_ROOT','LARECOMP_SETTINGS','LARECOMP_NO_UPDATE_CHECK','LARECOMP_NO_USER_INPUT',
    'LARECOMP_NO_LAUNCHER','LARECOMP_SHOT_AT','LARECOMP_INPUT','LARECOMP_FORCE_LAUNCHER',
    'LARECOMP_LAUNCHER_SHOT','LARECOMP_SHOT_PATH')
$saved = @{}
foreach ($key in $names) { $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
try {
    $env:PATH = (Join-Path $root 'build\msys-deps\ucrt64\bin') + ';' + $env:PATH
    $env:LARECOMP_DATA_ROOT = $data
    $env:LARECOMP_SETTINGS = Join-Path $data 'larecomp.ini'
    $env:LARECOMP_NO_UPDATE_CHECK = '1'
    $env:LARECOMP_NO_USER_INPUT = '1'
    $env:LARECOMP_NO_LAUNCHER = '1'
    $env:LARECOMP_SHOT_AT = $Shots
    $env:LARECOMP_INPUT = $InputScript
    $env:LARECOMP_FORCE_LAUNCHER = $null
    $env:LARECOMP_LAUNCHER_SHOT = $null
    $env:LARECOMP_SHOT_PATH = $null
    $arguments = '"' + (Join-Path $root 'extracted') + '" --play'
    if ($Launcher) {
        $env:LARECOMP_NO_LAUNCHER = $null
        $env:LARECOMP_FORCE_LAUNCHER = '1'
        $env:LARECOMP_LAUNCHER_SHOT = '5:en'
        $env:LARECOMP_SHOT_PATH = Join-Path $data 'launcher.png'
        $arguments = '"' + (Join-Path $root 'extracted') + '"'
    }
    $process = Start-Process -FilePath (Join-Path $root 'build\violet-gnu\lasrecomp.exe') -ArgumentList $arguments `
        -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $data 'stdout.log') `
        -RedirectStandardError (Join-Path $data 'stderr.log') -PassThru
    $timedOut = -not $process.WaitForExit($Seconds * 1000)
    if ($timedOut) { $process.Kill(); $process.WaitForExit() }
    Write-Output ("Test {0}: exit {1}, reached time limit {2}; data {3}" -f $Name, $process.ExitCode, $timedOut, $data)
    Get-Content -LiteralPath (Join-Path $data 'stderr.log') -Tail 35
} finally {
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
}
