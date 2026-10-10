@echo off
REM ============================================================
REM  Preflight check: env -> build -> run -> verify
REM  Wrapper for tools/preflight.py (double-click friendly).
REM  ASCII only on purpose (avoid Windows codepage issues).
REM ============================================================
setlocal
cd /d "%~dp0.."

set "PY="
where python >nul 2>nul && set "PY=python"
if not defined PY (
  where py >nul 2>nul && set "PY=py"
)
if not defined PY (
  echo [ERROR] Python 3 not found. Please install Python 3 and retry.
  echo         https://www.python.org/downloads/
  pause
  exit /b 2
)

echo Running preflight check (env / build / run / verify) ...
echo.
%PY% "%~dp0preflight.py" %*
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
  echo [OK] Preflight PASSED - safe to deploy.
) else (
  echo [FAIL] Preflight found problems. See the list above.
)
pause
exit /b %RC%
