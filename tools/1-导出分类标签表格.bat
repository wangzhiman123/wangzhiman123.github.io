@echo off
chcp 65001 >nul
cd /d "%~dp0.."
echo.
echo ==========================================
echo   第 1 步：导出分类标签表格
echo ==========================================
echo.
set "PY=C:\Users\13202\.workbuddy\binaries\python\versions\3.13.12\python.exe"
if not exist "%PY%" set "PY=python"
"%PY%" "scripts\export_tags_table.py"
echo.
echo 表格位置：tools\文章分类标签表.csv
echo 用 Excel 或 WPS 打开即可编辑。
echo.
pause
