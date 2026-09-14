@echo off
REM Starts the V8SC Timing Logger — the always-on background process that
REM connects to a timing feed and records everything to the shared SQLite DB.
REM
REM Usage:
REM   Start-Logger.bat                 (defaults to the "replay" profile)
REM   Start-Logger.bat supercars-live   (connect to the live Supercars TCP feed)
REM   Start-Logger.bat openf1-live      (connect to the OpenF1 API)
REM
REM Edit config\profiles.json to set host/port/filePath for each profile.

setlocal
set SCRIPT_DIR=%~dp0
set PROFILE=%1
if "%PROFILE%"=="" set PROFILE=replay

echo Unblocking executable (removes Windows "downloaded file" restriction)...
powershell -NoProfile -Command "Get-ChildItem -Path '%SCRIPT_DIR%publish' -Recurse | Unblock-File" >nul 2>&1

echo Starting V8SC Timing Logger with profile "%PROFILE%"...
echo Database: %SCRIPT_DIR%v8sctiming.db
echo Press Ctrl+C to stop.
echo.

"%SCRIPT_DIR%publish\Logger\V8SCTiming.Logger.exe" %PROFILE% "%SCRIPT_DIR%config" "%SCRIPT_DIR%v8sctiming.db"

pause
