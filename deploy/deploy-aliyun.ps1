#Requires -Version 5.1
<#
================================================================
【本文件是什么？】
 deploy-aliyun.ps1 —— 本机（Windows）一键上传并发布到阿里云 ECS

 一句话概括：这是给"不想折腾 Git 的人"准备的一条捷径——
 双击一下，您电脑上的网站源码就会被自动传到服务器并发布上线。
 全程不需要您登录服务器、也不需要敲任何命令。

 【为什么要有这个脚本？】
 常规做法是"把代码推到 GitHub → 服务器再去拉"。但这条路要求您会用 Git。
 而这个脚本走的是"直接从您电脑传上去"，对"代码小白"更友好：
 改完文件，双击，等两分钟，网站就更新了。

 它做三件事：
   1) 把本机源码打包，通过 scp 传到服务器
   2) 在服务器上解包到源码目录（不动服务器上的浏览量数据）
   3) 在服务器上执行 publish.sh（构建 → 自检 → 原子切换）

 【术语解释】
 · ECS = 云服务器（Elastic Compute Service），就是您在云厂商买的那台远程电脑。
 · scp = 安全复制，一个走加密通道传文件的命令，用法类似"复制文件"。
 · PowerShell = Windows 自带的命令行工具，本脚本就是用它写的。
 · PowerShell 脚本不能双击运行（安全限制），所以配套有一个 .bat 文件，
   双击那个 .bat 就等于运行本脚本。

 用法：双击同目录下的 deploy-aliyun.bat
      （或在本目录执行：powershell -ExecutionPolicy Bypass -File deploy-aliyun.ps1）
      【解释一下括号里那串】-ExecutionPolicy Bypass 的意思是
      "这次运行请放行脚本执行限制"，否则 Windows 可能因为安全策略拒绝运行。
================================================================
#>

$ErrorActionPreference = "Stop"
# 设置"出错就停止"。
# 相当于 Linux 脚本里的 set -e：任何一步失败就立刻中断，
# 避免"上传失败但还继续往下发布"，最后弄出一个不完整的状态。
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
# 取得本脚本所在文件夹的路径，存进变量 $here。
# $MyInvocation.MyCommand.Path 是"本脚本自己的完整路径"，
# Split-Path -Parent 取它所在的文件夹（去掉文件名部分）。
# 这样后面找配置文件时，不管您从哪个目录运行都不会找错地方。

function Info($m) { Write-Host "`n▶ $m" -ForegroundColor Cyan }
# 定义一个打印步骤标题的"函数"（可以理解为一段可重复使用的小工具）。
# 参数 $m 就是要显示的提示文字；ForegroundColor Cyan 让它显示成青色；
# 开头的 `n 是先换一行（反引号在 PowerShell 里是转义符）。
function Ok($m)   { Write-Host "✅ $m" -ForegroundColor Green }
# 打印绿色成功提示。
function Die($m)  { Write-Host "❌ $m" -ForegroundColor Red; exit 1 }
# 打印红色错误提示，然后立刻结束脚本。
# exit 1 里的 1 表示"以出错的状态结束"，这样调用它的 .bat 文件能知道出了问题。

# ================== 载入配置 ==================
$conf = Join-Path $here "config.local.ps1"
# 拼出配置文件路径（就在本脚本旁边），文件名是 config.local.ps1。
# 注意它跟服务器的 config.env 是两个不同的文件：
#   这个存"您电脑怎么连服务器"（服务器地址、登录方式）；
#   那个存"服务器上的网站放在哪、叫什么域名"。
if (-not (Test-Path $conf)) {
  # 检查这个配置文件是否存在。不存在就给出解决方案并退出。
  Write-Host "❌ 找不到 config.local.ps1" -ForegroundColor Red
  Write-Host ""
  Write-Host "请先执行（在本目录）：" -ForegroundColor Yellow
  Write-Host "   Copy-Item config.local.ps1.example config.local.ps1"
  # 告诉您第一步：把配置模板复制成正式配置文件。
  # Copy-Item 是 PowerShell 里的"复制文件"命令，用法是（源文件 目标文件）。
  Write-Host "   notepad config.local.ps1      # 改 ServerIp / SshKey"
  # 告诉您第二步：用记事本打开它，填上您的服务器 IP 和密钥路径。
  # notepad 就是记事本，对新手最友好的编辑器——双击、打字、Ctrl+S 保存即可。
  exit 1
}
. $conf
# 【注意开头的那个点】这个点号表示"读取并执行这个文件"，
# 效果和 Linux 里的 source 一样：把配置文件里的 $ServerIp、$SshUser 等
# 变成当前脚本可以直接使用的变量。

foreach ($v in @("ServerIp", "SshUser", "SrcDir", "RepoDir")) {
  # 逐个检查四个必填配置项有没有填：服务器地址、登录名、服务器上的源码目录、本机仓库目录。
  if (-not (Get-Variable $v -ErrorAction SilentlyContinue) -or -not (Get-Variable $v -ValueOnly)) {
    Die "config.local.ps1 里缺少 $v"
    # 只要有一项缺失或为空，就报错退出。
    # Get-Variable 用来检查这个变量存不存在、有没有值。
  }
}
if ($ServerIp -eq "1.2.3.4") { Die "config.local.ps1 里的 ServerIp 还没改成你的服务器 IP" }
# 【防呆检查】1.2.3.4 是模板里的示例地址。
# 如果还留着它，说明您忘了改，这时传文件会连到不存在的地址上、白等半天。
if (-not (Test-Path $RepoDir)) { Die "找不到本机仓库目录：$RepoDir" }
# 检查您电脑上的源码目录确实存在，避免打包时才发现路径写错。

# ================== 检查本机工具 ==================
Info "0/5  检查本机工具"
foreach ($t in @("ssh", "scp", "tar")) {
  # 逐个检查三个必备命令是否可用：
  #   ssh —— 远程登录服务器的通道；
  #   scp —— 传送文件的通道；
  #   tar —— 打包/解包工具（把一堆文件打成一个包，传输更快更省事）。
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
    Die "本机没有 $t 命令。Windows 10/11 自带 ssh/scp/tar；若缺失请启用「OpenSSH 客户端」功能。"
    # 缺了就明确告知怎么解决：在 Windows 的"设置 → 应用 → 可选功能"里
    # 找到「OpenSSH 客户端」并安装。Win10/11 一般默认就有，不用担心。
  }
}
Ok "ssh / scp / tar 均可用"

# ssh / scp 的通用参数
$sshArgs = @("-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=15")
# 准备登录服务器时要带的一串参数，存成一个清单（数组）方便复用。
# 两个参数的含义：
#   StrictHostKeyChecking=accept-new —— 第一次连接新服务器时自动接受它的"身份指纹"，
#        不弹出需要人工确认的提问。否则脚本会卡在一个"是否信任该主机"的询问上。
#   ConnectTimeout=15 —— 连接最多等 15 秒，超时就报错。
#        避免网络不通时一直傻等（否则可能等好几分钟都没反应）。
$scpArgs = @("-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=15")
# 传文件时用同一套参数，保持一致。
if ($SshKey -and (Test-Path $SshKey)) {
  # 如果配置里指定了密钥文件，而且这个文件确实存在，就用密钥登录。
  $sshArgs += @("-i", $SshKey)
  $scpArgs += @("-i", $SshKey)
  # 追加 -i 参数，意思是"用这个指定的密钥文件作为登录凭证"。
  # 【密钥登录是什么？】可以理解成"一把专用钥匙文件"，
  # 比用密码更安全，也不用手动输密码，特别适合自动化。
} else {
  Write-Host "   （未使用私钥，将走密码登录）" -ForegroundColor Yellow
  # 没有密钥文件就走密码登录——执行时会弹出来让您输密码。
  # 能用，但每次都要手动输，不太方便。建议配置密钥。
}
$remote = "$SshUser@$ServerIp"
# 拼出"登录名@服务器地址"这个标准格式，例如 deploy@115.190.250.120。
# 后面所有远程操作都用它来指定"操作哪台机器"。

# ================== 测试连通 ==================
Info "1/5  测试 SSH 连接 $remote"
& ssh @sshArgs $remote "echo SSH_OK" | Out-Null
# 试着连一下服务器，让它随口回一句"SSH_OK"。
#   开头的 & 是调用外部命令的写法（@sshArgs 表示把整个参数清单展开）；
#   | Out-Null 表示"结果别显示出来，我只看成功失败"，输出更干净。
# 【为什么要先试一下？】花一秒钟确认通道是通的，比传了半天文件才发现连不上要好得多。
if ($LASTEXITCODE -ne 0) { Die "SSH 连不上。请确认：服务器在运行、IP 正确、22 端口已在安全组放行、密钥/密码正确。" }
# $LASTEXITCODE 是上一条命令的"退出状态码"，不等于 0 就表示失败了。
# 这里把最常见的四个原因一次列全，照着逐条排查基本都能解决：
#   ① 服务器是不是开机状态（云控制台能看）；
#   ② IP 有没有填错；
#   ③ 云控制台的"安全组"里有没有放行 22 端口（本脚本和服务器之间的通道端口）；
#   ④ 密钥路径或密码对不对。
Ok "SSH 连接正常"

# ================== 打包（排除不该上传的东西） ==================
Info "2/5  打包源码（排除 .git / _site / 浏览量数据 等）"
$tmp = Join-Path $env:TEMP ("site-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".tgz")
# 决定打好的包放在哪里、叫什么名字。
#   $env:TEMP 是 Windows 的临时文件夹；
#   文件名带时间戳（如 site-20261013-093045.tgz）避免重名；
#   .tgz 是一种压缩包格式（相当于 .tar.gz）。
$excludes = @(
  "./.git", "./_site", "._site", "./.github",
  "./deploy/config.env", "./deploy/config.local.ps1",
  "./_data/views.json", "./_data/pv_state.json",
  "./node_modules", "./.workbuddy"
)
# 【这段排除清单非常关键，逐项说明为什么不传：】
#   ./.git              —— Git 的版本历史。体积可能很大，而且服务器上不需要。
#   ./_site             —— 上一次构建出来的网页成品。服务器会自己重新构建，传过去纯属浪费。
#   ./.github           —— GitHub 专用的自动化配置。服务器不跑 GitHub Actions，没用。
#   ./deploy/config.env —— 【重要】服务器自己的配置文件。里面是服务器上的域名和目录设置，
#                          用本机的版本覆盖它会把服务器配置搞坏。
#   ./deploy/config.local.ps1 —— 【重要】这个文件里可能存着服务器 IP 和密钥路径等敏感信息。
#                          绝对不该传到服务器上，属于安全考量。
#   ./_data/views.json 和 ./_data/pv_state.json —— 【最关键的一项】
#                          这两个是浏览量数据及其内部账本。您电脑上的版本很可能是几天前的旧数据，
#                          如果传上去覆盖服务器的，会导致"浏览量数字倒退"。
#                          所以必须排除，让服务器保留自己那份最新的。
#   ./node_modules       —— 前端的第三方代码包，体积巨大且服务器用不上。
#   ./.workbuddy         —— 工具产生的本地配置文件夹，与网站无关。
$tarArgs = @("-czf", $tmp)
# 开始组装打包命令的参数：
#   -c 表示"创建新包"、-z 表示"同时压缩"、-f 后面跟"包的文件名"。
foreach ($e in $excludes) { $tarArgs += @("--exclude=$e") }
# 把排除清单里的每一项都转成 --exclude=路径 的形式追加到参数里。
$tarArgs += @("-C", $RepoDir, ".")
# 【-C 这个参数很关键】它的意思是"先切换到指定目录，再开始打包"，
# 而这个目录就是您的源码目录，"."表示"打包当前目录下的所有内容"。
# 好处：压缩包里的路径是干净的相对路径，解包时不会多出一层奇怪的目录。
Push-Location $RepoDir
# 记录当前位置，并切换到源码目录。
# Push-Location 相当于"存个书签再出发"，后面 Pop-Location 就能回到原地。
try {
  & tar @tarArgs
  if ($LASTEXITCODE -ne 0) { Die "打包失败" }
} finally { Pop-Location }
# 执行打包。
# try/finally 的意思是：不管打包成功还是失败，最后都一定要执行 Pop-Location 回到原来的位置。
# 【为什么必须这样？】否则一旦打包中途出错，当前目录会一直停在源码目录里，
# 后续脚本在错误的目录下运行，可能做出莫名其妙的事。
# 【可DIY修改】要注意排除清单：如果您新增了不该上传的文件夹，
# 在这里加一行即可，格式是 "./文件夹名"。
$sizeMB = [math]::Round((Get-Item $tmp).Length / 1MB, 2)
# 算出压缩包有多大，并保留两位小数。
# Get-Item 取文件信息、.Length 是字节数、除以 1MB 换算成兆字节、
# Round(..., 2) 四舍五入到两位小数。
Ok "已打包：$tmp （$sizeMB MB）"
Write-Host "   （已排除 _data/views.json、pv_state.json，避免覆盖服务器上的实时浏览量）" -ForegroundColor DarkGray
# 特意再强调一次这个排除，因为它最容易出问题、后果也最明显（浏览量会倒退）。

# ================== 上传 ==================
Info "3/5  上传到服务器"
$remoteTmp = "/tmp/site-upload.tgz"
# 包在服务器上的临时存放位置。
# 放在 /tmp 目录的好处：系统临时目录，重启会自动清理，不会占着磁盘不放。
& scp @scpArgs $tmp "${remote}:/tmp/site-upload.tgz"
# 把压缩包传到服务器上。
# 格式是：scp 本机文件 登录名@服务器地址:目标路径
if ($LASTEXITCODE -ne 0) { Die "上传失败" }
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
# 上传成功就把本机的临时压缩包删掉，不留垃圾文件。
# -ErrorAction SilentlyContinue 表示"万一删不掉也别报错"（比如文件正被其他程序占用）。
Ok "上传完成"

# ================== 解包 ==================
Info "4/5  在服务器上解包到 $SrcDir"
$cmd = "mkdir -p '$SrcDir' && tar -xzf $remoteTmp -C '$SrcDir' && rm -f $remoteTmp && echo UNPACK_OK"
# 准备一段"要在服务器上执行的命令"，用 && 把四步串起来（前一步成功才做下一步）：
#   mkdir -p '$SrcDir'          确保源码目录存在（已存在也不报错）；
#   tar -xzf ... -C '$SrcDir'   把压缩包解开到源码目录
#                               （-x 解开、-z 是 gzip 压缩格式、-f 指定文件、-C 指定解开到哪）；
#   rm -f $remoteTmp            解完把服务器上的压缩包删掉，不留垃圾；
#   echo UNPACK_OK              最后打印一句"OK"，方便我们确认这一步真的走到了。
& ssh @sshArgs $remote $cmd
# 把上面那段命令发到服务器去执行。
if ($LASTEXITCODE -ne 0) { Die "解包失败" }
Ok "解包完成"

# ================== 发布 ==================
Info "5/5  在服务器上构建并发布"
& ssh @sshArgs $remote "cd '$SrcDir' && bash deploy/publish.sh"
# 【最后一步】让服务器进入源码目录，然后执行发布脚本。
# 也就是说：真正"把文章编译成网页并安全上线"这件事，是在服务器上完成的
# （用 5/5 这一行远程触发），而不是在您电脑上做——
# 因为构建网站需要 Ruby 环境，您电脑上不必装这些。
# 发布脚本内部的完整流程（构建 → 自检 → 原子切换 → 清理旧版本）见 deploy/publish.sh。
if ($LASTEXITCODE -ne 0) { Die "发布失败，请看上面的输出" }
# 失败时提示去看上面的输出内容——发布脚本会打印具体是哪一步出了问题。

Write-Host ""
Ok "全部完成 🎉  稍后刷新 https://2019527.xyz/ 查看效果"
# 打印最终成功提示。
# 【为什么要"稍后刷新"？】因为浏览器可能还缓存着旧页面，
# 稍微等一会儿再刷新（或者按 Ctrl+F5 强制刷新）才能看到最新内容。
# 【可DIY修改】如果您换了域名，这行提示里的网址记得一并改掉，避免误导。
