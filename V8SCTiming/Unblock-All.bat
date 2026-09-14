@echo off
REM Removes the Windows "downloaded from the internet" block from every file
REM in publish\ (this is what causes "Access is denied" when double-clicking
REM or running the .exe after unzipping a downloaded copy of this folder).
REM Run this once after copying/unzipping the project onto a new machine.

setlocal
set SCRIPT_DIR=%~dp0

echo Unblocking all files under %SCRIPT_DIR%publish ...
powershell -NoProfile -Command "Get-ChildItem -Path '%SCRIPT_DIR%publish' -Recurse | Unblock-File"
echo Done.
pause
