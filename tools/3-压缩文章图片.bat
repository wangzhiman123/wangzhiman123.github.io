@echo off
rem ==========================================================
rem  Image compressor launcher.
rem  Keep this file pure ASCII with CRLF line endings -
rem  cmd.exe misparses UTF-8/LF batch files. All Chinese
rem  output is printed by Python, not by this script.
rem ==========================================================
setlocal
set "ROOT=%~dp0.."
set "PY=C:\Users\13202\.workbuddy\binaries\python\versions\3.13.12\python.exe"
if not exist "%PY%" set "PY=python"
cd /d "%ROOT%"
"%PY%" "%ROOT%\scripts\optimize_remote_images.py" %*
echo.
pause
endlocal
