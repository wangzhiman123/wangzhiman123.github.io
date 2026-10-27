@echo off
chcp 65001 >nul
cd /d "%~dp0.."
echo.
echo ==========================================
echo   更新图标字体（字体瘦身）
echo ==========================================
echo.
echo 什么时候需要运行它：
echo   在文章或模板里新用了一个图标，页面上却显示成空白方块/框框，
echo   说明这个图标没被收进"精简字体"。运行一次即可补齐。
echo.
echo 这个工具会自动：
echo   1. 扫描全站，找出实际用到的所有图标
echo   2. 只把这些图标从完整字体里抠出来
echo   3. 顺手精简图标样式表
echo.
set "PY=C:\Users\13202\.workbuddy\binaries\python\versions\3.13.12\python.exe"
if not exist "%PY%" set "PY=python"
"%PY%" "scripts\update_icon_font.py"
if errorlevel 1 (
    echo.
    echo 【出错了】请把上面这段红字/英文报错发给助手看看。
    echo.
    pause
    exit /b 1
)
echo.
echo 完成。接下来在 deploy.bat 里提交推送，等 GitHub 构建完就生效。
echo.
pause
