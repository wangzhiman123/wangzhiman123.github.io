@echo off
chcp 65001 >nul
cd /d "%~dp0.."
echo.
echo ==========================================
echo   第 2 步：把表格里的分类标签写回文章
echo ==========================================
echo.
set "PY=C:\Users\13202\.workbuddy\binaries\python\versions\3.13.12\python.exe"
if not exist "%PY%" set "PY=python"

echo 先做一次预演，只显示会改什么，不动任何文件...
echo.
"%PY%" "scripts\import_tags_table.py" --dry-run
echo.
set /p GO=确认无误请输入 Y 并回车，其它任意键取消：
if /i not "%GO%"=="Y" (
    echo 已取消，文章没有任何改动。
    echo.
    pause
    exit /b 0
)
echo.
echo 正在写入（会自动备份到 _backup\autosave-时间戳\）...
echo.
"%PY%" "scripts\import_tags_table.py"
echo.
pause
