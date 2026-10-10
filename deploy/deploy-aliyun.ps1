#Requires -Version 5.1
<#
================================================================
 deploy-aliyun.ps1 —— 本机（Windows）一键上传并发布到阿里云 ECS

 它做三件事：
   1) 把本机源码打包，通过 scp 传到服务器
   2) 在服务器上解包到源码目录（不动服务器上的浏览量数据）
   3) 在服务器上执行 publish.sh（构建 → 自检 → 原子切换）

 用法：双击同目录下的 deploy-aliyun.bat
      （或在本目录执行：powershell -ExecutionPolicy Bypass -File deploy-aliyun.ps1）
================================================================
#>

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Info($m) { Write-Host "`n▶ $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "✅ $m" -ForegroundColor Green }
function Die($m)  { Write-Host "❌ $m" -ForegroundColor Red; exit 1 }

# ---------- 载入配置 ----------
$conf = Join-Path $here "config.local.ps1"
if (-not (Test-Path $conf)) {
  Write-Host "❌ 找不到 config.local.ps1" -ForegroundColor Red
  Write-Host ""
  Write-Host "请先执行（在本目录）：" -ForegroundColor Yellow
  Write-Host "   Copy-Item config.local.ps1.example config.local.ps1"
  Write-Host "   notepad config.local.ps1      # 改 ServerIp / SshKey"
  exit 1
}
. $conf

foreach ($v in @("ServerIp", "SshUser", "SrcDir", "RepoDir")) {
  if (-not (Get-Variable $v -ErrorAction SilentlyContinue) -or -not (Get-Variable $v -ValueOnly)) {
    Die "config.local.ps1 里缺少 $v"
  }
}
if ($ServerIp -eq "1.2.3.4") { Die "config.local.ps1 里的 ServerIp 还没改成你的服务器 IP" }
if (-not (Test-Path $RepoDir)) { Die "找不到本机仓库目录：$RepoDir" }

# ---------- 检查本机工具 ----------
Info "0/5  检查本机工具"
foreach ($t in @("ssh", "scp", "tar")) {
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
    Die "本机没有 $t 命令。Windows 10/11 自带 ssh/scp/tar；若缺失请启用「OpenSSH 客户端」功能。"
  }
}
Ok "ssh / scp / tar 均可用"

# ssh / scp 的通用参数
$sshArgs = @("-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=15")
$scpArgs = @("-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=15")
if ($SshKey -and (Test-Path $SshKey)) {
  $sshArgs += @("-i", $SshKey)
  $scpArgs += @("-i", $SshKey)
} else {
  Write-Host "   （未使用私钥，将走密码登录）" -ForegroundColor Yellow
}
$remote = "$SshUser@$ServerIp"

# ---------- 测试连通 ----------
Info "1/5  测试 SSH 连接 $remote"
& ssh @sshArgs $remote "echo SSH_OK" | Out-Null
if ($LASTEXITCODE -ne 0) { Die "SSH 连不上。请确认：服务器在运行、IP 正确、22 端口已在安全组放行、密钥/密码正确。" }
Ok "SSH 连接正常"

# ---------- 打包（排除不该上传的东西）----------
Info "2/5  打包源码（排除 .git / _site / 浏览量数据 等）"
$tmp = Join-Path $env:TEMP ("site-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".tgz")
$excludes = @(
  "./.git", "./_site", "._site", "./.github",
  "./deploy/config.env", "./deploy/config.local.ps1",
  "./_data/views.json", "./_data/pv_state.json",
  "./node_modules", "./.workbuddy"
)
$tarArgs = @("-czf", $tmp)
foreach ($e in $excludes) { $tarArgs += @("--exclude=$e") }
$tarArgs += @("-C", $RepoDir, ".")
Push-Location $RepoDir
try {
  & tar @tarArgs
  if ($LASTEXITCODE -ne 0) { Die "打包失败" }
} finally { Pop-Location }
$sizeMB = [math]::Round((Get-Item $tmp).Length / 1MB, 2)
Ok "已打包：$tmp （$sizeMB MB）"
Write-Host "   （已排除 _data/views.json、pv_state.json，避免覆盖服务器上的实时浏览量）" -ForegroundColor DarkGray

# ---------- 上传 ----------
Info "3/5  上传到服务器"
$remoteTmp = "/tmp/site-upload.tgz"
& scp @scpArgs $tmp "${remote}:/tmp/site-upload.tgz"
if ($LASTEXITCODE -ne 0) { Die "上传失败" }
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
Ok "上传完成"

# ---------- 解包 ----------
Info "4/5  在服务器上解包到 $SrcDir"
$cmd = "mkdir -p '$SrcDir' && tar -xzf $remoteTmp -C '$SrcDir' && rm -f $remoteTmp && echo UNPACK_OK"
& ssh @sshArgs $remote $cmd
if ($LASTEXITCODE -ne 0) { Die "解包失败" }
Ok "解包完成"

# ---------- 发布 ----------
Info "5/5  在服务器上构建并发布"
& ssh @sshArgs $remote "cd '$SrcDir' && bash deploy/publish.sh"
if ($LASTEXITCODE -ne 0) { Die "发布失败，请看上面的输出" }

Write-Host ""
Ok "全部完成 🎉  稍后刷新 https://2019527.xyz/ 查看效果"
