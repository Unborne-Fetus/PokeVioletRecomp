@echo off
setlocal
pushd "%~dp0" || exit /b 1

if not exist "build\violet-gnu\lasrecomp.exe" goto :missing_runtime
if not exist "build\violet-gnu\lasgame.dll" goto :missing_game
if not exist "build\msys-deps\ucrt64\bin" goto :missing_dependencies
if not exist "extracted\exefs\main" goto :missing_extraction
if not exist "extracted\exefs\subsdk0" goto :missing_extraction
if not exist "extracted\exefs\sdk" goto :missing_extraction
if not exist "extracted\exefs\main.npdm" goto :missing_extraction
if not exist "extracted\romfs.bin" goto :missing_extraction

set "PATH=%CD%\build\msys-deps\ucrt64\bin;%PATH%"
echo Starting Pokemon Violet from the existing native build...
echo Game data: "%CD%\extracted"
"build\violet-gnu\lasrecomp.exe" "%CD%\extracted" --play
if errorlevel 1 goto :game_error
popd
exit /b 0

:missing_runtime
echo Missing native executable. Run tools\violet\build.ps1 -Game.
goto :failure
:missing_game
echo Missing lasgame.dll. Run tools\violet\build.ps1 -Game.
goto :failure
:missing_dependencies
echo Missing private runtime DLL dependencies under build\msys-deps\ucrt64\bin.
goto :failure
:missing_extraction
echo Missing extracted game files. Prepare your own Violet game files with tools\violet\prepare.ps1.
goto :failure
:game_error
echo.
echo Violet exited with an error. The native program is launchable but game startup may still abort.
echo To diagnose, run tools\violet\test_boot.ps1 in PowerShell and check the generated boot-summary.json.
:failure
echo.
pause
popd
exit /b 1
