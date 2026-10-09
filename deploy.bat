@echo off
setlocal
cd /d "%~dp0"
title Deploy Blog - wangzhiman123.github.io

echo.
echo ============================================================
echo   Blog one-click deploy  (double-click this file)
echo ============================================================
echo.

where powershell >nul 2>&1
if errorlevel 1 (
    echo [ERROR] PowerShell not found on this computer.
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" %*

echo.
echo ------------------------------------------------------------
echo   Finished. Press any key to close this window.
echo ------------------------------------------------------------
pause >nul
endlocal
