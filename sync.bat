@echo off
REM ============================================================
REM 【本文件是什么？】
REM  sync.bat —— 双击就能用的"一键同步到本地"工具
REM
REM  一句话概括：当网站上（GitHub）的代码是最新的，双击本文件，
REM           就会自动把线上最新代码拉取回你的电脑，本地文件就跟线
REM           上一致了。
REM
REM  它和 deploy.bat（一键发布）有什么区别？
REM   deploy.bat        方向是 本地 → 线上：把你电脑的改动传到网站上。
REM   sync.bat（本文件）方向是 线上 → 本地：把网站上的最新代码取回
REM                    自己电脑。
REM  简单记：发布用 deploy.bat，同步用 sync.bat。
REM
REM  安全提醒（放心）：
REM    1. 同步前会自动备份被覆盖的文件，出问题可从备份里找回。
REM    2. 如果某个文件"你本地改过、线上也改了"，它会停下来问你，
REM       不会静默吞掉你的改动。
REM    3. 它只"读线上 + 写本地"，不会提交、也不会修改线上代码。
REM
REM  怎么用（三步）：
REM    1. 双击本文件。
REM    2. 运行过程中若弹出选择提示，按屏幕说明输入即可
REM       （直接回车就是选用线上版本）。
REM    3. 看到 "Finished" 就完成了。
REM ============================================================

REM 关闭命令回显，让打印出来的提示更干净。
setlocal

REM 切到本文件所在的项目目录：这样才能保证找到同目录下的 deploy.ps1。
cd /d "%~dp0"
REM %~dp0 是"本文件完整路径"；/d 表示"连所在驱动盘也一起切换"。
title Sync Blog - wangzhiman123.github.io
REM 设置窗口标题的文字，一眼就能看出这是做什么的（可自行修改）。

echo.
echo ============================================================
echo   Blog sync to local  (double-click this file)
echo ============================================================
echo.

where powershell >nul 2>&1
REM 先检查电脑有没有 PowerShell。
REM where 是"查找命令"；>nul 2>&1 表示"查找结果不要显示出来"。
if errorlevel 1 goto nops

REM 关键一行：让 PowerShell 执行 deploy.ps1，并带上 -Pull（拉取方向）。
REM   -NoProfile               不加载个人配置，避免被环境干扰。
REM   -ExecutionPolicy Bypass  临时放行脚本执行，这就是让你靠 .bat 双击的原因。
REM   -File "deploy.ps1"       指定要运行的脚本。
REM   -Pull                    把线上最新代码拉回本地。
REM   %*                       你在本 bat 后面额外加的参数会原样传进去；
REM                            例如 sync.bat -Force 会传成 -Pull -Force。
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" -Pull %*
REM 想不备份就加 -NoBackup，想冲突一律用线上版就加 -Force。
REM 例： sync.bat -NoBackup    或    sync.bat -Force
goto end

:nops
echo [ERROR] PowerShell not found on this computer.
echo.
pause
exit /b 1

:end
echo.
echo ------------------------------------------------------------
echo   Finished. Press any key to close this window.
echo ------------------------------------------------------------
pause >nul
endlocal
