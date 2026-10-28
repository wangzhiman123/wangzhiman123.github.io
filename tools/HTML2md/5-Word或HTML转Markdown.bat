@echo off
rem ======================================================================
rem  Word (.docx) / HTML (.html .htm)  ->  blog Markdown converter  --  launcher
rem
rem  Why this file is pure English/ASCII:
rem  cmd.exe misreads UTF-8 batch files and turns Chinese into garbage.
rem  So every Chinese message is printed by PowerShell (word2md.ps1),
rem  never by this file. Keep it ASCII, keep it CRLF.
rem
rem  Three ways to use:
rem    1. Double-click this file, then drag a .docx / .html into the window.
rem    2. Drag files directly onto this file's icon.
rem    3. Drag a whole folder (it takes every .docx / .html inside).
rem ======================================================================
setlocal
rem Find the folder this bat lives in, and hand it to the script with -Root.
rem The script must never guess where it is: guessing is what broke it when
rem launched from a shortcut or from C:\Windows\System32.
rem
rem In the blog this folder is <blog>\tools, so the script climbs one level
rem and finds _config.yml -> writes straight into _posts.
rem Copied anywhere else, no _config.yml is found -> portable mode: the md
rem files land in the "output" subfolder next to this file. Both work.
pushd "%~dp0" 2>nul
if errorlevel 1 goto missing
set "TOOLS=%CD%"
popd
set "PS1=%TOOLS%\word2md.ps1"

if not exist "%PS1%" goto missing

if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Root "%TOOLS%"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Root "%TOOLS%" %*
)

echo.
pause
endlocal
exit /b 0

:missing
echo.
echo  [ERROR] word2md.ps1 was not found next to this file.
echo          Keep all the tool files together in the same folder.
echo.
pause
exit /b 1
