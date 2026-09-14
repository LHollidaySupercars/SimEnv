@echo off
REM Starts the V8SC Timing Viewer — the WPF app you look at.
REM It reads live from the same v8sctiming.db that the Logger writes to.
REM Safe to start/stop independently of the Logger.

setlocal
set SCRIPT_DIR=%~dp0

echo Unblocking executable (removes Windows "downloaded file" restriction)...
powershell -NoProfile -Command "Get-ChildItem -Path '%SCRIPT_DIR%publish' -Recurse | Unblock-File" >nul 2>&1

echo Starting V8SC Timing Viewer...
start "" "%SCRIPT_DIR%publish\Viewer\V8SCTiming.Viewer.exe"
