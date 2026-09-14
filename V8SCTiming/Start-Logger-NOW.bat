@echo off
REM Quick-start: unblock + launch the Logger against supercars-live, right now.
setlocal
set SCRIPT_DIR=%~dp0

echo Unblocking all files (removes Windows download-block)...
powershell -NoProfile -Command "Get-ChildItem -Path '%SCRIPT_DIR%publish' -Recurse | Unblock-File" >nul 2>&1

echo Starting Logger with profile "supercars-live"...
echo Database: %SCRIPT_DIR%v8sctiming.db
echo.

"%SCRIPT_DIR%publish\Logger\V8SCTiming.Logger.exe" supercars-live "%SCRIPT_DIR%config" "%SCRIPT_DIR%v8sctiming.db"

echo.
echo Logger stopped (or failed to start - see message above).
pause
