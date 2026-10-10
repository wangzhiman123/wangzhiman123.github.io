@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

echo ============================================================
echo   一键上传并发布到阿里云 ECS
echo ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy-aliyun.ps1"
set RC=%ERRORLEVEL%

echo.
if "%RC%"=="0" (
  echo [完成] 发布成功。
) else (
  echo [失败] 退出码 %RC% ，请查看上面的错误信息。
)
echo.
pause
endlocal
