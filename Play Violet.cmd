@echo off
setlocal
pushd "%~dp0" || exit /b 1
echo Pokemon Violet - native Windows launch
echo.
if not exist "tools\violet\run.ps1" goto :old_checkout
if not exist "tools\violet\build.ps1" goto :old_checkout
set "BRANCH="
for /f "delims=" %%B in ('git branch --show-current 2^>nul') do set "BRANCH=%%B"
if defined BRANCH if /I not "%BRANCH%"=="pokemon-za" (
    echo WARNING: this checkout is on %BRANCH% instead of pokemon-za.
    echo          Latest boot fixes may not exist here.
)
echo Checking and rebuilding changed native runtime files before launching...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\violet\run.ps1" -Play -RebuildRuntime -CaptureCrash
set "EXIT=%ERRORLEVEL%"
if not "%EXIT%"=="0" goto :failure
popd
exit /b 0
:old_checkout
echo This is an old checkout without Violet's development scripts.
echo Switch to the latest pokemon-za checkout; do not run an older Violet executable.
goto :failure
:failure
echo.
echo The game did not start successfully. Scroll up for the error or inspect:
echo   build\violet-launch-logs\*-stderr.log
echo If the game aborts, send the newest stderr log so the actual cause can be fixed.
pause
popd
exit /b 1
