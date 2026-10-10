@echo off
setlocal
title Windows Cleanup Helper
pushd "%~dp0"

if not exist "windows-cleanup.ps1" (
  echo [ERROR] windows-cleanup.ps1 not found in the same folder.
  echo Keep this file next to windows-cleanup.ps1
  pause
  exit /b 1
)

:menu
cls
echo.
echo  ==========================================================
echo     Windows Cleanup Helper
echo  ==========================================================
echo.
echo   [1] Scan only            - show what can be cleaned (no deletion)
echo   [2] Quick clean          - delete 100%% junk (caches, temp files)
echo   [3] Deep clean           - also delete regenerable caches
echo   [4] Admin deep clean     - include system items (UAC prompt)
echo   [5] Drive scan           - read-only report, any drive (no deletion)
echo   [0] Exit
echo.
choice /c 123450 /n /m "  Choose 1/2/3/4/5/0: "
if errorlevel 6 goto exit
if errorlevel 5 goto drivescan
if errorlevel 4 goto admin
if errorlevel 3 goto deep
if errorlevel 2 goto quick
if errorlevel 1 goto scan

:scan
echo.
echo [Scan only - nothing will be deleted...]
powershell -NoProfile -ExecutionPolicy Bypass -File "windows-cleanup.ps1" -Scan
echo.
pause
goto menu

:quick
echo.
echo [Quick clean - deleting 100%% junk...]
powershell -NoProfile -ExecutionPolicy Bypass -File "windows-cleanup.ps1" -Clean
echo.
pause
goto menu

:deep
echo.
echo [Deep clean - deleting junk and regenerable caches...]
powershell -NoProfile -ExecutionPolicy Bypass -File "windows-cleanup.ps1" -Clean -Yes
echo.
pause
goto menu

:admin
echo.
echo [Admin deep clean - requesting administrator privileges...]
echo If a UAC prompt appears, click Yes.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList '-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File','""%~dp0windows-cleanup.ps1""','-Clean','-Yes'"
echo.
echo Admin window launched. If nothing appeared, right-click this file and choose "Run as administrator".
pause
goto menu

:drivescan
echo.
echo [Drive scan - read-only, nothing will be deleted]
set "DRIVE="
set /p "DRIVE=  Drive letter (C/D/E...), empty = both C and D: "
set "DRIVE=%DRIVE::=%"
python -c "import sys" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Python not found in PATH. Run scan-drive.py manually instead.
  pause
  goto menu
)
if "%DRIVE%"=="" (
  python "scan-drive.py" C: --min-mb 200
  python "scan-drive.py" D: --min-mb 200
) else (
  python "scan-drive.py" "%DRIVE%:" --min-mb 200
)
echo.
pause
goto menu

:exit
echo Bye
endlocal
exit /b 0
