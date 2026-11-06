@echo off
setlocal
pushd "%~dp0" || exit /b 1
echo Pokemon Violet - native Windows launch
echo.
if not exist "tools\violet\run.ps1" goto :old_checkout
if not exist "tools\violet\build.ps1" goto :old_checkout
if exist ".git\rebase-merge" goto :conflicted
if exist ".git\rebase-apply" goto :conflicted
set "CONFLICT="
for /f "delims=" %%F in ('git diff --name-only --diff-filter=U 2^>nul') do set "CONFLICT=1"
if defined CONFLICT goto :conflicted
set "BRANCH="
for /f "delims=" %%B in ('git branch --show-current 2^>nul') do set "BRANCH=%%B"
if /I not "%BRANCH%"=="pokemon-za" goto :wrong_branch
if not exist "tools\violet\startup_menu.ps1" goto :old_checkout
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0tools\violet\startup_menu.ps1"
set "MENU_CHOICE=%ERRORLEVEL%"
if "%MENU_CHOICE%"=="0" goto :launch_play
if "%MENU_CHOICE%"=="2" goto :launch_controls
if "%MENU_CHOICE%"=="3" goto :cancelled
echo Startup menu could not open. Exit code: %MENU_CHOICE%
goto :failure
:launch_play
echo Checking native runtime before launching Violet...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\violet\run.ps1" -Play -RebuildRuntime -CaptureCrash
set "EXIT=%ERRORLEVEL%"
goto :launched
:launch_controls
echo Opening the native Controls editor. Choose Configure inputs to rebind, then return to Play.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\violet\run.ps1" -OpenControls -RebuildRuntime -CaptureCrash
set "EXIT=%ERRORLEVEL%"
goto :launched
:launched
if not "%EXIT%"=="0" goto :failure
popd
exit /b 0
:cancelled
popd
exit /b 0
:old_checkout
echo This checkout does not include the latest Violet startup and development scripts.
echo Switch to the latest pokemon-za checkout; do not run an older Violet executable.
goto :failure
:conflicted
echo An unfinished Git rebase or merge is in progress.
echo Do not compile or run from a checkout with unresolved conflicts.
echo Run: git rebase --abort
echo Then switch to the up-to-date pokemon-za branch.
goto :failure
:wrong_branch
echo Current branch: %BRANCH%
echo This launcher requires pokemon-za. It will not rebuild from an older branch.
echo Finish or abort any rebase, then switch to the updated pokemon-za checkout.
goto :failure
:failure
echo.
echo The game did not start successfully. Scroll up for the error or inspect:
echo   build\violet-launch-logs\*-stderr.log
echo If the game aborts, send the newest stderr log so the actual cause can be fixed.
pause
popd
exit /b 1
