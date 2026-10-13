@echo off
REM ============================================================
REM 【本文件是什么？】
REM  deploy.bat —— 双击就能用的"一键部署博客"入口
REM
REM  一句话概括：这是整个部署体系里"最傻瓜"的一个入口。
REM  您双击它，它就会启动根目录下的 deploy.ps1，
REM  由那个脚本帮您把网站发布到 GitHub（不需要在本机安装 Git）。
REM
REM  【它和 deploy/deploy-aliyun.bat 有什么区别？别搞混】
REM   · deploy.bat（就是本文件）—— 发布到 GitHub Pages，
REM       走的是 GitHub 的在线接口，本机不用装任何额外软件。
REM       适合"我就想更新网站、不想碰服务器"的情况。
REM   · deploy/deploy-aliyun.bat —— 用传文件的方式发布到您自己的阿里云服务器。
REM       适合"我想发布到自己买的服务器"的情况。
REM  两个都是双击即用，根据您想发布到哪里来选。
REM
REM  操作步骤（给代码小白）：
REM    1. 双击本文件
REM    2. 首次运行会提示您填写 GitHub 的访问令牌（按屏幕提示操作即可）
REM    3. 等它跑完，看到 "Finished" 就成功了
REM ============================================================

REM 关闭命令回显，不把命令本身也打印出来，界面更清爽。
setlocal

REM 开启局部环境，本文件里的设置改动不会残留到系统里。
cd /d "%~dp0"
REM 切换到本文件所在目录。%~dp0 是本文件的完整路径，/d 表示连盘符一起切换。
REM 【作用】保证后面能找到同目录下的 deploy.ps1。
title Deploy Blog - wangzhiman123.github.io
REM 设置这个黑色窗口顶部的标题文字，让您一眼看出这是哪个任务在运行。
REM 【可DIY修改】想改成中文也行，例如：title 一键部署博客

echo.
echo ============================================================
echo   Blog one-click deploy  (double-click this file)
echo ============================================================
echo.
REM 打印标题框，提示您"双击这个文件就能一键部署"。
REM echo. 表示输出一个空行。

where powershell >nul 2>&1
REM 检查这台电脑上有没有 PowerShell 这个工具。
REM where 是"查找命令在哪"；>nul 2>&1 表示"结果不要显示，我只看成功失败"。
if errorlevel 1 (
    echo [ERROR] PowerShell not found on this computer.
    echo.
    pause
    exit /b 1
)
REM 【防呆检查】如果找不到 PowerShell，就打印错误并停下来。
REM 【为什么需要？】因为接下来要依赖它执行脚本，
REM 没有的话后面必然失败，不如在这里就说清楚。
REM   errorlevel 1 是"上一条命令返回了失败状态"的意思；
REM   pause 让它停住，好让您看清错误信息；
REM   exit /b 1 是"以失败状态结束本文件"（1 表示出错）。
REM 【说明】Windows 10/11 都自带 PowerShell，正常情况下不会走到这里。

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" %*
REM 【核心的一行】启动 PowerShell 去执行真正干活的 deploy.ps1。
REM 参数说明：
REM   -NoProfile            不加载个人 PowerShell 配置，避免被本机设置干扰。
REM   -ExecutionPolicy Bypass  本次运行临时放行脚本执行限制
REM                         （这就是为什么必须靠 .bat 来双击启动）。
REM   -File "路径"          指定要运行哪个脚本。
REM   %*                    【很实用的一项】把您启动本 .bat 时携带的所有参数，
REM                         原样转交给 deploy.ps1 使用。
REM                         举例：您可以这样运行：
REM                             deploy.bat -DryRun
REM                         那么 -DryRun 就会被传给 deploy.ps1，
REM                         让它"先试跑一遍，不真正提交"。
REM                         通过它，您可以方便地用到 deploy.ps1 提供的各种功能。

echo.
echo ------------------------------------------------------------
echo   Finished. Press any key to close this window.
echo ------------------------------------------------------------
pause >nul
REM 打印结束提示，然后暂停窗口等您按键关闭。
REM pause >nul 后面的 >nul 是"不要把'请按任意键继续'那句系统提示也显示出来"，
REM 因为上面已经用中文说明了，这样界面更整洁。
REM 【为什么必须暂停？】否则窗口会一闪而过自动关闭，
REM 万一刚才报了错，您根本来不及看。
endlocal
REM 结束局部环境，与开头 setlocal 呼应。
