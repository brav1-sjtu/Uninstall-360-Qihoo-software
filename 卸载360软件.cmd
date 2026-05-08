@echo off
setlocal

set "SCRIPT=%~dp0Remove-360-Software.ps1"

if not exist "%SCRIPT%" (
    echo Missing script:
    echo "%SCRIPT%"
    echo.
    echo Keep Uninstall-360.cmd and Remove-360-Software.ps1 in the same folder.
    pause
    exit /b 1
)

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo Requesting administrator permission...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

echo Starting 360/Qihoo software removal...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Run
set "CODE=%ERRORLEVEL%"

echo.
echo Finished with exit code %CODE%.
echo You can close this window after reviewing the output.
pause
exit /b %CODE%
