@echo off
setlocal
cd /d "%~dp0"
echo Starting Pokemon Violet Recomp from this checkout...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\violet\run.ps1" -Play
if errorlevel 1 (
    echo.
    echo Violet did not start successfully. The game may still have a guest boot error.
    echo To capture a scratch boot log: powershell -NoProfile -File "tools\violet\test_boot.ps1"
    echo.
    pause
    exit /b 1
)
endlocal
