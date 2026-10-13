#Requires -Version 5.1
<#
================================================================================
【本文件是什么？】
  王志满律师博客 · 一键部署脚本（PowerShell 版，不需要安装 Git）
================================================================================

一句话概括：
  这是整个项目里功能最全的"一键发布"工具。
  您双击一个 .bat 文件，它就会自动帮您完成：更新浏览量数据 → 算出要改哪些文件
  → 把这些改动提交到 GitHub → 等网站构建完成 → 告诉您线上地址可以看了。
  全程不需要您在本机安装 Git，也不需要敲任何命令。

【它最大的价值 / 解决了什么痛点？】
  常规做法要求您会 Git（安装、配置、提交、推送、拉取……），对非程序员门槛很高。
  而这个脚本改用 GitHub 官方的"在线接口"来提交代码，
  相当于绕过 Git 这个工具，直接跟 GitHub 网站对话。
  所以只要您双击一下、填一次密码（令牌），剩下的全自动。

【为什么它更安全？】
  因为它内置了两道"安全闸"（下面有详细说明），能防止一件最可怕的事：
  「用您电脑上的旧版本，把线上更新的内容覆盖掉，导致文章丢失」。
  这是所有"一键发布工具"最容易出事的地方，本脚本专门做了防护。

--------------------------------------------------------------------------------
怎么用：双击同目录下的  deploy.bat  就行（推荐）。
         也可以在本目录按住 Shift 右键 →「在此处打开 PowerShell 窗口」，然后运行：
             .\deploy.ps1

它做了什么（五个步骤）：
   1. 刷新每篇文章的浏览量（写入 _data/views.json、_data/pv_state.json）
   2. 把本地文件和线上仓库逐一比对，算出「新增 / 修改 / 删除」
   3. 通过 GitHub 官方接口，把改动组装成一次提交并推送到仓库
      （效果等同于 git add + commit + push，但本机不用装 Git）
   4. 自动等待 GitHub 构建，构建完成后告诉你结果和线上地址

推送成功后，GitHub Actions 会自动构建并发布到：
   · 2019527.xyz          （火山引擎服务器）
   · GitHub Pages         （备用地址）

【⚠️ 注意：本脚本发布的是 GitHub 仓库，不是直接传服务器】
  它做的是"把代码送到 GitHub"，然后由 GitHub 上的自动化流程去构建并发布。
  如果您想"直接从电脑传文件到服务器、不走 GitHub"，
  那要用的是另一个脚本：deploy/deploy-aliyun.bat。

可用参数（在命令行里加，例如 .\deploy.ps1 -DryRun）：
   -DryRun         只预览会改动哪些文件，不真的上传（不需要令牌）
   -Message "..."  自定义提交说明
   -SkipViews      跳过"刷新浏览量"这一步（不查询统计接口、不在本地生成数据文件）
   -SkipData       跳过"浏览量数据文件"的同步：_data/views.json 与 _data/pv_state.json
                   这两个文件即使变了也不上传、不覆盖线上，交给 GitHub 定时任务维护
                   （可与 -SkipViews 一起用：连刷新也不做，全程不碰这两个文件）
   -SkipWatch      推送后不等待构建结果
   -Status         只看最近几次部署的状态，不做任何改动
   -SetToken       重新设置 / 更换 GitHub 令牌
   -Yes            删除较多「非文章」文件时不再询问（谨慎使用）
   -ResetBaseline  重新记录本地基准（确认本地副本已是最新时才用）
   -AllowStale     明知线上还有本地没有的更新，仍要覆盖（谨慎，可能丢文章）

   以下参数用于「拉取」方向（线上 → 本地，把网站上的最新代码同步回本机）：
   -Pull           拉取线上最新代码到本地（只写本地，不改线上）
   -Force          配合 -Pull：冲突文件一律用线上版本覆盖，不再逐个询问（谨慎）
   -NoBackup       配合 -Pull：拉取前不备份被覆盖的文件（默认是备份的）

两道安全闸（默认开启，不用做任何设置）：
   1. 线上 SHA 乐观锁：部署前先比对「本地基准提交」和线上最新提交。
      只要线上存在本地副本不知道的改动（例如在 GitHub 网页上发过文章），
      脚本会直接中止并列出冲突文件，绝不用旧副本覆盖线上。
      【名词解释】SHA 是一串代表某次提交的编号，可以理解成"这次提交的身份证号"；
      "乐观锁"是指"假设一切顺利，但在动手之前先核对一下凭证是否还有效"，
      发现不对就主动停下——这是一种既不啰嗦又能防事故的稳妥做法。
   2. 删除保护：本次只要涉及任意 .md 文件的删除，一定会列出来要求确认，
      -Yes 也绕不过；非 .md 文件删除达到 5 个以上时同样会询问。
      【为什么 .md 格外严格？】因为 .md 是您的文章和页面文件，
      删错了就是内容真的没了。而其他文件（图片、配置）删错了相对好恢复。

首次使用需要在 GitHub 生成一个「访问令牌」填一次，之后脚本自动记住。
【令牌是什么？】可以理解为"给这个脚本开的一张通行证"，
让它有权限代表您去修改自己的仓库。它只保存在您本机、加密存放。
================================================================================
#>

[CmdletBinding()]
# 声明本脚本支持 PowerShell 的"高级函数"特性（比如 -Verbose 这类通用参数）。
param(
    # param = 参数定义区。下面这些都是"开关"，您在运行时选着加即可。
    [string] $Message,
    # 自定义这次提交的说明文字。不加就会自动用「更新站点内容 - 日期时间」。
    [switch] $DryRun,
    # 试运行：只计算并显示会改哪些文件，绝不真的上传。改东西前先看看很有用。
    [switch] $SkipViews,
    # 跳过"刷新浏览量"这一步（不查询统计接口、不写本地数据文件），
    # 适合赶时间、或者不想产生额外查询记录时用。
    [switch] $SkipData,
    # 跳过"浏览量数据文件"的同步（_data/views.json、_data/pv_state.json）。
    # 【和上面 -SkipViews 的区别，请务必分清】
    #   -SkipViews：跳过"抓取"这一步 —— 不去查询统计接口，本地不生成这两个文件。
    #   -SkipData ：跳过"上传"这一步 —— 这两个文件即使变了也不上传、不覆盖线上。
    # 两个开关可以单独用，也可以一起用（一起用 = 这两个文件从抓取到上传全程不碰）。
    # -SkipData 适合与线下的其它工具/wangzhiman 的定时任务分工的场景：
    # 让线上（GitHub 定时任务）独占维护这两个文件，本地部署完全不插手。
    # 【为什么单独做成开关而不是永久排除？】因为本地的浏览量刷新、以及线上定时任务的
    # 数据纠错，都依赖这两个文件能正常提交；永久排除会切断这条链路。
    # 所以这里保留成"按需开启"，默认行为不变。
    [switch] $SkipWatch,
    # 提交完成后不等 GitHub 构建、不检查网站，直接结束（不想干等就用它）。
    [switch] $Pull,
    # 【本参数的作用】把线上（GitHub）的最新代码"拉取"回本地电脑 —— 方向与部署相反。
    # 部署 = 本地 → 线上；拉取 = 线上 → 本地。用于"网站上才是最新的，我想同步到本地"这种场景。
    # 【安全设计】拉取前会自动备份将被覆盖的文件；
    # 若某个文件"本地改过、线上也改过"，会停下来问你，不会静默覆盖你的改动。
    # 直接运行 deploy.bat 不带此参数时，行为完全不变（仍是正常的部署方向）。
    [switch] $Force,
    # 【仅配合 -Pull 使用】自动覆盖"本地改过、线上也改过"的文件，不再逐个询问。
    # ⚠️ 你的本地改动会被线上版本覆盖（有备份可恢复）。请谨慎使用。
    [switch] $NoBackup,
    # 【仅配合 -Pull 使用】拉取前不备份被覆盖的文件。项目目录更干净，但覆盖后无法找回旧版本。
    [switch] $Status,
    # 只看最近几次部署的状态，不做任何改动（查问题时很方便）。
    [switch] $SetToken,
    # 重新设置或更换 GitHub 令牌（比如旧令牌失效、或要提升权限时）。
    [switch] $Yes,
    # 对"删除较多普通文件"的询问自动回答"是"。注意：删 .md 文件时它也不管用，仍会问。
    [switch] $ResetBaseline,
    # 重新记录"本地基准"（就是"我这份副本是从线上哪个版本来的"这个记录）。
    [switch] $AllowStale
    # 明知线上有本地没有的更新，仍要强行覆盖。⚠️ 这个最危险，可能丢文章，请谨慎使用。
)

$ErrorActionPreference = 'Stop'
# 出错就停止，不要硬着头皮继续往下跑。
# 【为什么对发布脚本特别重要？】任何一步出错都该立刻中断，
# 例如"上传到一半失败"却继续提交，就会产生一个不完整的版本。
$ProgressPreference    = 'SilentlyContinue'
# 关掉进度条动画。
# 【为什么要关？】PowerShell 里那个蓝白相间的进度条看起来很友好，
# 但它会让文件上传/下载速度变慢好几倍（这是 PowerShell 知名的小毛病）。
# 关掉它，脚本能快不少，纯属性能优化，不影响功能。

# ============================== 基本配置 =====================================
# 【可DIY修改】这一段是您最可能需要改的地方（换账号、换域名时）。

$RepoOwner = 'wangzhiman123'
# GitHub 用户名（账号名）。换账号时改这里。
$RepoName  = 'wangzhiman123.github.io'
# 仓库名。这个特殊的名字表示"这是个人主页仓库"，可以免费获得 xxx.github.io 网址。
$Repo      = "$RepoOwner/$RepoName"
# 拼成"用户名/仓库名"的标准写法，GitHub 的接口都用这种格式来定位仓库。
$Branch    = 'main'
# 要提交到哪个分支。main 是当前主流的默认分支名（老项目可能叫 master）。
$SiteUrl   = 'https://2019527.xyz'
# 网站正式地址。部署完成后脚本会去访问它、验证是否正常。
$ActionsUrl = "https://github.com/$Repo/actions"
# 自动构建任务的页面地址。出问题时去这里看详细日志。

$TokenDir  = Join-Path $env:USERPROFILE '.wangzhiman-deploy'
# 令牌和基准记录的保存目录，位于您电脑的用户文件夹下。
# $env:USERPROFILE 就是 Windows 里的"C:\Users\您的用户名"。
# 【为什么放在这里？】这是相对隐蔽、只属于您个人的位置，不会随项目一起被同步走。
$TokenFile = Join-Path $TokenDir 'token.dat'
# 令牌具体存成哪个文件。

$BackupRoot = Join-Path $TokenDir 'backup'
# 「拉取」（-Pull）功能备份文件时用的根目录。
# 【为什么放在项目目录外面？】这是关键 —— 如果放在项目里，
# 备份文件会被当成"新增文件"一起上传到网站，闹出笑话（而且可能覆盖线上同名文件）。
# 放在用户文件夹下（和令牌同处），既不会上传，又是只属于你本机的位置。
# 每次拉取会在它下面建一个带时间戳的子文件夹，形如 backup\20261014-001530\。

$Root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
# 确定项目根目录。
#   $PSScriptRoot 是"本脚本所在的文件夹"。正常运行时它就有值；
#   如果是被粘贴到命令行里执行、拿不到这个值时，就退而用"当前所在目录"。
$Root = (Resolve-Path -LiteralPath $Root).Path
# 把它转换成"完整的绝对路径"，避免后面拼路径时产生歧义。
Set-Location -LiteralPath $Root
# 切换到这个目录。
# 【为什么必须先切？】因为脚本里大量操作都相对这个目录进行，
# 不管您从哪儿启动，先统一"站位"，后面才不会找错文件。
# LiteralPath 的意思是"当普通路径处理，别把里面的特殊符号当通配符"，
# 这样即使路径里有 [ ] 这种字符也不会出错。

# 不参与同步的目录 / 文件（等价于 .gitignore 的作用）
# 【说明】下面这三份清单规定了"哪些东西不往 GitHub 上传"。
# 为什么要排除？一来上传没用的文件纯属浪费，二来某些文件传上去反而会引发问题。
$ExcludeDirNames = @(
    '.git', '.workbuddy', '_site', 'node_modules', '.idea',
    '.bundle', 'vendor', '.jekyll-cache', '.sass-cache'
)
# 要排除的"文件夹名"清单：
#   .git            版本历史（体积可能很大，且服务器端不需要）
#   .workbuddy      工具产生的本地配置
#   _site           本机编译出来的网页成品（线上会自己编译，传过去纯属浪费）
#   node_modules    前端第三方代码包（体积巨大）
#   .idea           编辑器（如 IntelliJ 系列）的个人配置
#   .bundle / vendor              本机安装的组件缓存
#   .jekyll-cache / .sass-cache   编译缓存文件
# 判断方式是按文件夹名字匹配，所以只要叫这些名字的文件夹都会被跳过。
$ExcludeFileNames = @(
    'Gemfile.lock', 'package-lock.json', '.DS_Store', 'Thumbs.db',
    '.jekyll-metadata', 'deploy.log'
)
# 要排除的"文件名"清单：
#   Gemfile.lock / package-lock.json  组件版本锁定文件。
#        为什么排除？因为它会因操作系统不同而略有差异，
#        如果本机一份、线上定时任务一份，会反复产生"无意义的改动"，
#        让每次部署都显示"有文件被修改"，很干扰判断。
#   .DS_Store        苹果电脑自动生成的文件夹显示设置（对网站无用）
#   Thumbs.db        Windows 自动生成的缩略图缓存（对网站无用）
#   .jekyll-metadata 编译时的增量记录（本机专用）
#   deploy.log       部署日志（属于本地运行痕迹，不该进仓库）
$ExcludePathPrefixes = @('assets/lib', '_sass/vendors', 'assets/js/dist')
# 要排除的"路径前缀"清单。这三处都是主题自带的第三方代码，
# 属于"官方文件、我们不会改"，所以不参与同步。
# 好处：万一这些文件在两边有细微差异，也不会干扰"哪些文件被改了"的判断。

$DataFileRelPaths = @('_data/views.json', '_data/pv_state.json')
# 两个"浏览量数据文件"的相对路径清单（这是本项目的专用清单，不是通用排除项）。
# 【它们是干什么的？】
#   _data/views.json   网页真正要读的数据（每篇文章显示多少次浏览）。
#   _data/pv_state.json 内部账本（记录每篇文章查询了几次，供下次纠错用）。
# 【为什么要单独列出来？】因为这两个文件由"本地部署"和"线上的 GitHub 定时任务"
# 两条链路各自维护。某些场景下（例如 -SkipData）需要让它们不参与本地同步，
# 但又不能影响其它文件，所以单独做成一张清单，方便精确控制。
# 【注意】本清单只在带 -SkipData 参数时才生效，默认不排除。

$SkipDataSelected = @{}
# 准备一张"实际要跳过的数据文件"表（空表表示一个都不跳过）。
# 【为什么用 $() 里赋值？】这张表在下面会根据 -SkipData 是否开启被填入内容，
# 然后交给 Test-ExcludedPath 使用；先在这里定义好，避免后面读不到它。

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# 强制使用 TLS 1.2 这种加密协议去访问网络。
# 【为什么需要这一行？】老版本的 Windows PowerShell 默认用的加密协议太旧，
# 而 GitHub 早就停用了旧协议，不设置的话会连不上、报"基础连接已关闭"这类莫名其妙的错。
# 这是很多"旧系统上跑不通"问题的根本原因，属于必备的兼容处理。

$script:Token = $null
# 准备一个变量存放令牌（密码）。
# 【为什么用 $script: 前缀？】它表示"这个变量属于整个脚本"，
# 这样下面各个函数里都能读到、写入它。如果只用普通变量名，
# 在函数内部赋值会产生一个同名的局部变量，外面读不到，功能就会失效。

# ============================== 输出小工具 ===================================
# 【说明】下面五个函数是"打印漂亮提示"的小工具，纯粹为了屏幕上好看，
# 不影响任何实际功能。看懂大概意思即可，不用逐字研究。

function Head([string] $m) { Write-Host ''; Write-Host "=== $m ===" -ForegroundColor Cyan }
# 打印一个"章节标题"，青色。前后各空一行，把输出分隔成清晰的段落。
function Say([string] $m)  { Write-Host "  $m" }
# 打印普通说明文字，前面缩进两个空格。
function Ok([string] $m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
# 打印成功提示，绿色。
function Warn([string] $m) { Write-Host "  [!]  $m" -ForegroundColor Yellow }
# 打印警告提示，黄色。
function Fail([string] $m) { Write-Host "  [x]  $m" -ForegroundColor Red }
# 打印错误提示，红色。

function Die([string] $m) {
    # 定义一个"遇到无法继续的错误时，打印信息并退出"的函数。
    Write-Host ''
    Fail $m
    Write-Host ''
    # 打印错误信息（前后各空一行，让它显眼）。
    try {
        if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
            # 先判断"当前是在一个真正的窗口里运行，而不是被别处调用、输出被重定向"。
            # 【为什么判断？】只有在真窗口里才能等您按键；
            # 如果是被其它程序调用，等按键会永久卡住。
            Write-Host '按任意键退出…' -ForegroundColor DarkGray
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            # 等您按一下键盘。
            # NoEcho 表示"别把您按的键显示在屏幕上"；
            # IncludeKeyDown 表示"按下就算，不用等松开"。
            # 【为什么要有这一步？】否则出错后窗口会立刻关掉，
            # 您根本看不清是什么错误。这个小小的等待大大方便了排查问题。
        }
    } catch { }
    # 万一"等按键"这一步本身失败了，也忽略掉，直接往下走。
    exit 1
    # 以"出错"的状态结束脚本（1 表示失败），
    # 这样外层的 deploy.bat 能知道任务没成功。
}

# ============================== 公共函数 =====================================
# 【说明】下面这些是"通用工具函数"，被后面的主流程反复调用。

function Get-ApiError($ErrorRecord) {
    # 这个函数的作用：把网络请求抛出的错误，整理成一句人能看懂的话。
    # 【为什么需要它？】PowerShell 抛出的原始错误信息往往又长又含糊，
    # 只说"远程服务器返回错误"，不告诉您到底是 401（没权限）还是 404（找不到）。
    # 经过这里处理，就能看到具体的状态码和原因。

    $resp = $null
    try { $resp = $ErrorRecord.Exception.Response } catch { }
    # 尝试从错误里取出"服务器返回的响应内容"。取不到也没关系。
    if ($null -ne $resp) {
        # 取到了响应，说明确实是服务器那边给了明确答复。
        $code = ''
        try { $code = [int]$resp.StatusCode } catch { }
        # 取出 HTTP 状态码，例如 401、404、422。
        $txt = ''
        try {
            $stream = $resp.GetResponseStream()
            if ($null -ne $stream) {
                $reader = New-Object IO.StreamReader($stream)
                $txt = $reader.ReadToEnd()
                $reader.Close()
                # 把服务器返回的正文内容读出来（里面通常写着具体原因，例如"权限不足"）。
            }
        } catch { }
        if ($txt.Length -gt 400) { $txt = $txt.Substring(0, 400) }
        # 内容太长就只截取前 400 个字符。
        # 【为什么截断？】否则一大段错误信息糊满屏幕，真正有用的部分反而被淹没了。
        return "HTTP $code $txt"
        # 返回"状态码 + 简短说明"。
    }
    return $ErrorRecord.Exception.Message
    # 没取到响应（比如网络断了、域名解析不了），就返回原始的错误描述。
}

function Invoke-GitHub {
    # 这个函数是"和 GitHub 对话"的通用通道，全脚本所有网络请求都走它。
    # 【它的核心价值】把所有请求的公共部分（地址前缀、身份验证、参数格式）
    # 统一在这里处理好，其他函数只管传"我要做什么"，不用重复写这些。
    param(
        [Parameter(Mandatory)] [string] $Method,
        # 请求方式。Mandatory 表示必填。
        #   GET  = 读取信息；POST = 新建；PATCH = 修改。
        [Parameter(Mandatory)] [string] $Path,
        # 具体要访问的地址（不含网站前缀部分），例如 /repos/xxx/git/blobs。
        $Body,
        # 要发送的数据内容。查询类的请求不需要它，所以不强制。
        [int] $TimeoutSec = 300
        # 超时时间，默认 300 秒（5 分钟）。
        # 【为什么这么长？】因为上传大文件（比如图片）可能需要时间，太短会误判为失败。
    )
    $headers = @{
        'User-Agent' = 'wzm-blog-deploy'
        'Accept'     = 'application/vnd.github+json'
    }
    # 准备请求头（可以理解为"信封上要写的说明"）：
    #   User-Agent  告诉对方"我是谁"。
    #       【注意】GitHub 接口强制要求带这个，不带就直接拒绝，
    #       所以我们随便起一个名字 'wzm-blog-deploy' 即可。
    #   Accept      告诉对方"我希望你用什么格式回复我"，这里要求返回 JSON 格式
    #       （JSON 是一种结构化的文本格式，方便程序读取）。
    if ($script:Token) { $headers['Authorization'] = "token $script:Token" }
    # 如果拿到了令牌，就把令牌放进请求头里。
    # 这一句就是"出示通行证"——有了它，GitHub 才允许我们修改自己的仓库。
    # 【如果令牌是空的呢？】那就不能写入，只能读公开信息。
    # 所以 -DryRun 预览模式才敢不要令牌——它只读不写。

    $params = @{
        Method     = $Method
        Uri        = 'https://api.github.com' + $Path
        Headers    = $headers
        TimeoutSec = $TimeoutSec
    }
    # 把这些信息组装成一份"调用参数"。
    # 这里拼上了 https://api.github.com 这个固定前缀——它就是 GitHub 官方接口的入口。
    if ($null -ne $Body) {
        # 有数据要发送时，多做三步处理。
        $json = $Body | ConvertTo-Json -Depth 30 -Compress
        # 把数据转成 JSON 格式的文本。
        #   -Depth 30 表示"最多往嵌套里钻 30 层"。
        #       这里给得很大是刻意的：提交代码时数据结构嵌套很深，
        #       层次不够会导致内容被截断、提交出错，属于典型的踩坑点。
        #   -Compress 表示"不要加多余的空格换行"，压缩后传输更快。
        $params['Body'] = [Text.Encoding]::UTF8.GetBytes($json)
        # 把文本转成"字节数据"。
        # 【为什么必须转？】因为要处理中文内容，
        # 直接传文本可能因为编码不一致变成乱码，先转成标准的 UTF-8 字节最稳妥。
        $params['ContentType'] = 'application/json; charset=utf-8'
        # 声明"我发的是 UTF-8 编码的 JSON 数据"，让对方正确解读中文。
    }
    try {
        return Invoke-RestMethod @params
        # 真正发出去。Invoke-RestMethod 是一个"会自动把返回的 JSON 解析成对象"的便捷命令，
        # 省得我们自己再转换一次。
    } catch {
        throw (Get-ApiError $_)
        # 失败了，就用前面那个工具把错误整理得清楚一些再抛出。
    }
}

function Test-GitHubToken([string] $Plain) {
    # 这个函数的作用：验证一个令牌是否有用（能不能访问到本仓库）。
    # 返回"真"表示可用，"假"表示不可用。
    try {
        $headers = @{ 'User-Agent' = 'wzm-blog-deploy'; 'Authorization' = "token $Plain" }
        $null = Invoke-WebRequest -Uri "https://api.github.com/repos/$Repo" -Headers $headers `
            -UseBasicParsing -TimeoutSec 30
        # 试着读一下本仓库的信息。
        # 【为什么用"读仓库"来测试？】因为只要能读成功，
        # 就说明令牌有效、而且确实有访问这个仓库的权限，一次测试两件事。
        # -UseBasicParsing 是兼容旧版系统的写法，避免依赖浏览器组件；
        # 结果用 $null 接住是因为我们只关心"成功还是失败"，不关心内容。
        return $true
    } catch {
        return $false
        # 任何失败（网络问题、令牌无效、权限不足）都当作"不可用"。
    }
}

function Get-TokenScopes([string] $Plain) {
    # 这个函数的作用：查出这个令牌都拥有哪些权限。
    # 【为什么要知道权限？】因为不同操作需要不同权限：
    # 提交普通文件需要 repo 权限；而如果改动涉及 .github/workflows 下的文件，
    # 还额外需要 workflow 权限。提前查出来就能给出准确的提示，
    # 免得您上传失败却不知道为什么。
    try {
        $headers = @{ 'User-Agent' = 'wzm-blog-deploy'; 'Authorization' = "token $Plain" }
        $r = Invoke-WebRequest -Uri 'https://api.github.com/user' -Headers $headers `
            -UseBasicParsing -TimeoutSec 30
        # 读取"当前账号"的信息。
        return [string]$r.Headers['x-oauth-scopes']
        # 从返回的"信封"里取出权限清单那一项。
        # 它的值形如 "repo, workflow"，中间用逗号隔开。
    } catch {
        return ''
        # 查不到就返回空。
    }
}

function Save-Token([string] $Plain) {
    # 这个函数的作用：把令牌加密后保存到本机，下次就不用再输了。

    if (-not (Test-Path -LiteralPath $TokenDir)) {
        $null = New-Item -ItemType Directory -Path $TokenDir -Force
    }
    # 如果保存目录不存在就先创建。
    $sec = ConvertTo-SecureString $Plain -AsPlainText -Force
    # 把明文令牌转成"安全字符串"（一种加密后存放在内存里的形式）。
    $enc = ConvertFrom-SecureString $sec
    # 再把它转成可以保存到文件里的加密文本。
    # 【注意：这里的安全性建立在哪？】Windows 的这个加密功能和"当前登录用户"
    # 绑定在一起——也就是说，只有您本人登录这台电脑才能解密。
    # 就算文件被人拷走，在别的电脑上也用不了。这正是它安全的原因。
    [IO.File]::WriteAllText($TokenFile, $enc, [Text.Encoding]::ASCII)
    # 把加密后的内容写进文件。
    try { (Get-Item -LiteralPath $TokenFile).Attributes = 'Hidden' } catch { }
    # 把这个文件设成"隐藏"，减少被误看到、误删的可能。
    # 万一设置失败也没关系（有些系统或磁盘格式不支持），所以放在 try 里忽略错误。
}

function Read-StoredToken {
    # 这个函数的作用：把之前保存的令牌读出来并解密。
    # 读不到就返回"空"，表示需要重新设置。
    if (-not (Test-Path -LiteralPath $TokenFile)) { return $null }
    # 文件不存在，说明从没保存过。
    try {
        $enc = ([IO.File]::ReadAllText($TokenFile, [Text.Encoding]::ASCII)).Trim()
        # 读取加密文本，并去掉前后可能多余的空白字符。
        if (-not $enc) { return $null }
        # 文件里是空的，也当作"没有"。
        $sec  = ConvertTo-SecureString $enc
        # 把加密文本还原成内存里的安全字符串。
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        # 【这一段是 Windows 的标准套路，照抄即可】
        # 安全字符串为了安全不能直接读，需要先转成一种"非托管内存里的字符串"。
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        # 从这块内存里把真正的明文取出来返回。
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        # 【finally 这一句很重要】不管上面成功还是失败，都要把这块内存清空。
        # 为什么要清？因为明文令牌留在内存里，理论上可能被其他程序窥探。
        # 用完立刻擦掉，是处理密码类信息的良好习惯。
    } catch {
        return $null
        # 解密失败（比如换了电脑、文件损坏）就当作没有，让流程去引导重新设置。
    }
}

function Prompt-Token {
    # 这个函数的作用：一步步引导您去 GitHub 申请令牌，并接收您粘贴进来的内容。
    # 【为什么要把步骤写得这么详细？】因为申请令牌这件事对新手来说相当陌生，
    # 页面上全是英文选项，很容易点错。这里把该点什么都写清楚了。
    Write-Host ''
    Write-Host '---- 需要设置 GitHub 访问令牌（只需一次，之后自动记住）----' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  获取步骤：'
    Write-Host '    1. 浏览器打开  https://github.com/settings/tokens/new'
    # 这是"新建令牌"页的直达链接，省得您在一层层菜单里找。
    Write-Host '    2. Note 随便填，例如  blog-deploy'
    # Note 是"给这个令牌起个备注名"，方便以后认出来它用来干什么。
    Write-Host '    3. Expiration 建议选  No expiration'
    # Expiration 是"有效期"。选"永不过期"就不用隔一段时间重新设置一次。
    # 【小提醒】从安全角度说，设一个有效期更稳妥；
    # 但从"省心"角度说，选永不过期对个人博客更方便。您可以自己权衡。
    Write-Host '    4. 勾选两个权限：  repo（整项）  和  workflow（整项）'
    # 【这一步最关键，勾错了就会失败】
    #   repo     —— 允许读写仓库内容（提交文章必需）。
    #               注意要点最上面那个总开关，它会自动把下面所有子项都勾上。
    #   workflow —— 允许修改 .github/workflows 里的自动化配置。
    #               本项目包含这类文件，所以也需要它。
    Write-Host '    5. 拉到最下面点  Generate token，复制 ghp_ 开头的那串字符'
    # 生成后页面上会显示一串以 ghp_ 开头的字符，那就是令牌。
    # ⚠️ 它只会显示这一次！离开页面就再也看不到了，务必当场复制。
    Write-Host ''
    Write-Host '  （粘贴：在这个窗口按 鼠标右键 或 Ctrl+V；输入时不显示是正常的）' -ForegroundColor DarkGray
    # 【给新手的贴心提示】两点最容易困惑的地方：
    #   ① 这个窗口里没法用 Ctrl+V 的老写法，但可以用鼠标右键直接粘贴；
    #   ② 粘贴时屏幕上一个字符都不会显示（这是密码输入的保护机制），
    #      看起来像没粘上，其实已经粘好了，直接按回车就行。
    Write-Host ''
    $sec = Read-Host '  把令牌粘贴到这里后按回车'
    # 把您粘贴的内容读进来（不会显示在屏幕上）。
    return $sec
}

function Get-Token {
    # 这个函数的作用：拿到一个可用的令牌。
    # 它会按"最省事的顺序"依次尝试，尽量避免打扰您。
    #   ① 先看环境变量里有没有（适合自动化场景）；
    #   ② 再看本机有没有保存过的、而且仍然有效的；
    #   ③ 都没有，才弹出引导让您手工填。
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }
    # 第一优先：系统的环境变量。
    # 如果您在系统里设置了 GITHUB_TOKEN，就直接用它，不打扰您。
    # （这种方式常见于服务器自动化，个人电脑上一般不会设置。）

    for ($round = 1; $round -le 3; $round++) {
        # 最多给三次机会。为什么要循环？因为您可能粘贴不完整、或者权限勾漏了，
        # 允许重来比"一次失败就退出"友好得多。
        $stored = Read-StoredToken
        # 试着读出本机保存过的令牌。
        if ($stored) {
            # 有保存过的，先验证它现在还有没有用。
            if (Test-GitHubToken $stored) {
                # 能用，再检查它的权限够不够。
                $scopes = Get-TokenScopes $stored
                if ($scopes -and ($scopes -notmatch 'repo')) {
                    # 【关键检查】如果权限清单非空、但里面不含 repo。
                    # 【为什么必须检查？】没有 repo 权限就没法提交文件，
                    # 与其等到上传到一半才失败，不如现在就重新生成一个。
                    Warn "已保存的令牌缺少 repo 权限（当前权限：$scopes），请重新生成。"
                    Remove-Item -LiteralPath $TokenFile -Force -ErrorAction SilentlyContinue
                    # 把这份不好用的令牌删掉，免得下次又读到它。
                } else {
                    # repo 权限没问题。
                    if ($scopes -and ($scopes -notmatch 'workflow')) {
                        Warn '令牌没有 workflow 权限，本次无法更新 .github/workflows 里的文件。'
                        # 只是提醒，不阻断。
                        # 【为什么可以容忍？】因为大部分人只改文章，
                        # 不改那些自动化配置，所以缺这个权限通常也能顺利完成部署。
                    }
                    return $stored
                    # 直接返回这个能用的令牌，整个流程都不打扰您。
                }
            } else {
                # 保存的令牌已经失效了。
                Warn '本机保存的令牌已失效（可能被撤销或过期），需要重新设置。'
                Remove-Item -LiteralPath $TokenFile -Force -ErrorAction SilentlyContinue
                # 删掉失效的，准备让您填新的。
            }
        }

        $plain = Prompt-Token
        # 弹出引导，让您粘贴令牌。
        $plain = ([string]$plain) -replace '\s', ''
        # 把您粘贴内容里所有的空白字符（空格、换行、Tab）都去掉。
        # 【为什么需要？】粘贴时经常不小心带进空格或换行，
        # 而令牌里绝不能有这些字符，否则会验证失败却看不出原因。
        # 自动清理掉，能省掉一大类"明明粘对了却说无效"的困惑。
        if (-not $plain) { Warn '没有输入内容，请重试。'; continue }
        # 您直接按了回车、什么都没填，就提示一下再来。

        if (-not (Test-GitHubToken $plain)) {
            Fail '这个令牌无法访问仓库，请确认：复制完整、且勾选了 repo + workflow 权限。'
            continue
            # 令牌无效（或者没权限），把最常见的原因列出来提示您，然后重来一次。
        }
        Save-Token $plain
        # 验证通过，加密保存到本机，以后就不用再填了。
        Ok '令牌验证通过，已加密保存在本机（只能在这台电脑上使用）。'
        $scopes = Get-TokenScopes $plain
        if ($scopes -and ($scopes -notmatch 'workflow')) {
            Warn '注意：该令牌没有 workflow 权限，.github/workflows 下的文件将无法更新。'
            # 再提醒一次可能的影响。
        }
        return $plain
        # 把可用的令牌交出去。
    }
    Die '连续 3 次都没能设置成功，已退出。'
    # 三次都没成，就带着提示正常退出（通常是令牌本身有权限问题）。
}

# ---------------------------- 路径 / 文件处理 --------------------------------
function Test-ExcludedPath([string] $rel) {
    # 这个函数的作用：判断某个文件/文件夹是否属于"不该同步"的范围。
    # 参数 $rel 是"相对于项目根目录的路径"，例如 assets/lib/xxx.js。
    if ($SkipDataSelected.Count -gt 0 -and $SkipDataSelected.ContainsKey($rel)) {
        return $true
        # 【本次新增】如果本次开启了 -SkipData，且这个文件正是两个浏览量数据文件之一，
        # 就判定为"该排除"。这样它们既不会被上传，也不会被当作"要删除的文件"。
        # 【为什么要放在最前面判断？】因为这是本次任务的重点，优先处理最直观；
        # 而且它的判断最快（直接查表），放在前面也顺带省一点时间。
    }
    foreach ($p in $ExcludePathPrefixes) {
        if ($rel -eq $p -or $rel.StartsWith($p + '/')) { return $true }
        # 两种都算命中：刚好等于这个前缀，或者以"前缀/"开头。
        # 例如 assets/lib 本身、以及 assets/lib/jquery.js 都会被排除。
    }
    return $false
    # 不在排除清单里，返回"不排除"。
}

function Get-LocalFiles {
    # 这个函数的作用：把您电脑上"需要同步的"文件全部列出来。
    # 【实现方式】它是个"递归"函数——遇到文件夹就进去继续找，
    # 就像翻抽屉：先看这一层，有子抽屉就一层层翻下去，直到翻完为止。
    param([string] $Dir, [string] $Rel = '')
    # $Dir 是当前要扫描的真实目录路径；
    # $Rel 是它相对于项目根目录的表示（第一层调用时不传，默认为空）。

    foreach ($d in [IO.Directory]::GetDirectories($Dir)) {
        # 先处理这个目录下所有的"子文件夹"。
        $name = [IO.Path]::GetFileName($d)
        # 取出文件夹名字（不含前面的路径）。
        if ($ExcludeDirNames -contains $name) { continue }
        # 名字在排除清单里，跳过它（连同里面的所有内容一起不看）。
        # continue 的意思是"这一个跳过，直接处理下一个"。
        $childRel = if ($Rel) { "$Rel/$name" } else { $name }
        # 算出这个子文件夹的相对路径。如果当前层已有前缀就接上，
        # 否则它本身就是第一层。
        if (Test-ExcludedPath $childRel) { continue }
        # 命中路径前缀排除规则，跳过。
        Get-LocalFiles -Dir $d -Rel $childRel
        # 【递归调用自己】进入这个子文件夹，继续往下找。
        # 这就是"层层翻抽屉"的关键一步。
    }
    foreach ($f in [IO.Directory]::GetFiles($Dir)) {
        # 再处理这个目录下所有的"文件"。
        $name = [IO.Path]::GetFileName($f)
        if ($ExcludeFileNames -contains $name) { continue }
        # 文件名在排除清单里，跳过。
        if ($name -like '*.log' -or $name -like '*~') { continue }
        # 额外排除两类：所有 .log 日志文件，
        # 以及以波浪号结尾的临时文件（编辑器自动生成的备份，例如 文章.md~）。
        $childRel = if ($Rel) { "$Rel/$name" } else { $name }
        if (Test-ExcludedPath $childRel) { continue }
        # 检查路径前缀排除规则。
        [PSCustomObject]@{ Rel = $childRel; Full = $f }
        # 【输出一个记录】把文件的"相对路径"和"完整真实路径"配对输出。
        # 两者都要的原因：相对路径用来和 GitHub 上的文件一一对应；
        # 完整路径用来真正读取文件内容。
        # 【注意】这里没有用 return，而是直接写出一个对象，
        # 这是 PowerShell 的特性——在函数里写出的值会自动成为"返回值"的一部分，
        # 从而把沿途找到的所有文件汇集起来，形成一份完整清单。
    }
}

function Get-GitBlobSha {
    # 这个函数的作用：算出某个文件内容的"身份编号"（专业叫法：SHA 哈希值）。
    # 【哈希值是什么？】可以理解成"内容的指纹"：
    # 内容只要有一个字节不同，算出来的指纹就完全不同；
    # 内容完全相同，指纹就一定相同。
    # 【为什么需要它？】这样比对"本地文件和线上文件是否一样"就不用真的下载比对，
    # 只要比一下指纹即可，又快又准。
    # 【实现细节为什么这么绕？】因为 Git 对文件算指纹的方式比较特殊，
    # 必须先加上一段"文件头"（内容是 blob + 文件长度 + 一个结束符）再一起参与计算。
    # 所以要在内存里把"头"和"内容"拼起来。
    param([byte[]] $Bytes)
    $header = [Text.Encoding]::ASCII.GetBytes(("blob {0}" -f $Bytes.Length) + [char]0)
    # 造出文件头：形如 "blob 1234" 后面跟一个空字符（[char]0）。
    # {0} 会被替换成文件长度（字节数）。这是 Git 内部规定的固定格式，照做即可。
    $buf = New-Object byte[] ($header.Length + $Bytes.Length)
    # 准备一块"刚好能装下头 + 内容"的内存空间。
    [Buffer]::BlockCopy($header, 0, $buf, 0, $header.Length)
    # 先把文件头拷到这块内存的最前面。
    if ($Bytes.Length -gt 0) {
        [Buffer]::BlockCopy($Bytes, 0, $buf, $header.Length, $Bytes.Length)
        # 再把文件内容接在后面。
        # 判断长度大于 0 是为了跳过空文件这种特殊情况，避免出错。
    }
    $sha1 = [Security.Cryptography.SHA1]::Create()
    # 创建一个"算指纹"的工具（Git 用的正是 SHA1 这种算法）。
    try { $hash = $sha1.ComputeHash($buf) } finally { $sha1.Dispose() }
    # 算出指纹。
    # finally 里那句是"用完就释放这个工具占用的资源"，属于良好习惯，
    # 特别是在处理成百上千个文件时能避免资源被耗光。
    return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    # 把结果转成我们熟悉的十六进制字符串形式（例如 a1b2c3...）。
    # x2 表示"每个字节转成两位小写十六进制"。
    # 这样拼出来的 40 位字符串，就是 Git 里常见的那个文件编号。
}

# ------------------------------ JSON 读写 ------------------------------------
# 刻意与 scripts/update_views.py 的输出格式保持逐字节一致：
#   2 空格缩进、键名升序、文件末尾一个换行、无 BOM
# 这样本地脚本和 GitHub 定时任务互相不会产生无意义的差异。
# 【为什么要在意"逐字节一致"？】因为两边都会修改这两个文件。
# 只要格式有一点点不同（比如缩进用了 4 个空格），
# Git 就会认为"文件被改过了"，每次部署都显示有修改，很干扰判断。
# 统一格式之后，真正没变的时候就不算改动，情况一目了然。

function Read-JsonMap([string] $path) {
    # 这个函数的作用：把一个 JSON 文件读成"一张对照表"（键值对）。
    $map = @{}
    # 先准备一张空表。@{} 是 PowerShell 里表示"对照表"的写法。
    if (-not (Test-Path -LiteralPath $path)) { return $map }
    # 文件不存在就直接返回空表（第一次运行时就是这种情况，不该报错）。
    try {
        $raw = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
        # 按 UTF-8 编码把整个文件读成文本。
        $raw = $raw.TrimStart([char]0xFEFF).Trim()
        # 去掉开头的"BOM"标记（一个看不见的特殊字符，
        # 某些编辑器保存时会偷偷加上，很多程序会因此解析失败），
        # 再去掉首尾空白。这一步能避免一类很难查的诡异问题。
        if (-not $raw) { return $map }
        # 内容为空也返回空表。
        $obj = $raw | ConvertFrom-Json
        # 把 JSON 文本解析成对象。
        foreach ($prop in $obj.PSObject.Properties) {
            $map[$prop.Name] = [int]$prop.Value
            # 逐项搬进对照表。
            # [int] 是把它强制转成整数（浏览量必须是数字，
            # 不转的话后面做加法可能变成"文字拼接"，出现 12 变成 123 这种怪事）。
        }
    } catch { }
    # 万一文件内容损坏，也不报错，就当空表处理（后续流程会自然覆盖它）。
    return $map
}

function Write-JsonMap([string] $path, $map) {
    # 这个函数的作用：把一张对照表按指定格式写回 JSON 文件。
    # 【为什么要手工拼字符串，而不用现成的转换命令？】
    # 因为现成命令的格式不受我们控制（缩进、排序、结尾换行都不一定符合预期），
    # 而这里需要和 Python 脚本保持逐字节一致，所以自己精确控制每一处细节。
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    # 确保要写入的文件夹存在，不存在就创建。
    $keys = @($map.Keys | Sort-Object)
    # 把所有键拿出来排序。
    # 【为什么排序？】这样每次生成的文件顺序都一致，
    # 内容没变时文件也完全一样，不会产生"虚假的改动"。
    $sb = New-Object Text.StringBuilder
    # 准备一个"文字拼接器"。用它来拼长文本比用 + 号快得多（性能考虑）。
    [void]$sb.Append("{`n")
    # 先写下开头的大括号和一个换行符。
    # `n 是 PowerShell 里表示换行的写法。
    # 前面的 [void] 是"别把结果输出到屏幕上"（否则拼接过程会不断刷屏）。
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $k = $keys[$i]
        $comma = if ($i -lt $keys.Count - 1) { ',' } else { '' }
        # 决定这一行末尾要不要加逗号：
        # 只要不是最后一项就加（因为最后一项后面不能有逗号，否则 JSON 格式不合法）。
        [void]$sb.Append(('  "{0}": {1}{2}' -f $k, [int]$map[$k], $comma))
        # 拼出一行，形如：  "/posts/post-001/": 3,
        # 开头两个空格是缩进（与 Python 那边保持一致）。
        [void]$sb.Append("`n")
        # 加上换行。
    }
    [void]$sb.Append("}`n")
    # 写上结尾的大括号和一个换行符。
    # 【为什么结尾要有换行？】很多文本工具会因为"文件最后少一个换行"而报整份文件都变了，
    # 补上它就避免了这种麻烦。
    [IO.File]::WriteAllText($path, $sb.ToString(), (New-Object Text.UTF8Encoding $false))
    # 把内容写成文件。
    # 【关键细节】UTF8Encoding 后面的 $false 表示"不要加 BOM"。
    # 这就是前面读文件时为什么要处理 BOM 的原因——两边配合，保证格式干净一致。
}

# --------------------------- 文章路径推导 ------------------------------------
function Get-PostSlug([string] $fileName) {
    # 这个函数的作用：从文章文件名里提取"文章代号"。
    # 例如 2026-10-03-post-046.md → post-046
    # 【为什么需要它？】浏览量数据是按网址存放的，
    # 而网址规则是 /posts/ + 代号 + /，所以必须先算出这个代号。
    $base = $fileName
    # 从文件名开始处理。
    foreach ($ext in @('.md', '.markdown')) {
        if ($base.EndsWith($ext, [StringComparison]::OrdinalIgnoreCase)) {
            # 检查文件名是不是以这个后缀结尾。
            # OrdinalIgnoreCase 表示"忽略大小写"，这样 .MD 或 .Md 也能正确识别。
            $base = $base.Substring(0, $base.Length - $ext.Length)
            # 把后缀切掉，只保留主干。
            break
            # 切掉一个就够了，跳出循环。
        }
    }
    if ($base -match '^\d{4}-\d{1,2}-\d{1,2}-(.*)$') { return $Matches[1] }
    # 用规律匹配"4位数字-数字-数字-剩下的内容"，
    # 也就是识别并去掉开头的日期部分，返回日期后面那段。
    # $Matches[1] 是匹配结果里第一个括号内的内容（也就是我们想要的部分）。
    return $base
    # 文件名格式不标准（没写日期），就原样返回，保证不出错。
}

function Get-PostUrlPath {
    # 这个函数的作用：算出某篇文章在网站上的访问路径。
    # 例如 /posts/post-046/ 或文章自己指定的 /my-page/
    # 【为什么必须准确？】因为这个路径同时是浏览量数据的"编号"，
    # 一旦算错，就取不到、也写不对浏览量数字。
    param([string] $File, [string] $Slug)

    $head = ''
    try {
        $all = [IO.File]::ReadAllText($File, [Text.Encoding]::UTF8)
        $head = if ($all.Length -gt 4096) { $all.Substring(0, 4096) } else { $all }
        # 只读取文件开头的一小段（最多 4096 个字符）。
        # 【为什么要限制？】文章正文可能很长，
        # 而我们只需要开头的说明部分，少读一点能让几十篇文章的处理明显更快。
    } catch { }
    # 读取失败就保持为空，下面会走默认规则。

    if ($head.StartsWith('---')) {
        # 确认开头是说明区（front matter）的起始标记。
        $end = $head.IndexOf('---', 3)
        # 从第 4 个字符开始找第二个 ---，它标记着说明区的结束。
        if ($end -gt 0) {
            $fm = $head.Substring(3, $end - 3)
            # 把两个 --- 之间的内容取出来，这就是文章的元信息。
            foreach ($line in ($fm -split "`r?`n")) {
                # 按行拆开逐行查看。
                # `r?`n 这个写法能同时兼容 Windows 的换行（回车+换行）
                # 和 Linux/Mac 的换行（只有换行），处理更稳妥。
                if ($line -match '^\s*permalink\s*:\s*(.+?)\s*$') {
                    # 找出形如 permalink: 值 的那一行。
                    # permalink 的意思是"文章自己指定的固定网址"。
                    $perm = $Matches[1].Trim().Trim('"').Trim("'")
                    # 取出值，并去掉两边可能的空格和引号。
                    if ($perm) { return '/' + $perm.Trim('/') + '/' }
                    # 【优先使用它】如果文章自己指定了网址，就按它来，
                    # 前后补上斜杠使其规范化（例如 my-page 变成 /my-page/）。
                    break
                }
            }
        }
    }
    return "/posts/$Slug/"
    # 文章没自己指定，就用统一规则：/posts/ + 代号 + /
    # 【重要】这个格式必须和 _config.yml 里的 permalink 设置保持一致，
    # 否则算出来的路径和网页实际地址对不上，数据就对不上了。
}

# ============================ 刷新浏览量 =====================================
# 【说明】这一整段函数的功能，和 scripts/update_views.py 基本一致，
# 只是用 PowerShell 重写了一遍。为什么要重写？
# 因为本脚本（deploy.ps1）的设计目标就是"本机不装任何额外环境"——
# 如果调用 Python 脚本，就要求您电脑上先装好 Python，那就不算"一键"了。
# 所以作者把抓取浏览量的逻辑也用 PowerShell 实现了一份。
# 两者的纠错原理完全相同，详细原理说明请见 scripts/update_views.py 里的注释。
function Update-Views {
    Head '刷新文章浏览量'

    $postsDir  = Join-Path $Root '_posts'
    $viewsFile = Join-Path $Root '_data\views.json'
    $stateFile = Join-Path $Root '_data\pv_state.json'
    # 三个关键路径：文章文件夹、最终数据文件、内部账本文件。
    $api = 'https://busuanzi.ibruce.info/busuanzi?jsonpCallback=BusuanziCb'
    # 要查询的统计接口地址。
    $ua  = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
           '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    # 伪装成常见的 Chrome 浏览器。
    # 【为什么要伪装？】有些统计服务对"看起来不像浏览器的请求"会比较警惕，
    # 可能会拒绝。装作普通浏览器访问，成功率更高。

    if (-not (Test-Path -LiteralPath $postsDir)) { Warn '_posts 目录不存在，跳过这一步。'; return }
    # 没有文章文件夹就跳过（而不是报错），保证流程还能继续。

    $posts = @(Get-ChildItem -LiteralPath $postsDir -File |
        Where-Object { $_.Name -match '\.(md|markdown)$' } | Sort-Object Name)
    # 取出文章文件夹里所有的 .md / .markdown 文件，并按文件名排序。
    # 排序是为了输出稳定、便于核对。
    if ($posts.Count -eq 0) { Warn '没有找到文章，跳过这一步。'; return }
    # 一篇文章都没有也跳过，避免把数据文件清空。

    # 基准数据优先取自线上仓库（GitHub 的定时任务也在维护这两个文件），
    # 避免本地和线上各记一套、互相覆盖。
    # 【这一段设计得很讲究，值得理解】
    # 因为 GitHub 上的定时任务也在跑同样的抓取工作、也在更新这两个文件。
    # 如果本地用一个"自己之前的旧账本"去算，
    # 算出来的数字就会和线上那套对不上，两边来回覆盖，浏览量会乱跳。
    # 所以这里先尝试读取线上版本作为基准，保证两边"账本是同一本"。
    $fetchMap = {
        # 定义一个"从 GitHub 上读取某个数据文件"的小工具（可以理解成一段可重复调用的代码块）。
        # {$ ... } 是 PowerShell 里"代码块"的写法，用 & 来调用它。
        param([string] $name)
        $res = Invoke-GitHub -Method GET -Path "/repos/$Repo/contents/_data/$name?ref=$Branch"
        # 通过接口读取指定文件的内容。
        # ?ref=$Branch 表示"要 main 分支上那个版本"。
        $txt = [Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String(($res.content -replace '\s', '')))
        # 【为什么要转来转去？】因为 GitHub 接口返回文件内容时用的是"Base64 编码"
        # （一种把二进制数据表示成文本的方式），所以要先解码再转成文字。
        # -replace '\s', '' 是先把内容里所有空白字符去掉（Base64 不允许有空格换行）。
        $obj = $txt | ConvertFrom-Json
        # 解析成对象。
        $map = @{}
        foreach ($prop in $obj.PSObject.Properties) { $map[$prop.Name] = [int]$prop.Value }
        # 逐项搬进对照表（和前面 Read-JsonMap 一样的做法）。
        return $map
    }

    $state = $null
    try { $state = & $fetchMap 'pv_state.json'; Say '  已读取线上账本作为基准。' } catch { }
    # 试着从线上读"内部账本"。
    # & 就是执行前面定义的那个代码块；success 时顺便打印一句说明。
    if ($null -eq $state) {
        $state = Read-JsonMap $stateFile
        Say '  线上暂无账本，改用本地账本。'
        # 线上读不到（比如第一次用、或者网络问题），就退回用本机的那份。
    }

    $prevViews = $null
    try { $prevViews = & $fetchMap 'views.json' } catch { }
    if ($null -eq $prevViews) { $prevViews = Read-JsonMap $viewsFile }
    # 同样地，把"上一次的浏览量数据"也准备好。
    # 它的用途：万一某篇文章这次查询失败，就用这里的旧值顶上，
    # 避免页面上突然变成 0 次浏览。

    Say "  共 $($posts.Count) 篇文章，逐篇查询（约需 1～2 分钟，请勿关闭窗口）…"
    # 提前告知需要等待，避免您以为程序卡死了把窗口关掉。

    $views = @{}
    # 准备新的"最终浏览量"对照表。
    $okCount = 0; $failCount = 0; $idx = 0
    # 三个计数器：成功篇数、失败篇数、当前处理到第几篇。

    foreach ($p in $posts) {
        # 逐篇处理。
        $idx++
        # 当前篇号 +1。
        $slug    = Get-PostSlug $p.Name
        # 算出文章代号。
        $urlPath = Get-PostUrlPath -File $p.FullName -Slug $slug
        # 算出文章网址路径（这是数据的编号）。
        $pageUrl = $SiteUrl + $urlPath
        # 拼出完整网址，用作请求时的 Referer 说明。

        $raw = $null
        for ($try = 0; $try -le 2; $try++) {
            # 最多尝试三次（第一次 + 两次重试）。
            # 【为什么要重试？】网络偶尔抖动很常见，重试通常就成功了，
            # 比直接失败、显示旧数字要好。
            try {
                $r = Invoke-WebRequest -Uri $api -Headers @{ 'Referer' = $pageUrl; 'User-Agent' = $ua } `
                    -UseBasicParsing -TimeoutSec 25
                # 发出查询请求。两个关键说明：
                #   Referer —— 【最关键的一项】声明"这次访问来自哪个页面"。
                #              统计服务正是靠它区分不同文章的，
                #              所以必须设成这篇文章自己的地址，不能错。
                #   User-Agent —— 伪装浏览器（见上文说明）。
                # 25 秒超时，避免网络卡住时一直干等。
                $content = [string]$r.Content
                # 把返回的内容转成文本。
                if ($content -match '"page_pv"\s*:\s*(\d+)') { $raw = [int]$Matches[1]; break }
                # 用规律从返回内容里把浏览量数字抠出来。
                # 匹配的是形如 "page_pv":123 这样的片段。
                # 找到就存下来并立刻结束重试循环（break）。
            } catch { }
            # 出错就忽略，交给下面的重试逻辑处理。
            if ($try -lt 2) { Start-Sleep -Milliseconds 1200 }
            # 还有重试机会就等 1.2 秒。
            # 【为什么要等？】连着猛敲同一个接口容易被当成恶意请求而被限制，
            # 稍微缓一下更礼貌、成功率也更高。
        }

        if ($null -eq $raw) {
            # 查询失败：沿用上一次的数值，账本不动（页面上不会突然变成 0）
            # 【为什么这么做？】网络偶尔出问题很正常。
            # 如果失败就写 0，页面上会突然显示"0 次浏览"，看着像网站坏了；
            # 沿用旧值最多是数字暂时没涨，体验好得多。
            $failCount++
            if ($prevViews.ContainsKey($urlPath)) { $views[$urlPath] = $prevViews[$urlPath] }
            # 把旧值原样搬过来。
            Write-Host ("    [{0,2}/{1}] {2,-14} 查询失败，沿用上次数值" -f $idx, $posts.Count, $slug)
            # 打印一行说明。{0,2} 表示"占 2 个字符宽度"，
            # {2,-14} 表示"占 14 个字符宽、左对齐"，都是为了让各列对齐好看。
        } else {
            $polls  = [int]$state[$urlPath] + 1
            # polls = "累计被本脚本查询过的次数"。
            # 取账本里的记录（没有就当作 0），+1 表示"这次又查了一遍"。
            $truePv = $raw - $polls
            # 【纠错公式，核心就这一行】
            # 真实浏览量 = 接口现在给的数字 − 累计查询次数。
            # 原理：因为"看一次账本就多记一笔"，所以要把自己看的那几眼减掉，
            # 剩下的才是访客真实访问的次数。
            # 举例：接口显示 7，前后查过 3 次 → 真实浏览量 7 − 3 = 4。
            if ($truePv -lt 0) { $truePv = 0 }
            # 兜底：万一算成负数（比如账本记录不准、或接口数据被重置），
            # 就让最小值是 0，页面上不会出现"-1 次浏览"这种荒唐数字。
            $views[$urlPath] = $truePv
            # 存进最终数据表。
            $state[$urlPath] = $polls
            # 把更新后的查询次数写回账本，供下次使用。
            $okCount++
            Write-Host ("    [{0,2}/{1}] {2,-14} 接口={3}  已查询{4}次  ->  真实={5}" -f `
                $idx, $posts.Count, $slug, $raw, $polls, $truePv)
            # 打印详细记录：第几篇、哪篇文章、接口原始值、累计查询次数、算出的真实值。
            # 把中间过程都显示出来，以后数字看着不对时一眼就能定位是哪一步的问题。
        }
        Start-Sleep -Milliseconds 400
        # 每处理完一篇就歇 0.4 秒。
        # 同样是"礼貌访问"的考虑，避免被服务方限制。
        # 【可DIY修改】想跑快些可改成 200；若发现被限制了，就调到 800 更稳。
    }

    Write-JsonMap $viewsFile $views
    # 把整理好的浏览量数据写入 _data/views.json —— 这是网页真正要读的文件。
    Write-JsonMap $stateFile $state
    # 把内部账本写入 _data/pv_state.json —— 供下次运行纠错使用。

    $total = 0
    foreach ($v in $views.Values) { $total += [int]$v }
    # 把所有文章的浏览量加起来，算出全站总浏览量。
    Ok "成功 $okCount 篇，失败 $failCount 篇，全站合计 $total 次浏览"
    # 打印总结。
}

# ============================== 部署主流程 ===================================
function Get-RemoteSnapshot {
    # 这个函数的作用：一次性取得"线上仓库当前的完整文件清单"。
    # 这是整个比对流程的基础——有了它，才知道线上有哪些文件、内容是什么。
    # 【为什么叫 Snapshot？】Snapshot 是"快照"的意思，
    # 意思是"把线上此刻的状态定格下来，供我们比对"，就像一个照片。
    $ref    = Invoke-GitHub -Method GET -Path "/repos/$Repo/git/ref/heads/$Branch"
    # 第 1 步：查到分支当前指向哪个提交。
    # ref 可以理解成"书签"，heads/main 就是 main 分支这个书签。
    $commit = Invoke-GitHub -Method GET -Path "/repos/$Repo/git/commits/$($ref.object.sha)"
    # 第 2 步：用上一步拿到的编号，查这次提交的详细信息
    # （我们主要需要它对应的"文件清单"编号）。
    $tree   = Invoke-GitHub -Method GET -Path "/repos/$Repo/git/trees/$($commit.tree.sha)?recursive=1"
    # 第 3 步：取出这次提交对应的完整文件清单。
    # 【Git 的三个层次，帮助理解这三步】
    #   ref    → 书签（哪个分支指向谁）
    #   commit → 提交记录（这一次改动封存成了什么）
    #   tree   → 文件清单（这次提交里每个文件是什么样子）
    # 这就是 Git 存储数据的结构，接口也按这个结构一层层查。

    if ($tree.truncated) {
        Warn '仓库文件过多，接口返回被截断，比对可能不完整。'
        # truncated 表示"因为文件太多，清单没能一次返回完"。
        # 本项目文件不算多，正常不会出现；真要出现就提醒一下，
        # 因为不完整的清单可能导致误判"某些文件被删了"。
    }

    $blobs = @{}
    foreach ($e in $tree.tree) {
        if ($e.type -eq 'blob') { $blobs[$e.path] = @{ Sha = $e.sha; Mode = $e.mode } }
        # 只关心普通文件（Git 里叫 blob）。
        # tree 类型的条目是文件夹，我们不需要。
        # 每一项都记下"文件编号"和"文件权限模式"。
        # 【为什么要记权限？】因为下面提交新文件时要沿用原有的权限设置，
        # 否则可能把文件的权限改坏（比如把可执行文件变成不可执行）。
    }
    return @{
        CommitSha = $ref.object.sha
        # 当前提交的编号（后面乐观锁要用它来判断本地副本是否落后）。
        TreeSha   = $commit.tree.sha
        # 当前文件清单的编号（后面提交新内容时要基于它来改）。
        Blobs     = $blobs
        # 完整的文件对照表（路径 → 编号 + 权限）。
    }
}

# ----------------------------------------------------------------------------
# 线上 SHA 乐观锁相关：本地基准 = 「这份本地副本是从哪个提交来的」
# 基准文件只存在本机（不进仓库、不上传），用来判断本地副本是否已经落后。
#
# 【先把这件事的道理讲清楚，不然会觉得这些函数莫名其妙】
# 危险场景：假设您三天前把整个项目下载到电脑上，然后一直在改。
# 而在这三天里，您又在 GitHub 网页上直接发了两篇文章。
# 现在您跑这个脚本，它就会觉得"线上那两篇文章本地没有 → 应该删掉"，
# 于是把您刚写好的文章删了。这就是最典型的"一键部署把文章弄丢"。
#
# 解决办法：记账。记住"我这份副本当初是从哪个版本复制来的"（这就是"基准"）。
# 每次部署前先问："从我当初那个版本，到现在线上最新，中间别人改了什么？"
# 如果改动的正是我这次准备删/改的文件，就说明我这份副本过时了，必须先停下。
# 这个记录只存本机，因为它描述的是"你手上这份副本的来历"，对别人没意义。
# ----------------------------------------------------------------------------
function Get-BaselinePath {
    # 算出"基准记录文件"应该放在哪。
    $safe = $Repo -replace '[^A-Za-z0-9._-]', '-'
    # 把仓库名里不适合做文件名的字符都换成短横线。
    # 例如斜杠在某些系统里是路径分隔符，直接用在文件名里会出问题。
    return Join-Path $TokenDir "baseline-$safe.json"
    # 拼出完整路径，例如 .../.wangzhiman-deploy/baseline-wangzhiman123-wangzhiman123.github.io.json
    # 带上仓库名是为了支持"同时管理多个仓库"，各记各的不会混淆。
}

function Read-Baseline {
    # 读出之前记录的基准信息。读不到就返回"空"。
    $f = Get-BaselinePath
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    # 文件不存在说明从没记录过（比如第一次使用本脚本）。
    try {
        $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
        # 读取并解析成对象。
        if ($null -ne $j -and $j.sha) { return $j }
        # 内容完整（确实有那个编号）才返回，否则当作没有。
    } catch { }
    return $null
}

function Write-Baseline {
    # 把基准信息记下来。每次成功部署后都会调用它。
    param([Parameter(Mandatory)] [string] $Sha)
    # 要记录的提交编号（必填）。
    $f = Get-BaselinePath
    if (-not (Test-Path -LiteralPath $TokenDir)) {
        New-Item -ItemType Directory -Path $TokenDir -Force | Out-Null
    }
    # 确保保存目录存在。
    $obj = [PSCustomObject]@{
        repo    = $Repo
        branch  = $Branch
        sha     = $Sha
        updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        # 顺手记下时间。
        # 【这有什么用？】万一需要排查问题，
        # 看到"基准记录于 3 天前"，就能立刻明白"您这份副本已经 3 天没更新了"，
        # 这对判断问题非常有帮助。
    }
    ($obj | ConvertTo-Json) | Set-Content -LiteralPath $f -Encoding UTF8
    # 转成 JSON 写入文件。
}

# 比对两个提交之间有哪些文件被改动过（用于判断「线上有多少本地不知道的改动」）
function Get-Divergence {
    # 这个函数的作用：问 GitHub"从我记录的那个版本，到现在最新版本，中间发生了什么变化"。
    # 这是"乐观锁"能给出准确提示的关键。
    param([string] $BaseSha, [string] $HeadSha)
    # 一个是基准版本编号，一个是线上最新版本编号。

    $res = @{ Ok = $false; AheadBy = 0; Commits = 0; Files = @(); Reason = '' }
    # 先准备一个默认结果。
    # 【为什么先填好默认值？】因为后面如果出错，就能直接返回这个"失败且信息为空"的结果，
    # 调用方一看 Ok 是 false 就知道出问题了，逻辑简单。
    try {
        $cmp = Invoke-GitHub -Method GET -Path "/repos/$Repo/compare/$BaseSha...$HeadSha"
        # 调用 GitHub 的"版本比对"接口。
        # 地址里那三个点是固定写法，表示"从 A 到 B 的变化"。
    } catch {
        $res.Reason = Get-ApiError $_
        return $res
        # 查不到（比如基准版本已经被删掉了），把原因记下来返回。
    }
    $res.Ok = $true
    # 标记这次查询成功了。
    try { $res.AheadBy = [int]$cmp.ahead_by } catch { $res.AheadBy = 0 }
    # 记录"线上比基准多了几个提交"。
    try { $res.Commits = @($cmp.commits).Count } catch { $res.Commits = 0 }
    # 记录涉及的提交数量。

    $names = New-Object System.Collections.ArrayList
    # 准备一个清单装"被改动过的文件路径"。
    foreach ($f in @($cmp.files)) {
        if ($f.filename) { [void]$names.Add([string]$f.filename) }
        # 把每个被改动文件的路径收进来。
    }
    $res.Files = $names.ToArray()
    # 转成数组存起来。
    return $res
    # 返回：是否成功、多了几个提交、都改了哪些文件。
}

function Show-Status {
    # 这个函数的作用：显示最近几次自动部署的结果（对应 -Status 参数）。
    # 【什么时候用？】想知道"我刚才那次部署成功了没"、
    # 或者"最近几次怎么老是失败"的时候，用它可以快速看清情况。
    Head '最近几次部署情况'
    try {
        $runs = Invoke-GitHub -Method GET -Path "/repos/$Repo/actions/runs?per_page=5"
        # 读取最近 5 次自动任务记录。
    } catch {
        Fail "查不到部署记录：$_"
        return
    }
    if (-not $runs.workflow_runs -or @($runs.workflow_runs).Count -eq 0) {
        Warn '还没有任何构建记录。'
        return
        # 一次都没跑过（比如刚建好仓库、还没发过文章）。
    }
    foreach ($r in @($runs.workflow_runs)) {
        # 一条条打印。
        $when = ''
        try { $when = ([datetime]$r.created_at).ToLocalTime().ToString('MM-dd HH:mm') } catch { }
        # 把时间转成本机时区并简化显示（例如 10-13 09:30）。
        # ToLocalTime 很重要，否则显示的是国际标准时间，会差 8 小时让您困惑。
        $mark = switch ($r.conclusion) {
            'success'   { '[OK]' }
            'failure'   { '[失败]' }
            'cancelled' { '[取消]' }
            default     { "[$($r.status)]" }
        }
        # 把英文状态翻译成一眼能懂的中文标记。
        # switch 是"逐个情况比对"的语法：
        #   成功显示 [OK]、失败显示 [失败]、被取消显示 [取消]，
        #   其他情况（比如还在进行中）就原样显示状态名。
        Write-Host ("  {0,-8} {1}  {2}" -f $mark, $when, $r.display_title)
        # 打印一行：状态、时间、这次为什么触发的说明。
        Write-Host ("           {0}" -f $r.html_url) -ForegroundColor DarkGray
        # 再打印一行可点击的详情链接（灰色小字），点进去能看完整日志。
    }
    Say ''
    Say "全部记录：$ActionsUrl"
    # 附上完整记录页的地址。
}

function Wait-Deploy {
    # 这个函数的作用：提交完成后，盯着 GitHub 看它什么时候构建好，
    # 并把结果告诉您（对应默认行为，可用 -SkipWatch 跳过）。
    param([string] $Sha, [int] $MaxMinutes = 15)
    # $Sha 是刚提交的那个版本编号（要靠它认出"哪次任务是我的"）；
    # 最多等 15 分钟。

    Head '等待 GitHub 构建与发布'
    Say '  GitHub 正在编译网站并发布，通常 1～3 分钟…'
    # 提前告知预计时间，让您安心等待。

    $run = $null
    $elapsed = 0
    # 已经等了多久（秒）。
    $deadline = (Get-Date).AddMinutes($MaxMinutes)
    # 算出"最晚等到什么时候"。

    while ((Get-Date) -lt $deadline) {
        # 只要还没到截止时间就继续循环检查。
        try {
            $runs = Invoke-GitHub -Method GET -Path "/repos/$Repo/actions/runs?per_page=20"
            # 读最近的 20 条任务记录。
            $run = @($runs.workflow_runs | Where-Object { $_.head_sha -eq $Sha }) | Select-Object -First 1
            # 【关键】从里面挑出"版本编号和我刚提交的一致"的那一条，
            # 这就是我这次触发的那次构建。
            # Select-Object -First 1 表示"只要第一条"（理论上只会有一条）。
        } catch { $run = $null }
        # 网络出错就先当作没查到，下一轮再试。

        if ($run -and $run.status -eq 'completed') { break }
        # 任务已完成，跳出循环，准备报告结果。

        if ($run) {
            Write-Host ("    [{0,3}s] 状态：{1}" -f $elapsed, $run.status)
        } else {
            Write-Host ("    [{0,3}s] 等待任务启动…" -f $elapsed)
            # 还没查到任务（可能刚提交、系统还没开始处理）。
        }
        Start-Sleep -Seconds 10
        $elapsed += 10
        # 每 10 秒查一次，同时累加已等待时间。
        # 【为什么是 10 秒？】太频繁会浪费请求次数，太慢又显得迟钝，10 秒比较合适。
    }

    if (-not $run) {
        Warn '暂时没有查到对应的构建任务，可能还在排队。'
        Say  "  请稍后到 $ActionsUrl 查看。"
        return
        # 等到超时都没找到对应任务，就提示您自己去网站看（不影响已完成的提交）。
    }

    if ($run.status -ne 'completed') {
        Warn "等待超时，任务仍在进行（状态：$($run.status)）。"
        Say  "  查看进度：$($run.html_url)"
        return
        # 还在跑但等太久了，就不继续干等，给出链接让您自己看。
    }

    Write-Host ''
    if ($run.conclusion -eq 'success') {
        Ok '构建部署成功！'
    } else {
        Fail "构建没有成功（结果：$($run.conclusion)）"
        Say  "  打开日志看看原因：$($run.html_url)"
        # 失败了就直接给日志链接——这是排查问题必须看的地方。
    }

    # 逐个任务报告，特别是「推送到火山引擎服务器」那一步有没有跑
    try {
        $jobs = Invoke-GitHub -Method GET -Path "/repos/$Repo/actions/runs/$($run.id)/jobs"
        # 读取这次构建里各个"小任务"的执行情况。
        # 【为什么要看这么细？】因为一次构建包含好几个环节，
        # 只知道"整体失败"还不够，得知道是哪个环节出问题。
        Say ''
        Say '  各步骤结果：'
        foreach ($j in @($jobs.jobs)) {
            $res = if ($j.conclusion) { $j.conclusion } else { $j.status }
            # 有结果就用结果；还在跑的话就显示当前状态。
            $color = switch ($j.conclusion) {
                'success' { 'Green' }
                'skipped' { 'DarkGray' }
                default   { 'Yellow' }
            }
            # 按情况上色：成功绿色、被跳过灰色（表示"本来就没打算执行"，不是错误）、
            # 其他（失败等）黄色需注意。
            Write-Host ("    - {0,-40} {1}" -f $j.name, $res) -ForegroundColor $color
            # 打印"环节名称 + 结果"。
        }
        $serverJob = @($jobs.jobs | Where-Object { $_.name -like '*server*' })
        # 找出名字里含 server 的那个环节（也就是"推送到自己的服务器"这一步）。
        if ($serverJob -and $serverJob[0].conclusion -eq 'skipped') {
            Warn '推送到服务器那一步被跳过了 —— 说明仓库里 DEPLOY_TO_SERVER 变量不是 true，'
            Warn '2019527.xyz 上的内容不会更新（只有 GitHub Pages 会更新）。'
            # 【很贴心的一段提示】这是很容易困惑的情况：
            # "明明部署成功了，为什么我的服务器上内容没变？"
            # 原因就是这个开关没开。这里主动替您点出来。
        }
    } catch { }
    # 整段都套在 try 里忽略错误：查看明细只是"锦上添花"，
    # 就算查不到也不该影响主流程的成功判断。
}

function Test-LiveSite {
    # 这个函数的作用：真去访问一下网站，确认它确实能打开（对应默认行为的收尾）。
    # 【为什么要真访问？】因为"构建成功"和"网站真的能访问"是两件事，
    # 实际打开一下才算真正验收。
    Head '验证线上站点'
    for ($try = 1; $try -le 3; $try++) {
        # 最多试 3 次。
        # 【为什么要试多次？】因为网站刚发布完，各处的缓存可能还没更新，
        # 第一次访问失败很常见，过一会儿就好了。
        try {
            $r = Invoke-WebRequest -Uri $SiteUrl -UseBasicParsing -TimeoutSec 30
            # 访问网站首页。
            if ($r.StatusCode -eq 200) {
                Ok "$SiteUrl 访问正常（HTTP 200）"
                return
                # 200 是"一切正常"的标准回应码。看到它就放心了，直接返回。
            }
            Warn "返回 HTTP $($r.StatusCode)"
            # 能连上但状态码不正常（比如 404、500），提示一下。
        } catch {
            Warn "第 $try 次访问失败：$($_.Exception.Message)"
            # 连都连不上，记下第一次失败的原因。
        }
        if ($try -lt 3) { Start-Sleep -Seconds 10 }
        # 还有机会就等 10 秒再试。
    }
    Warn '站点暂时访问不到，稍后再看看（不影响已完成的部署）。'
    # 【这句安抚很重要】访问不到只代表"此刻网络或缓存有点问题"，
    # 不代表部署失败——代码早就提交成功、构建也成功了。
    # 明确说清楚这点，能避免您白紧张一场。
}

# ============================================================================
#                           拉取功能（-Pull）
# ----------------------------------------------------------------------------
# 【这个功能解决什么问题？】
#   平时 deploy 是"本地 → 线上"（把本地改动推上去）。
#   但有时反过来：你在 GitHub 网页上直接改了东西（例如手机上改了 _config.yml、
#   在线发了文章），这时"线上才是最新的"，本地那份反而旧了。
#   本功能就是"线上 → 本地"，把线上最新代码同步回你这台电脑。
#
# 【为什么不能简单粗暴地"全部覆盖"？】
#   因为本地可能也有你没来得及推上去的改动。如果不管不顾地覆盖，
#   那些改动就悄无声息地没了。所以本功能做了两件事：
#     ① 覆盖前先备份（默认开启，除非加 -NoBackup）；
#     ② 如果某个文件"本地改过、线上也改过"，就停下来问你，
#        让你决定是保留本地、还是用线上覆盖。
#
# 【判断"谁更新"的依据是什么？】
#   靠本机保存的「基准提交」（baseline）—— 它记录了"这份本地副本当初是从线上哪个
#   版本拷来的"。拿它和线上最新一对比，就能列出"线上新增/修改/删除"了哪些文件，
#   也就能区分出"本地是否也动过同一个文件"。
# ============================================================================

function Get-BlobShaAtCommit {
    # 小工具：查出"某个提交里、某个文件"的内容编号。
    # 【用途】拉取时判断"本地这个文件是否偏离了基准版本"（即本地是否改过）。
    # 【为什么定义在 Invoke-Pull 前面？】因为 Invoke-Pull 会用到它。
    # PowerShell 是"从上往下"执行定义的，被调用的函数要先定义好，
    # 否则运行到那一行会报"找不到命令"。
    param([string] $Commit, [string] $Path)
    try {
        $tree = Invoke-GitHub -Method GET -Path "/repos/$Repo/git/trees/$Commit`?recursive=1"
        # 取那个提交的完整文件清单，然后在里面找目标文件。
        # 【注意】地址里的 `? 里的反引号是转义符，表示"这就是个普通问号字符"，
        # 否则 PowerShell 可能把它当成别的意思。
        foreach ($e in $tree.tree) {
            if ($e.type -eq 'blob' -and $e.path -eq $Path) { return $e.sha }
        }
    } catch { }
    return $null
}

function Invoke-Pull {
    # 把线上仓库的最新文件同步到本地。整个过程只"读线上 + 写本地"，不改动线上。

    $remote = Get-RemoteSnapshot
    # 先拿线上快照：有哪些文件、各自的内容编号、当前提交号。
    Ok "线上仓库共 $($remote.Blobs.Count) 个文件（最新提交 $($remote.CommitSha.Substring(0,7))）"

    # ---------- 1. 扫描本地文件 ----------
    $localMap = @{}
    foreach ($f in (Get-LocalFiles -Dir $Root)) { $localMap[$f.Rel] = $f.Full }
    Say "  本地共 $($localMap.Count) 个文件"

    # ---------- 2. 判断本地基准，决定"差异从哪算起" ----------
    $baseline = Read-Baseline
    $baseSha  = $null
    if ($null -ne $baseline) { $baseSha = $baseline.sha }

    if ($null -eq $baseSha) {
        # 没有基准（第一次用本脚本、或基准文件丢了）：只能做"全量对比"。
        Warn '本机没有「基准提交」记录，无法知道线上"改了什么"，将改为逐个文件对比。'
        Say  '  （结果依然准确，只是提示会笼统一些：凡内容不同的都按"待更新"处理）'
    } elseif ($baseSha -eq $remote.CommitSha) {
        Ok "本地基准与线上最新一致（$($baseSha.Substring(0,7))），本地应该已经是最新的。"
        # 基准相同不代表每个文件都相同（本地可能改过还没推），所以下面仍然要逐个比对。
    } else {
        # 有基准、且和线上不同：能精确算出"线上比本地多了哪些改动"。
        $div = Get-Divergence -BaseSha $baseSha -HeadSha $remote.CommitSha
        if ($div.Ok) {
            Say "  线上比本地基准新 $($div.AheadBy) 个提交，涉及 $($div.Files.Count) 个文件。"
        } else {
            Warn "  基准与线上无法比对（$($div.Reason)），改为逐个文件对比。"
        }
    }

    # ---------- 3. 逐个文件比对，分类 ----------
    $toUpdate = New-Object System.Collections.ArrayList   # 线上有内容、本地需要更新（含本地没有的）
    $toDelete = New-Object System.Collections.ArrayList   # 线上已删、本地还留着的
    $conflict = New-Object System.Collections.ArrayList   # 两边都改过，需要问用户
    $localOnly = New-Object System.Collections.ArrayList  # 只有本地改过（线上没动）→ 应原样保留
    $same     = 0                                          # 两边内容完全相同

    # 先遍历"线上有的文件"
    foreach ($rel in @($remote.Blobs.Keys | Sort-Object)) {
        $blob = $remote.Blobs[$rel]
        if (Test-ExcludedPath $rel) { continue }
        # 排除清单里的（例如 assets/lib 第三方代码）不参与，和部署逻辑保持一致。

        if (-not $localMap.ContainsKey($rel)) {
            # 本地没有 → 线上的新文件，需要下载。
            [void]$toUpdate.Add(@{ Rel = $rel; Sha = $blob.Sha; Mode = $blob.Mode; Why = '新增' })
            continue
        }

        # 本地有 → 比对内容指纹（不用真的下载内容，比指纹即可，快且准）。
        $bytes = [IO.File]::ReadAllBytes($localMap[$rel])
        if ((Get-GitBlobSha $bytes) -eq $blob.Sha) {
            $same++
            continue
            # 指纹一样 = 内容完全一致，无需处理。
        }

        # 内容不同。这时要区分"是本地改的、还是线上改的、还是两边都改了"。
        # 【判定原理】基准版本 = 本地和线上的"共同祖先"。
        #   · 本地当前内容 == 基准内容  → 本地没动过 → 差异纯粹来自线上 → 直接更新。
        #   · 本地当前内容 != 基准内容  → 本地动过 → 再看线上是否也动过：
        #        线上动过  → 冲突（两边都改，要问用户）
        #        线上没动过 → 只是你自己的本地改动，保留即可。
        $remoteChanged = $false
        $baseShaLocal  = $null
        if ($null -ne $baseSha) {
            if ($baseSha -eq $remote.CommitSha) {
                # 【重要】基准就是线上最新 → 说明"线上从基准以来什么都没改"。
                # 此时差异必然全部来自本地，绝不可能是冲突。
                # 【为什么单独处理这一支？】因为基准和线上相同时，
                # 拿基准和线上做"版本比对"会得到"0 个提交、0 个变更文件"，
                # 那种结果无法用来判断"线上是否改过"——线上本来就等于基准，当然没改过。
                $remoteChanged = $false
            } else {
                # 基准和线上不同 → 查清楚这中间线上改了哪些文件。
                $div = Get-Divergence -BaseSha $baseSha -HeadSha $remote.CommitSha
                if ($div.Ok) {
                    $remoteChanged = ($div.Files -contains $rel)
                    # 线上那次改动里没提到这个文件 → 说明差异是本地改的，线上没动过。
                } else {
                    # 【查不到比对结果时的保守处理】无法确认线上是否改过。
                    # 宁可判定为"线上可能改过"（走下面的冲突判定），
                    # 也不要贸然覆盖，避免丢掉线上的改动。
                    $remoteChanged = $true
                }
            }
            # 不论哪一支，都取来"基准版本里这个文件的内容指纹"，用于判断本地是否偏离了基准。
            try {
                $shaAtBase = Get-BlobShaAtCommit -Commit $baseSha -Path $rel
                if ($shaAtBase) { $baseShaLocal = $shaAtBase }
            } catch { }
        } else {
            # 【没有基准记录时】无从判断谁改的，采取保守策略：按"需要更新"处理，
            # 但不直接当冲突（否则第一次使用、或基准丢失时会一片问号）。
            # 判断依据退化成一个更朴素的规则：本地内容 != 线上内容 → 需要更新。
            $remoteChanged = $true
        }

        if (-not $remoteChanged) {
            # 线上没动过，差异来自本地 → 这是你自己的本地改动，当然要保留，跳过。
            [void]$localOnly.Add($rel)
            continue
        }

        # 走到这里：线上动过这个文件（或无法确定）。
        if ($null -ne $baseShaLocal -and (Get-GitBlobSha $bytes) -eq $baseShaLocal) {
            # 本地内容 == 基准内容 → 本地没改过，纯粹是线上变新了，直接更新即可。
            [void]$toUpdate.Add(@{ Rel = $rel; Sha = $blob.Sha; Mode = $blob.Mode; Why = '线上更新' })
        } elseif ($null -eq $baseSha) {
            # 没有基准、无法判断本地是否改过 → 归入"待更新"，
            # 让它在下面统一受"备份 + 用户可见"的保护，而不是静默覆盖。
            [void]$toUpdate.Add(@{ Rel = $rel; Sha = $blob.Sha; Mode = $blob.Mode; Why = '内容不同' })
        } else {
            # 本地内容 != 基准内容 → 本地也改过，且线上也改过 → 冲突！
            [void]$conflict.Add(@{ Rel = $rel; Sha = $blob.Sha; Mode = $blob.Mode })
        }
    }

    # 再遍历"本地有、线上没有的"文件 → 线上已删除
    foreach ($rel in @($localMap.Keys | Sort-Object)) {
        if ($remote.Blobs.ContainsKey($rel)) { continue }
        if (Test-ExcludedPath $rel) { continue }
        [void]$toDelete.Add($rel)
        # 【注意】这里只是"记下来"。到底删不删，下面会征求你的同意。
    }

    # ---------- 4. 汇报差异 ----------
    Write-Host ''
    Say "  对比结果：待更新 $($toUpdate.Count) 个，冲突 $($conflict.Count) 个，"
    Say "            线上已删除 $($toDelete.Count) 个"
    Say "            两边完全相同 $same 个，仅本地改过（会原样保留）$($localOnly.Count) 个"

    if ($toUpdate.Count -eq 0 -and $conflict.Count -eq 0 -and $toDelete.Count -eq 0) {
        if ($localOnly.Count -gt 0) {
            Ok '线上没有新内容需要拉取（本地已是最新）。'
            Say ''
            Say "  以下是「只有本地改过、线上没动」的文件，拉取不会碰它们，你的改动安全保留："
            foreach ($l in $localOnly) { Write-Host "    ✓ 保留本地  $l" -ForegroundColor Green }
            # 【这个提示很重要】否则你会疑惑"我明明改了文件，怎么显示无需拉取"。
            # 明确列出来，你就知道这些改动会被原样留着，等你以后部署时推上去。
        } else {
            Ok '本地已经和线上完全一致，无需拉取。'
        }
        # 顺手把基准对齐（如果还没对齐），这样下次就能精确比对。
        if ($baseSha -ne $remote.CommitSha) {
            Write-Baseline $remote.CommitSha
            Say "  已顺手把本地基准更新为 $($remote.CommitSha.Substring(0,7))。"
        }
        return
    }

    foreach ($u in $toUpdate) {
        Write-Host ("    ↑ 更新      {0}  ({1})" -f $u.Rel, $u.Why) -ForegroundColor Green
    }
    foreach ($c in $conflict) {
        Write-Host ("    ! 冲突      {0}  （本地和线上都改过）" -f $c.Rel) -ForegroundColor Yellow
    }
    foreach ($d in $toDelete) {
        Write-Host ("    ? 线上已删  {0}" -f $d) -ForegroundColor DarkYellow
    }

    # ---------- 5. 处理冲突：问用户 ----------
    $keepLocal = @{}
    if ($conflict.Count -gt 0) {
        Write-Host ''
        Head '冲突处理'
        if ($Force) {
            Warn '已按 -Force 处理：冲突文件一律采用线上版本（你的本地改动会被覆盖，可从备份找回）。'
            foreach ($c in $conflict) { $keepLocal[$c.Rel] = $false }
        } else {
            Say '下列文件本地和线上都改过，请逐个选择：'
            Say '  输入  L  = 保留本地版本（放弃线上这版）'
            Say '  输入  R  = 采用线上版本（覆盖本地，会先备份）'
            Say '  直接回车 = 采用线上版本（默认）'
            foreach ($c in $conflict) {
                Write-Host ''
                Write-Host "    ◆ $($c.Rel)" -ForegroundColor Yellow
                $ans = Read-Host '      请选择 [L=保留本地 / R=用线上 / 回车=用线上]'
                $keepLocal[$c.Rel] = ($ans -match '^[Ll]')
                # 只有明确输入 L 才保留本地，其余一律用线上（对新手更安全：默认不做覆盖）
                if ($keepLocal[$c.Rel]) {
                    Say "      → 保留本地版本，线上这版将被忽略。"
                } else {
                    Say "      → 采用线上版本（本地这份会先备份）。"
                }
            }
            # 如果本地版本被保留，就把它从"待更新"里剔除（不覆盖它）。
            $toUpdate = @($toUpdate | Where-Object { -not $keepLocal.ContainsKey($_.Rel) -or -not $keepLocal[$_.Rel] })
        }
    }

    # ---------- 6. 备份（默认开启） ----------
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = Join-Path $BackupRoot $stamp
    $backedUp = 0
    # 【重要】备份目录放在项目之外（见文件开头的 $BackupRoot 说明），
    # 否则备份文件本身会被下次部署当成"新增文件"上传到网站。

    if (-not $NoBackup) {
        Head '备份将被覆盖的文件'
        foreach ($u in $toUpdate) {
            if ($localMap.ContainsKey($u.Rel)) {
                # 本地已有的、即将被覆盖的文件才需要备份（本地没有的属于"纯新增"，无需备份）。
                $src = $localMap[$u.Rel]
                $dst = Join-Path $backupDir $u.Rel
                $dstDir = Split-Path -Parent $dst
                if (-not (Test-Path -LiteralPath $dstDir)) { $null = New-Item -ItemType Directory -Path $dstDir -Force }
                Copy-Item -LiteralPath $src -Destination $dst -Force
                $backedUp++
            }
        }
        if ($backedUp -gt 0) {
            Ok "已备份 $backedUp 个文件到：$backupDir"
            Say '  （万一拉取后发现问题，可以到这个文件夹里把旧版本拷回来）'
        } else {
            Say '  本次没有"会被覆盖的已有文件"，无需备份（新增文件不覆盖任何东西）。'
        }
    } else {
        Warn '已按 -NoBackup 跳过备份。若拉取后发现问题，旧版本将无法找回。'
    }

    # ---------- 7. 执行写入 ----------
    Head '写入最新文件到本地'
    $written = 0
    foreach ($u in $toUpdate) {
        try {
            $blob = Invoke-GitHub -Method GET -Path "/repos/$Repo/git/blobs/$($u.Sha)"
            # 按文件编号取回内容（GitHub 返回的是 Base64 编码的字节）。
            $bytes = [Convert]::FromBase64String(($blob.content -replace '\s', ''))
            $dst = Join-Path $Root ($u.Rel -replace '/', '\')
            $dstDir = Split-Path -Parent $dst
            if ($dstDir -and -not (Test-Path -LiteralPath $dstDir)) { $null = New-Item -ItemType Directory -Path $dstDir -Force }
            [IO.File]::WriteAllBytes($dst, $bytes)
            # 【为什么用 WriteAllBytes（写字节）而不是写文本？】
            # 因为文件里可能有图片等二进制内容，也可能有 BOM 等细节。
            # 直接按字节原样写入，才能保证和线上一字不差、指纹相同。
            $written++
        } catch {
            Warn "写入失败：$($u.Rel)  —— $_"
        }
    }
    Ok "已更新 $written 个文件"

    # ---------- 8. 处理"线上已删除"的文件 ----------
    if ($toDelete.Count -gt 0) {
        Write-Host ''
        Head '线上已删除的文件'
        Say '下列文件线上已经没有了，但本地还留着：'
        foreach ($d in $toDelete) { Write-Host "    - $d" -ForegroundColor DarkYellow }
        Say ''
        Say '【建议】如果你确认线上是特意删掉它们的，可以一并从本地删掉，保持两边一致；'
        Say '        如果不确定，就选"保留"，之后你核实清楚再手动删也不迟。'
        $delAns = Read-Host '  是否把本地这些文件也删掉？[y=删除 / 回车=保留]'
        if ($delAns -match '^[Yy]') {
            # 参照部署时的严格策略：涉及文章（.md）删除必须二次确认。
            $mdFiles = @($toDelete | Where-Object { $_ -like '*.md' -or $_ -like '*.markdown' })
            $doDelete = $true
            if ($mdFiles.Count -gt 0) {
                Write-Host ''
                Warn "其中包含 $($mdFiles.Count) 篇文章/页面文件（.md）："
                foreach ($m in $mdFiles) { Write-Host "      $m" -ForegroundColor Red }
                $again = Read-Host '  这些是内容文件，删掉就没了。确实要删吗？[输入 DELETE 才删除]'
                $doDelete = ($again -ceq 'DELETE')
            }
            if ($doDelete) {
                $delCount = 0
                foreach ($d in $toDelete) {
                    try {
                        if (-not $NoBackup) {
                            $src = Join-Path $Root ($d -replace '/', '\')
                            $dst = Join-Path $backupDir $d
                            $dstDir = Split-Path -Parent $dst
                            if (-not (Test-Path -LiteralPath $dstDir)) { $null = New-Item -ItemType Directory -Path $dstDir -Force }
                            Copy-Item -LiteralPath $src -Destination $dst -Force
                            # 删除前也先备份一份，万一误删还能找回。
                        }
                        Remove-Item -LiteralPath (Join-Path $Root ($d -replace '/', '\')) -Force
                        $delCount++
                    } catch { Warn "删除失败：$d —— $_" }
                }
                Ok "已删除 $delCount 个本地文件"
            } else {
                Say '  已取消删除，这些文件保留在本地。'
            }
        } else {
            Say '  已保留，本地这些文件不动。'
        }
    }

    # ---------- 9. 对齐基准 ----------
    Write-Baseline $remote.CommitSha
    Ok "本地基准已更新为 $($remote.CommitSha.Substring(0,7))（线上最新）"
    Say '  下次部署时脚本就能正确判断"本地是否落后"了。'

    Write-Host ''
    if ($backedUp -gt 0 -and -not $NoBackup) {
        Say "备份位置：$backupDir"
    }
    Ok '拉取完成，本地已同步到线上最新版本。'
    # 【提醒】拉取只下载代码，不会触发网站重建，也不会改动线上任何内容。
}

# ================================ 开始执行 ===================================
# 【说明】前面都是"定义工具和函数"，从这里开始才是真正的执行流程。
# 按顺序读下去，就能理解整个部署从头到尾做了什么。

try { Clear-Host } catch { }
# 清一下屏幕，让输出从干净的一屏开始，看得更清楚。
Write-Host ''
Write-Host '  王志满律师博客 · 一键部署' -ForegroundColor White
Write-Host "  项目目录：$Root" -ForegroundColor DarkGray
# 打印标题和当前项目目录。
# 【为什么显示目录？】"在错误的目录里运行"是常见失误，
# 把目录显示出来，您一眼就能发现自己是不是跑错了地方。

Head '环境检查'
# ---- 第 0 步：环境检查 ----
if (-not (Test-Path -LiteralPath (Join-Path $Root '_config.yml'))) {
    Die '这个目录里找不到 _config.yml，不像是博客项目。请确认 deploy.bat 放在项目根目录。'
}
# 【很有用的防呆检查】_config.yml 是网站总配置文件，
# 有它就说明确实在博客项目里。如果不做这个检查，
# 您万一把脚本放错目录，后面的操作会闹出很离谱的结果。
Ok '找到 Jekyll 项目文件'
Ok "PowerShell $($PSVersionTable.PSVersion)"
# 打印 PowerShell 版本，方便排查兼容性问题时参考。

if ($Status) { Show-Status; Write-Host ''; exit 0 }
# 如果您带了 -Status 参数，就只显示部署记录然后结束，不做任何改动。
# 【为什么放在这么靠前？】因为只想看状态时，不该打扰您去验证身份、更不该有任何写操作。

# ---------- 令牌准备 ----------
# 【什么情况需要令牌？】
#   · 正式部署：必须（要往线上提交内容）。
#   · 拉取 -Pull：必须（要读大量线上文件）。
#   · 预览 -DryRun：不是必须，但"有最好" —— 见下面说明。
#
# 【关于预览模式的一个改进】早期版本预览时完全不加载令牌（纯匿名只读）。
# 但 GitHub 对"匿名请求"的额度极低（同一 IP 每小时仅 60 次），
# 而预览要读取线上完整文件清单、比对几百个文件，多跑几次就会撞上限额，
# 报出令人困惑的 "HTTP 403"。所以现在改为：
#   只要本机已经存过令牌，预览时就顺手用上（额度 5000 次/小时，几乎不会用完）；
#   本机没存过令牌也能照常预览（退回匿名模式，第一次使用不会卡住）。
$needToken   = (-not $DryRun) -or $Pull
# 必须要令牌的情形（否则走不下去）。
$wantToken   = $needToken -or (Test-Path -LiteralPath $TokenFile)
# 值得用令牌的情形（预览时若本机有存货也直接用上）。

if ($SetToken -and $DryRun -and -not $Pull) {
    Die '-SetToken 不能和 -DryRun 一起用。'
    # 【逻辑冲突检查】-DryRun 是"只读预览、不做任何事"，
    # -SetToken 是"去改令牌文件"，两者性质矛盾。
    # 与其默默忽略一个，不如明确报错，避免您误以为设置成功了。
}

if ($wantToken) {
    if ($SetToken) { Remove-Item -LiteralPath $TokenFile -Force -ErrorAction SilentlyContinue }
    # 如果您带 -SetToken 参数，先把旧的令牌文件删掉。
    # 效果：下次就会跳过"用保存的令牌"，直接引导您重新填一个。
    # 这正是"更换令牌"的实现方式。

    if ($needToken) {
        # 必须拿到令牌：拿不到就直接停下（继续下去必然失败）。
        Head 'GitHub 身份验证'
        try { $script:Token = Get-Token } catch { Die $_ }
        Ok '身份验证通过'
    } else {
        # 预览模式且本机有令牌：静默用上，不打扰您，只为避免撞上匿名额度限制。
        try { $script:Token = Read-StoredToken } catch { $script:Token = $null }
    }
} else {
    # 本机没存过令牌，且只是预览 —— 允许匿名只读。
    Write-Host ''
    Warn '本机还没有保存 GitHub 令牌，将以"匿名"方式预览。'
    Say  '  匿名请求每小时额度很低（约 60 次），偶尔可能报 HTTP 403。'
    Say  '  若遇到，先正式部署一次（会引导你填令牌），之后预览就不会受限了。'
}

# ---------- 0.5 拉取模式（-Pull）：线上 → 本地 ----------
# 【为什么放在这里（身份验证之后）？】这一点非常重要：
#   拉取需要调用大量 GitHub 接口（取快照、比指纹、下载文件）。
#   如果没带令牌，这些请求会以"匿名身份"发出，而匿名请求额度极低
#   （同一 IP 每小时只有 60 次），很容易中途撞上限额、报 HTTP 403 失败。
#   所以必须等令牌加载完成（上面那段）之后，才能开始拉取。
if ($Pull) {
    Head '拉取线上最新代码到本地'
    if ($DryRun) {
        Warn '提示：-Pull 会真实写入本地文件，-DryRun 的"只预览"对拉取无效。'
        Say  '      也就是本次依然会把线上文件下载下来覆盖本地（有备份）。'
        Say  '      若只想"看看会拉取哪些文件"而不写入，请看下面的"对比结果"清单后按 Ctrl+C 中止。'
    }
    if ($NoBackup)    { Warn '已启用 -NoBackup：本次不备份被覆盖的文件。' }
    if ($Force)       { Warn '已启用 -Force：冲突文件将直接采用线上版本。' }
    if ($SkipWatch)   { Say  '（-SkipWatch 在拉取模式下无作用，可忽略）' }
    if ($SkipViews)   { Say  '（-SkipViews 在拉取模式下无作用，可忽略）' }
    if ($SkipData)    { Say  '（-SkipData 在拉取模式下无作用，可忽略）' }
    Write-Host ''
    try {
        Invoke-Pull
    } catch {
        Die "拉取失败：$_"
    }
    Write-Host ''
    exit 0
    # 拉取完成后直接结束，绝不继续走下面的部署流程。
    # 【这一点至关重要】否则"刚拉取完"紧接着"又推上去"，
    # 会白白产生一条内容相同的提交记录。
}

# ---------- 1. 刷新浏览量 ----------
if ($SkipViews) {
    Head '刷新文章浏览量'
    Warn '按你的要求跳过（-SkipViews）'
} elseif ($DryRun) {
    Head '刷新文章浏览量'
    Warn '预览模式下跳过，避免产生额外的查询记录'
    # 【设计得很细致的一点】预览模式下自动跳过浏览量刷新。
    # 【为什么？】因为每次查询都会让统计那个数字 +1，
    # 如果预览也去查一遍，就白白污染了数据。
    # 作者考虑到了这个细节，避免"只是想看看会改什么"却把浏览量弄虚了。
} else {
    try {
        Update-Views
    } catch {
        Warn "刷新浏览量时出错，已跳过：$_"
        # 【注意这里的宽容设计】刷新浏览量失败只警告、不中断。
        # 【为什么可以容忍？】因为这一步只是"锦上添花"，
        # 浏览量数据就算没更新成功，也不该阻止您发文章。
        # 分清"必须成功"和"尽力而为"，是写自动化脚本的重要思路。
    }
}

# ---------- 1.5 处理「跳过浏览量数据文件」开关 ----------
# 【这一步做了什么？】如果本次带了 -SkipData，就把那两个数据文件登记进"排除表"，
# 让下面的文件比对彻底无视它们（不对比、不上传、也不算删除）。
# 【注意执行顺序】必须放在"扫描本地文件"之前，否则排除规则来不及生效。
if ($SkipData) {
    foreach ($p in $DataFileRelPaths) {
        $SkipDataSelected[$p] = $true
        # 逐个登记进排除表。键是"相对路径"，值随便给个 $true 表示"要跳过"。
    }
    Head '跳过浏览量数据文件'
    Warn '按你的要求，本次不刷新、也不上传这两个文件（-SkipData）：'
    Say  '  · _data/views.json    （网页读取的浏览量数据）'
    Say  '  · _data/pv_state.json （内部纠错账本）'
    Say  '  它们将由 GitHub 上的定时任务继续维护，本地部署不插手。'
    # 【为什么要明确列出文件名？】因为"跳过数据同步"是个有副作用的操作，
    # 打印清楚到底跳过了什么，事后排查"为什么浏览量没更新"时一眼就能看到原因。
    # 【提醒】如果同时用了 -SkipViews，那连"刷新"也跳过了，
    # 这两个文件本次从头到尾都不会被碰（本地既不生成、也不上传）。
} else {
    $SkipDataSelected.Clear()
    # 没带 -SkipData 就保证排除表是空的（默认行为不变：这两个文件照常同步）。
    # 【为什么还要 Clear 一下？】因为 $SkipDataSelected 是脚本级变量，
    # 显式清空可以杜绝"万一被别处写入过"导致默认行为被意外改变。
}

# ---------- 2. 对比远程仓库 ----------
Head '对比线上仓库'
try {
    $remote = Get-RemoteSnapshot
} catch {
    Die "无法读取仓库信息：$_
请检查网络是否能访问 GitHub。"
    # 读不到线上信息就没法保证安全（不知道该不该覆盖），
    # 所以这里是"必须成功"，失败必须中止。
    # 提示里点明"检查网络"是因为这通常就是原因（国内访问 GitHub 有时不稳定）。
}
Ok "线上仓库共 $($remote.Blobs.Count) 个文件（基准提交 $($remote.CommitSha.Substring(0,7))）"
# 打印线上文件总数和当前版本编号（只显示前 7 位，后面太长没必要看）。

$localMap = @{}
foreach ($f in (Get-LocalFiles -Dir $Root)) { $localMap[$f.Rel] = $f.Full }
# 扫描本地所有需要同步的文件，做成一张"相对路径 → 本地真实路径"的对照表。
Say "  本地共 $($localMap.Count) 个文件待同步"
# 打印本地文件总数，方便和线上对比（差很多就说明有问题）。

$changed = New-Object System.Collections.ArrayList
# 准备一个清单，装"有变动、需要上传"的文件。
foreach ($rel in @($localMap.Keys | Sort-Object)) {
    # 逐个检查本地文件。（排序是为了结果稳定、便于查看。）
    $full = $localMap[$rel]
    $bytes = [IO.File]::ReadAllBytes($full)
    # 读取这个文件的全部内容。
    $sha = Get-GitBlobSha $bytes
    # 算出它的"指纹"。
    if ($remote.Blobs.ContainsKey($rel)) {
        # 线上也有这个文件（说明不是新增）。
        if ($remote.Blobs[$rel].Sha -ne $sha) {
            # 【核心判断】指纹不一样，说明内容被改过了，需要上传。
            [void]$changed.Add([PSCustomObject]@{
                Path = $rel; Kind = '修改'; Full = $full; Size = $bytes.Length
            })
            # 记下来：路径、类型是"修改"、本地路径、文件大小。
        }
        # 指纹相同就什么都不做 —— 说明内容一模一样，没必要传。
        # 【这正是这个脚本能快的原因】：只传真正变过的文件，
        # 而不是每次都把所有文件重新上传一遍。
    } else {
        # 线上没有这个文件，说明是新增的。
        [void]$changed.Add([PSCustomObject]@{
            Path = $rel; Kind = '新增'; Full = $full; Size = $bytes.Length
        })
    }
}

$deleted = New-Object System.Collections.ArrayList
# 准备一个清单，装"线上有、本地没有"的文件（也就是看起来应该删除的）。
foreach ($rel in @($remote.Blobs.Keys | Sort-Object)) {
    if (-not $localMap.ContainsKey($rel)) {
        # 线上有、本地没有。
        if (Test-ExcludedPath $rel) { continue }
        # 【重要】如果是"本该排除"的文件，就不要算作要删除的。
        # 【为什么必须跳过？】因为排除清单里的文件本来就不同步，
        # 本地当然没有。如果不跳过，每次都会报"要删一堆文件"，纯粹是虚惊。
        [void]$deleted.Add($rel)
        # 记入待删除清单。
        # 【注意】这里只是"记录"，还没有真的删任何东西。
        # 下面有好几道检查会决定它到底该不该删。
    }
}

# ---------- 2.5 线上 SHA 乐观锁：本地副本落后就中止 ----------
# 这两个文件由定时任务自动生成，本地每次部署也会重新生成，
# 所以「线上比本地新」不算落后，不触发中止。
$AutoGenFiles = @('_data/views.json', '_data/pv_state.json')
# 【这两条"豁免通行证"的作用】这两个文件是自动生成的数据文件，
# 线上定时任务会更新它们、本地部署时也会重新生成它们。
# 所以"线上版本比本地新"对这两个文件来说是正常现象，
# 不该被当成"我的副本落后了"而中止部署。

$baseline    = Read-Baseline
$lockBlocked = $false
# 标记"乐观锁是否亮红灯（需要中止）"，先假设一切正常。
$lockDel     = @()
$lockChg     = @()
# 两个清单：分别装"有冲突的删除项"和"有冲突的修改项"。

if ($ResetBaseline) {
    # ---- 特殊情况：您明确要求"重新记录基准" ----
    Write-Baseline $remote.CommitSha
    # 直接认定"我这份本地副本就是基于线上最新版本"。
    Ok "已重新记录本地基准：$($remote.CommitSha.Substring(0,7))（线上最新提交）"
    Warn '仅在确认这份本地副本确实是最新的之后才该这么做。'
    # 【为什么要特意警告？】因为这一步相当于"手动解除了安全闸"。
    # 如果您其实不是最新的，这么做之后旧副本就会被当成最新的，可能覆盖线上内容。
    # 所以脚本在这里明确提醒您"要确实确认过"。
    # 【正确的使用时机】您已经把线上最新副本重新下载、并把改好的内容合并进去了，
    # 此时运行 -ResetBaseline 重新建立基准，是正确的做法。
    $baseline = Read-Baseline
    # 重新读一遍，让下面的逻辑用上新基准。
}

if ($null -eq $baseline) {
    # ---- 情况一：从来没有基准记录（比如第一次用本脚本） ----
    Warn '本机还没有「基准提交」记录，无法证明这份副本是最新的。'
    if ($deleted.Count -gt 0) {
        $lockBlocked = $true
        # 【这里判断得很精明】没有基准、又准备删文件 → 风险最高，必须停下。
        # 因为"不知道自己的副本从哪来" + "要删东西"，
        # 万一删的正是别人刚加的内容，就真的丢东西了。
    } else {
        Say '  本次不会删除任何线上文件，先继续；部署成功后会自动记录基准。'
        # 没有基准但不删任何东西 → 相对安全，可以继续。
        # 【为什么可以放心？】因为只是新增或修改自己的文件，
        # 最坏情况也只是覆盖了自己改的东西，不会误删别人的内容。
        # 而且部署成功后会自动记下基准，下次就有保护了——
        # 这意味着"第一次使用"的体验很顺畅，不会被卡住。
    }
} elseif ($baseline.sha -ne $remote.CommitSha) {
    # ---- 情况二：基准和线上最新不一致（说明中间线上有变化） ----
    # 【这是最关键的一类情况】需要查清楚"中间到底改了什么"。
    $div = Get-Divergence -BaseSha $baseline.sha -HeadSha $remote.CommitSha
    # 问 GitHub："从我记录的那版到现在，中间改了什么？"
    if (-not $div.Ok) {
        # 查不到比对结果（比如那个版本记录已经不存在了）。
        $lockBlocked = $true
        Warn "本地基准 $($baseline.sha.Substring(0,7)) 已无法与线上比对：$($div.Reason)"
        # 【这里的取舍很明智】"查不清楚"就应该保守处理、停下。
        # 因为无法确认安全性时，宁可让您多走一步，也不要冒丢内容的险。
    } else {
        # 查到了，开始判断这些变化是否构成冲突。
        $divSet = @{}
        foreach ($f in $div.Files) { $divSet[$f] = $true }
        # 把"线上改过的文件路径"整理成一张便于快速查找的表。
        # 【为什么要做成表？】因为后面要对每个文件反复检查"在不在里面"，
        # 用表来查比每次遍历一遍清单快得多。
        $lockDel = @($deleted | Where-Object {
            $divSet.ContainsKey($_) -and ($AutoGenFiles -notcontains $_)
        })
        # 【核心判断一】找出"这次要删的" ∩ "线上新改过的"。
        # 意思就是：某个文件线上刚被改过，而您本地没有它、准备把它删掉。
        # 这正是最危险的情况——您可能正在删除别人刚加的内容！
        # 同时排除掉那两个自动生成的数据文件（它们不算真正的冲突）。
        $lockChg = @($changed | Where-Object {
            $divSet.ContainsKey($_.Path) -and ($AutoGenFiles -notcontains $_.Path)
        })
        # 【核心判断二】找出"这次要改的" ∩ "线上新改过的"。
        # 意思就是：某个文件线上刚被改过，而您本地也有一份准备覆盖上去。
        # 这说明您手上那份可能已经过时了，覆盖上去就会丢掉线上的改动。
        if ($lockDel.Count -gt 0 -or $lockChg.Count -gt 0) {
            $lockBlocked = $true
            # 发现任何冲突，就亮红灯、准备中止。
        } else {
            Say "  线上有 $($div.Commits) 个新提交，但都只涉及自动生成的浏览量数据，基准已自动跟进。"
            Write-Baseline $remote.CommitSha
            # 【这是一个很顺畅的日常场景】线上确实有新提交，
            # 但那些提交只是定时任务更新的浏览量数据，和您的内容无关。
            # 这种情况完全不需要打扰您，直接把基准更新跟进即可。
            # 【为什么这个判断很重要？】因为定时任务一天要跑好几次，
            # 如果每次都被当成冲突、天天弹警告，那这个安全闸就太吵了，
            # 反而会让人养成"看到警告直接跳过"的坏习惯，那就失去意义了。
            # 作者把它区分出来，做到了"该严的地方严，该放的地方放"。
        }
    }
} else {
    # ---- 情况三：基准和线上完全一致（最理想的情况） ----
    Say "  本地基准 $($baseline.sha.Substring(0,7)) 与线上最新一致，可以安全部署。"
    # 说明您这份副本就是基于线上最新版本做的改动，不可能冲突。
}

if ($lockBlocked) {
    # ---- 乐观锁亮红灯，进入"中止并解释清楚"的流程 ----
    if ($AllowStale) {
        # 您明确表示"我知道有风险，但我就是要覆盖线上"。
        Write-Host ''
        Warn '已按 -AllowStale 跳过乐观锁：本次会用本地副本覆盖线上内容。'
        # 尊重您的决定，但再提醒一次风险。
    } else {
        # 默认行为：中止，并尽力把情况解释清楚。
        Write-Host ''
        Fail '已中止：本地副本落后于线上，继续部署会覆盖或删除线上内容。'
        Write-Host ''
        if ($lockChg.Count -gt 0) {
            Say '  线上改过、本次会被本地旧版本覆盖的文件：'
            foreach ($c in $lockChg) { Write-Host "      $($c.Path)" -ForegroundColor Yellow }
            # 列出具体是哪些文件会被旧版本覆盖。
            # 【为什么要列出来？】只说"有冲突"您没法判断该怎么处理；
            # 列出文件名，您就能回想起"哦这个是我在网页上改过的"，从而做出正确决定。
        }
        if ($lockDel.Count -gt 0) {
            Say '  线上新增或改过、本次会被删除的文件：'
            foreach ($d in $lockDel) { Write-Host "      $d" -ForegroundColor Red }
            # 列出会被删除的文件，用红色强调（这是最需要警惕的情况）。
        }
        if ($lockChg.Count -eq 0 -and $lockDel.Count -eq 0) {
            Say '  本机缺少有效的「基准提交」记录，无法证明这份副本是最新的；'
            Say '  而本次又要删除线上文件，风险太高，先停下来。'
            # 这是"没有基准 + 要删东西"那种情况，单独解释一下原因。
        }
        if ($null -ne $baseline) {
            Say "  本地基准：$($baseline.sha.Substring(0,7))（记录于 $($baseline.updated)）"
            # 显示基准的时间和编号，让您了解自己这份副本有多旧。
        }
        Say "  线上最新：$($remote.CommitSha.Substring(0,7))"
        Write-Host ''
        Say '  正确做法：'
        Say '    ① 到 GitHub 仓库页 → Code → Download ZIP，重新下载线上最新副本并解压；'
        Say '       （或者在这台电脑上用 git pull 拉取最新）'
        Say '    ② 把你要改的内容放进这份最新副本，然后运行：  .\deploy.ps1 -ResetBaseline'
        Say '    ③ 再运行：  .\deploy.ps1'
        Write-Host ''
        Say '  如果你确定这份本地副本才是最新的、就是要覆盖线上：'
        Say '       .\deploy.ps1 -AllowStale'
        # 【这段是全文最有价值的部分之一】它不只说"出错了"，
        # 而是直接给出"该怎么解决"的三步操作。
        # 对不熟悉 Git 的人来说，"请先 pull"这种话等于没说；
        # 而"去网页点 Download ZIP"是任何人都能照着做的。
        Die '已中止，线上内容保持原样，没有被破坏。'
        # 最后强调一句"线上没被破坏"，让您安心。
        # 【这一点非常关键】出错时最怕的是"不知道有没有搞坏东西"。
        # 这个脚本的设计确保:一旦发现风险，就在动手之前停下，线上始终完好。
    }
}

$addedCount   = @($changed | Where-Object { $_.Kind -eq '新增' }).Count
$changedCount = @($changed | Where-Object { $_.Kind -eq '修改' }).Count
# 数一下新增几个、修改几个（用于下面显示汇总）。

Write-Host ''
if ($changed.Count -eq 0 -and $deleted.Count -eq 0) {
    Ok '本地内容和线上完全一致，不需要部署。'
    Write-Host ''
    exit 0
    # 【一个很实用的判断】如果两边完全一样，就什么都不做、直接结束。
    # 好处：不会产生一条"什么都没改"的无意义提交记录，仓库历史保持干净。
    # 您重复运行部署脚本也不会出问题（这叫"幂等"）。
}

Say "  待上传：新增 $addedCount 个，修改 $changedCount 个"
Say "  待删除：$($deleted.Count) 个"
Write-Host ''

foreach ($c in $changed) {
    $color = if ($c.Kind -eq '新增') { 'Green' } else { 'Yellow' }
    # 新增用绿色、修改用黄色（一眼能区分）。
    Write-Host ("    + {0,-9} {1}  ({2:N1} KB)" -f $c.Kind, $c.Path, ($c.Size / 1KB)) -ForegroundColor $color
    # 打印一行，形如：    + 新增      _posts/xxx.md  (3.5 KB)
    # {2:N1} 表示"以数字格式显示、保留 1 位小数"，把字节数换算成 KB 更好读。
}
foreach ($d in $deleted) {
    Write-Host ("    - 删除      $d") -ForegroundColor Red
    # 用红色打印将被删除的文件（醒目提示）。
}

if ($DryRun) {
    Write-Host ''
    Ok '预览结束：以上就是要改动的内容。'
    Say '  这次没有上传任何东西。去掉 -DryRun 就会真正部署。'
    Write-Host ''
    exit 0
    # 【这就是 -DryRun 预览模式的出口】
    # 前面所有计算都做完了（该显示的都显示了），但没有任何写操作，
    # 在这里干净地结束。
    # 【什么时候特别有用？】第一次用、或者改动比较大时，
    # 先跑 -DryRun 看看会动哪些文件，确认没问题再真部署，心里踏实得多。
}

# ---------- 3. 删除确认 ----------
function Confirm-Deletions {
    # 这个函数的作用：如果本次涉及删除文件，就停下来问您确认。
    # 【这是第二道安全闸】前面那道防的是"本地副本过时"，
    # 这道防的是"操作本身的破坏性"——
    # 哪怕基准检查通过了，删文件这件事也值得再确认一次。
    param(
        [object[]] $Deleted,
        [switch] $Yes
    )
    # 规则一：只要涉及任意 .md 文件（文章 / 页面）的删除，一律确认，-Yes 也绕不过。
    # 规则二：删除非 .md 文件达到 5 个以上时确认（-Yes 可跳过）。
    # 【为什么要分两档？】因为风险等级不同：
    #   .md 是您的文章，删错了就是文字内容真的没了，必须严格把关；
    #   图片、配置等其他文件删错了相对好恢复，问一次就行、且允许用 -Yes 省事。
    $mdDeletes = @($Deleted | Where-Object { $_ -like '*.md' })
    # 从待删除清单里挑出所有 .md 文件。

    if ($mdDeletes.Count -gt 0) {
        # ---- 涉及文章删除，最高级别警惕 ----
        Write-Host ''
        Warn "本次会从线上删除 $($mdDeletes.Count) 个 .md 文件（文章或页面）："
        foreach ($m in $mdDeletes) { Write-Host "      - $m" -ForegroundColor Red }
        # 逐个列出文件名（红色），让您看清楚要删什么。
        Write-Host ''
        Say '  常见误判：这些文章其实是在 GitHub 网页上删掉的，而你手里这份'
        Say '  本地副本比线上旧，脚本就以为「线上有、本地没有」。'
        # 【这段话点出了最可能的误报原因】帮您正确判断，避免误删。
        Say '  请先到 GitHub 确认这些文章确实是不需要的。'
        if ($Yes) { Warn '你用了 -Yes，但删除 .md 文件仍然必须确认。' }
        # 明确告知 -Yes 在这里无效，避免您以为加了参数就跳过了。
        $ans = Read-Host '  确认无误请输入 DELETE 并回车继续，其它任意输入取消'
        # 【设计得很巧妙】要求输入一个完整的英文单词 DELETE 才能继续。
        # 而不是简单的"按 y 继续"——因为随手回车太容易了，
        # 这种"要打字才能通过"的方式能有效防止手滑。
        if ($ans -ne 'DELETE') {
            Say '  如果这些文件在线上是最新的，请先同步线上副本，再运行：  .\deploy.ps1 -ResetBaseline'
            return $false
            # 您没有输入 DELETE，就取消。
            # 顺便告诉您正确的解决方式（先同步线上副本）。
        }
        return $true
        # 确认了，允许继续。
    }

    if ($Deleted.Count -ge 5 -and -not $Yes) {
        # ---- 删除数量偏多，问一次 ----
        Write-Host ''
        Warn "这次会从线上删除 $($Deleted.Count) 个文件，数量偏多。"
        $ans = Read-Host '  确认要删除这些文件吗？输入 y 继续，其它任意键取消'
        if ($ans -notmatch '^[yY]') { return $false }
        # 检查输入的第一个字符是不是 y 或 Y（允许"y"、"yes"、"Y" 都行）。
        # -notmatch 表示"不匹配"，也就是"不是以 y 开头"就取消。
    }
    return $true
    # 没触发上面任何询问条件（比如只删一两个普通文件），就默认允许。
}

if (-not (Confirm-Deletions -Deleted $deleted -Yes:$Yes)) {
    Write-Host ''
    Say '已取消，没有做任何改动。'
    Write-Host ''
    exit 0
    # 您取消了，就干净地结束，线上没有任何变化。
}
# 【注意】上面函数名里的 -Yes:$Yes 这种写法，
# 表示"把您传入的 -Yes 开关原样转交给函数"。
# 您没加 -Yes 时，函数收到的就是"否"，从而会弹询问。

# ---------- 4. 组装并推送提交 ----------
$commitMsg = if ($Message) { $Message } else { "更新站点内容 - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
# 决定这次提交的说明文字。
# 您用 -Message 指定了就用您的；没指定就自动生成"更新站点内容 - 日期时间"。
# 【为什么要有默认值？】这样您平时什么都不用填，但想留个备注时也随时能加。

Head '上传并提交'
# 【下面这一整段是全文技术含量最高的部分：用 GitHub 接口模拟一次 Git 提交】
# 为了理解它，先了解一次 Git 提交在 GitHub 内部是怎么组成的：
#   ① blob   —— 每个文件的内容（先单独上传）
#   ② tree   —— 一份文件清单（把各个 blob 按路径组织起来）
#   ③ commit —— 一次提交（把 tree 和"上一次提交"串起来，形成历史链条）
#   ④ ref    —— 分支书签（让它指向这个新的 commit）
# 所以下面就是按这四步依次调用接口。
# 【为什么不能一次性完成？】因为这是 Git 数据模型的固有结构，
# GitHub 接口只是把这个结构暴露出来，必须按它的规矩一层层搭。
$newCommitSha = $null
# 用来存最终生成的新提交编号。
$attempts = 0
# 已尝试次数。
while ($attempts -lt 3 -and -not $newCommitSha) {
    # 最多尝试 3 次，成功（拿到新提交编号）就结束。
    # 【为什么要重试？】因为线上可能同时有定时任务在提交浏览量数据，
    # 导致我们的提交被拒绝（提示"仓库已被更新"）。
    # 这种情况重试一次，用最新的状态重新提交就能成功。
    $attempts++
    try {
        $treeEntries = New-Object System.Collections.ArrayList
        # 准备"文件清单"的条目集合。
        $n = 0
        foreach ($c in $changed) {
            # ---- 第 ① 步：把每个有变动的文件内容逐个上传 ----
            $n++
            Write-Host ("    ({0}/{1}) 上传 {2}" -f $n, $changed.Count, $c.Path)
            # 显示进度，形如 (3/12) 上传 _posts/xxx.md
            # 【为什么需要显示进度？】如果改了很多文件、还有大图片，
            # 这个过程可能要花几十秒，没有反馈会让人以为卡住了。
            $bytes = [IO.File]::ReadAllBytes($c.Full)
            # 读取文件内容。
            $b64 = [Convert]::ToBase64String($bytes)
            # 转成 Base64 文本。
            # 【为什么要转？】因为网络接口传输文本更方便，
            # 而文件里可能包含各种特殊字节（图片、二进制），
            # Base64 能把它们安全地表示成纯文本，传过去再还原回来。
            $blob = Invoke-GitHub -Method POST -Path "/repos/$Repo/git/blobs" `
                -Body @{ content = $b64; encoding = 'base64' }
            # 上传这个文件，拿回它的"编号"（后面清单里要用这个编号来引用它）。
            # encoding = 'base64' 是告诉对方"我传的内容是 Base64 编码的"。
            $mode = if ($remote.Blobs.ContainsKey($c.Path)) { $remote.Blobs[$c.Path].Mode } else { '100644' }
            # 决定这个文件的"权限模式"：
            #   如果线上原本就有这个文件，就沿用它的原权限（避免改坏）；
            #   如果是新文件，就用 100644（意思是"普通文件、可读写"）。
            # 【为什么要沿用？】万一某个文件原本设了特殊权限，
            # 我们不该在这次提交里悄悄把它改掉。
            [void]$treeEntries.Add(@{ path = $c.Path; mode = $mode; type = 'blob'; sha = $blob.sha })
            # 把这个文件记进"新清单"里：路径、权限、类型、内容编号。
        }
        foreach ($d in $deleted) {
            # ---- 删除文件也是同样的方式 ----
            [void]$treeEntries.Add(@{ path = $d; mode = '100644'; type = 'blob'; sha = $null })
            # 【关键技巧】把它的内容编号设成"空"（$null），
            # Git 就会理解为"这个文件在新清单里没有内容了"，
            # 效果等同于删除它。
            # 也就是说：Git 里其实没有"删除"这个操作，
            # "从清单里去掉内容"就是删除。
        }

        $newTree = Invoke-GitHub -Method POST -Path "/repos/$Repo/git/trees" `
            -Body @{ base_tree = $remote.TreeSha; tree = @($treeEntries) }
        # ---- 第 ② 步：生成新的文件清单 ----
        # 【base_tree 的含义】表示"以线上那份清单为基础"，
        # 然后只把上面这些条目（新增/修改/删除）应用上去。
        # 【为什么要这样？】这样就不用把仓库里所有文件都重新列一遍——
        # 没提到的文件（比如一堆没改过的图片）会自动保持不变。
        # 既省事又省流量。

        $commitBody = @{
            message = $commitMsg
            tree    = $newTree.sha
            parents = @($remote.CommitSha)
        }
        # ---- 第 ③ 步：生成新提交记录 ----
        # 三个要素：
        #   message 提交说明（下次看历史时能知道这次改了什么）
        #   tree    刚才生成的清单编号
        #   parents 【关键】上一次提交的编号
        # 有了 parents，新旧提交就串成了一条链，形成完整的版本历史。
        $newCommit = Invoke-GitHub -Method POST -Path "/repos/$Repo/git/commits" -Body $commitBody
        # 提交，拿回新提交的编号。

        $null = Invoke-GitHub -Method PATCH -Path "/repos/$Repo/git/refs/heads/$Branch" `
            -Body @{ sha = $newCommit.sha; force = $false }
        # ---- 第 ④ 步：把分支书签指向新提交 ----
        # 【最后一步才移动书签，这一点很重要】
        # 前面所有准备动作都不影响线上（线上还指向旧提交）；
        # 直到这一下移动书签，新内容才真正生效。
        # 这意味着：如果前面任何一步失败了，线上完全不受影响。这是很稳健的设计。
        # force = $false 表示"不允许强制覆盖"。
        # 【这是在防什么？】万一在这几秒里有别人提交了新内容，
        # 我们这次移动书签就会被拒绝（而不是悄悄把对方的内容冲掉）。
        # 这正是下面那个重试逻辑存在的意义。

        $newCommitSha = $newCommit.sha
        # 记下新提交编号，循环条件不满足，自然结束。
    } catch {
        $msg = "$_"
        if ($attempts -lt 3 -and ($msg -match 'HTTP 422' -or $msg -match 'HTTP 409' -or $msg -match 'fast forward')) {
            Warn '仓库刚才被更新过（可能是定时的浏览量任务），正在自动重试…'
            Start-Sleep -Seconds 3
            $remote = Get-RemoteSnapshot
            continue
            # 【这段是"乐观锁"的自动补救】
            # 出现这几种错误说明：我们的提交被拒绝了，
            # 因为在这几秒内线上又有了新提交（典型场景就是定时任务刚好在提交浏览量数据）。
            # 处理办法很聪明：重新读取线上的最新状态（$remote = ...），
            # 等 3 秒后再试一遍——这次就是用最新的状态来提交，
            # 冲突自然就解决了。
            # 【为什么要重新读？】因为我们这次提交要基于"线上当前是什么样"来做，
            # 状态变了就必须重新获取，否则还会失败。
            # 【这段的意义】它让"定时任务抢占"这种日常小冲突能被自动消化掉，
            # 不需要打扰您。只有真正严重的冲突才会停下来问。
        }
        Write-Host ''
        Fail "上传失败：$msg"
        if ($msg -match 'workflow') {
            Warn '看起来是令牌缺少 workflow 权限，无法更新 .github/workflows 下的文件。'
            Warn '请到 https://github.com/settings/tokens 重新勾选 workflow 权限后，运行：  .\deploy.ps1 -SetToken'
            # 【很实用的错误诊断】错误信息里含 workflow 字样，
            # 就基本可以断定是令牌权限不够。
            # 直接告诉您去重新生成令牌、并给出更换令牌的命令，一步到位。
        }
        Die '部署中断，线上内容保持原样，没有被破坏。'
        # 其他错误就中止（比如网络断了）。
        # 同样强调"线上没被破坏"——因为最后一步没执行，线上确实一点没变。
    }
}

Ok "提交成功：$($newCommitSha.Substring(0,7))  说明：$commitMsg"
# 打印成功信息：新提交编号（只显示前 7 位）和提交说明。
# 【这里的编号很有用】您可以去 GitHub 的提交记录里按这个编号找到这次改动。

# 记录本次提交为新的本地基准（下次部署时用它判断本地副本是否落后）
try {
    Write-Baseline $newCommitSha
    Say "  已记录本地基准：$($newCommitSha.Substring(0,7))"
    # 【这一步是安全闸能持续有效的原因】
    # 每次部署成功后都把基准更新到最新，这样下次部署时，
    # 判断的就是"从现在到那时的变化"，范围小、判断准。
    # 如果一直不更新，基准会永远停在第一次，每次都会报一堆冲突。
} catch {
    Warn "记录本地基准失败，下次部署会提示基准缺失：$_"
    # 万一记不上（比如磁盘写不进去），只是警告。
    # 后果是下次部署会提示"没有基准"，稍微麻烦一点，但不会出安全事故。
}

# ---------- 5. 等待构建 ----------
if ($SkipWatch) {
    Head '等待 GitHub 构建与发布'
    Warn '按你的要求跳过（-SkipWatch）'
    Say  "  稍后到这里看结果：$ActionsUrl"
    # 您选择了不等，就给出查看地址让您自己去看。
    # 【什么时候用？】赶时间、或者只是想赶紧把内容发出去，
    # 不想在电脑前等那两三分钟。
} else {
    Wait-Deploy -Sha $newCommitSha
    # 盯着看构建什么时候完成，并报告结果。
    Test-LiveSite
    # 构建完成后，真去访问一下网站确认能打开。
}

Write-Host ''
Write-Host '------------------------------------------------------------' -ForegroundColor DarkGray
Ok '部署流程结束'
Say "  网站首页：$SiteUrl"
Say "  构建记录：$ActionsUrl"
Say '  小提示：页面有缓存，看到旧内容时按 Ctrl+F5 强制刷新即可。'
Write-Host ''
# 最后打印一个清爽的收尾块：
#   网站首页（直接点开验收）、
#   构建记录（万一有问题来这儿看）、
#   以及那条很实用的小提示——
# 【为什么要提示 Ctrl+F5？】浏览器为了加快打开速度会记住旧页面，
# 您发完文章打开网站发现"怎么还是旧内容"，第一反应会以为是部署失败，
# 其实按一下 Ctrl+F5 强制刷新就对了。
# 提前把这一点说明，能避免很多无谓的困惑。
