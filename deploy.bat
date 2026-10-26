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
REM
REM  【当前默认设置 · 已按您的要求改好】
REM    双击本文件（不带任何参数）= 跳过"刷新浏览量" + 直接一键部署。
REM    也就是不会再去查询统计接口、不会重新生成浏览量数据，速度快很多。
REM
REM    如果您哪天想恢复"先刷新浏览量、再部署"的老流程，
REM    请不要双击，而是在本目录地址栏输入 cmd 回车，然后运行：
REM        deploy.bat -WithViews
REM    （这是本文件自己认的一个小开关，只影响 .bat，不传给 deploy.ps1。）
REM
REM    如果您自己带了别的参数（例如 deploy.bat -DryRun），
REM    本文件就不再自动加 -SkipViews，完全按您给的参数执行。
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

REM ============================================================
REM 【核心：按"有没有带参数"决定用哪套命令】
REM  · 没有带参数（也就是您双击）= 默认模式：自动加 -SkipViews，跳过刷新浏览量，直接部署。
REM  · 带了 -WithViews        = 老模式：照旧先刷新浏览量，再部署。
REM  · 带了别的参数            = 自定义模式：原样转发给 deploy.ps1，不额外加 -SkipViews。
REM ============================================================

if "%~1"=="" goto WB_DEFAULT
REM "%~1" 是您运行时携带的第一个参数（去掉首尾引号）。
REM 用 if "..."=="" 判断它是不是空的 —— 空就说明是双击，直接跳去默认模式。

if /i "%~1"=="-WithViews" goto WB_WITHVIEWS
REM /i 表示不区分大小写，所以 -withviews 也认。
REM 这是本文件自己造的小开关，只在这里被拦下来，不会传给 deploy.ps1。

goto WB_USERARGS
REM 都不是，就当作用户自带参数处理。

:WB_DEFAULT
echo   Mode: skip views refresh - deploy directly
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" -SkipViews
REM 【默认模式】-SkipViews = 跳过"刷新文章浏览量"这一步。
REM 效果：不查询统计接口、不生成 _data/views.json 与 _data/pv_state.json，直接进入部署。
set "WB_RC=%ERRORLEVEL%"
REM 把 powershell 的退出结果存起来（0 = 成功，非 0 = 出错）。
goto WB_SUMMARY

:WB_WITHVIEWS
echo   Mode: refresh views first, then deploy
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1"
REM 【老模式】不加 -SkipViews，deploy.ps1 会先刷新浏览量再部署。
set "WB_RC=%ERRORLEVEL%"
goto WB_SUMMARY

:WB_USERARGS
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" %*
REM 【自定义模式】%* = 您启动本 .bat 时携带的所有参数，原样转交给 deploy.ps1。
REM 举例：双击不了参数，所以在命令行里运行  deploy.bat -DryRun
REM 那么 -DryRun 就会被传给 deploy.ps1，让它"先试跑一遍，不真正提交"。
REM 这种情况下本文件不会偷偷加 -SkipViews，完全按您给的来。
set "WB_RC=%ERRORLEVEL%"

:WB_SUMMARY
echo.
echo ------------------------------------------------------------
if "%WB_RC%"=="0" (
    echo   Finished. Deploy succeeded.
) else (
    echo   Failed. Exit code = %WB_RC%
    echo   Please scroll up and read the red [ERROR] lines above.
)
echo   Press any key to close this window.
echo ------------------------------------------------------------
pause >nul
REM 根据退出码给一句明确的成功/失败提示，省得您自己去猜。
REM pause >nul 后面的 >nul 是"不要把'请按任意键继续'那句系统提示也显示出来"，
REM 因为上面已经用中文说明了，这样界面更整洁。
REM 【为什么必须暂停？】否则窗口会一闪而过自动关闭，
REM 万一刚才报了错，您根本来不及看。
endlocal & exit /b %WB_RC%
REM 结束局部环境，并把退出码继续传出去（与开头 setlocal 呼应）。
REM 注意：%WB_RC% 会在 endlocal 之前就被替换成实际数字，所以这样写是安全的。
