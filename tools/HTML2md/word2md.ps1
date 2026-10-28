<#
================================================================================
  word2md.ps1  ——  Word / HTML 转 Markdown（自动加表头），零安装、双击即用
================================================================================

【这个文件是干什么的】
  把稿件转成博客能直接用的 .md 文章，支持两种来源：
    · Word 文档（.docx）
    · 网页文件（.html / .htm）—— 整页源码、富文本片段都行
  自动写好标题、日期、分类、标签，自动把标题层级、加粗、表格、图片、
  网址全部改成 Markdown 格式。

【HTML 是怎么转的】
  标题  h1~h6 标签        →  # ~ ######（网页大标题会被认成文章标题）
  加粗  b / strong        →  **加粗**
  斜体  i / em            →  *斜体*
  链接  a 标签            →  [文字](网址)；文字和网址一样的写成 <网址>
  图片  img 标签          →  ![说明](网址)，图床图片自动补压缩后缀
  表格  table / tr / td   →  Markdown 表格，第一行当表头
  列表  ul / ol / li      →  - 列表 / 1. 列表（嵌套自动缩进）
  引用  blockquote        →  > 引用
  代码  pre / code        →  三个反引号的代码块
  导航 / 页脚 / 侧边栏 / 脚本 / 样式 → 自动丢掉，不会混进正文
  另外会自动找 <article>、.post-content 这类正文容器，只取正文

【正文里那行标题，删还是留 —— 可自选】
  程序会自动认出文章标题，写进 md 开头的表头（title）。
  至于「正文里原来那行标题」怎么处理，每次运行都会问一句：
    1) 删掉（默认）—— 网页顶部已经是标题了，正文再来一遍就重复
    2) 保留 —— 正文开头照样留着这条标题
  一次回答，本次所有文件都按这个来。
  不想被问、直接指定，命令行加 -KeepTitle（保留）即可，例如：
    powershell -File word2md.ps1 稿件.docx -KeepTitle -Yes

【不要直接双击这个文件】
  请双击同目录下的「5-Word或HTML转Markdown.bat」，它会以正确方式启动本脚本。
  原因：Windows 默认禁止运行 .ps1 脚本，bat 里已经帮你加了放行参数。

【它依赖什么】
  什么都不用装。只用 Windows 自带的 PowerShell 和 .NET，
  不需要 Python、不需要 Word、不需要联网、不需要安装任何软件。

【转换规则一览】
  Word 标题 1/2/3      →  # / ## / ###        （自动识别，层级原样保留）
  加粗 / 斜体           →  **加粗** / *斜体*
  超链接               →  [链接文字](https://...)
  正文里手打的裸网址     →  <https://...>       （自动变成可点击链接，Word 和 HTML 稿都一样）
  正文里手打的邮箱       →  <name@example.com>
  表格                 →  Markdown 表格，自动补齐表头行
  自动编号 / 项目符号    →  1. 列表 / - 列表
  引用段落             →  > 引用
  图片                 →  导出到 assets/img/文章编号/ 并压缩（见下）

【图片是怎么处理的】
  分两种情况：

  ① 图片是「网络图片」——比如从搜狐图床复制过来的链接
     自动在网址后面补上压缩参数，让服务器当场缩图，读者少下载 9 成流量：
       xxx.jpeg  →  xxx.jpeg?x-oss-process=image/resize,w_1000/format,webp
     已经带参数的会更新宽度，不会重复叠加。
     （想加别的图床域名，改下面 $OSS_HOSTS 那一行即可）

  ② 图片是「嵌在 Word 文件里的」
     导出时真实压缩：宽度超过 1000 像素自动等比缩小，
     JPEG 按 85% 质量重新保存，通常能瘦掉 60%~90%。
     压缩后原始尺寸的照片、截图都还能看清字。

【生成的文件在哪 —— 自动判断，不用你选】
  ① 放在博客的 tools 文件夹里用（现在这种用法，能直接发布）
      文章：_posts\2026-10-28-post-051.md   （编号自动往后接，不会撞车）
      图片：assets\img\post-051\xxx.jpg     （跟着文章编号走，好删好管）

  ② 把本文件夹拷到任何地方、任何一台电脑上单独用（便携模式）
      文章：本文件夹\输出\2026-10-28-post-001.md
      图片：本文件夹\输出\assets\img\post-001\xxx.jpg
      判断依据：往上找不到 _config.yml，就自动进便携模式，不会报错、不会问你。
      要拿回博客：md 拖进 _posts，输出\assets 里的 img 文件夹拖进博客的 assets\img。

  ③ 想自己指定存哪儿：加 -OutDir "D:\我的输出"

【万一出问题】
  · Word 只认 .docx。老的 .doc 请先用 Word「另存为」选 .docx 再转。
  · 网页文件 .html / .htm 直接拖进来就行；手机上存的网页如果是一整个文件夹，
    把里面的 .html 拖进来即可，图片是网络地址，不用一起拷。
  · 转换不动你的原件，原文件一个字节都不会改。
  · 网页里的脚本、广告、导航会自动跳过；万一还是混进了奇怪的东西，
    用「6-文章编辑器.html」打开生成的 md，左边删掉就行。
  · 分栏、文本框、艺术字、批注、页眉页脚、脚注、公式这些，
    Markdown 本身没有对应语法，会被忽略 —— 这不是故障。
================================================================================
#>

[CmdletBinding()]
param(
    # 要转换的 .docx 文件，可以给多个，也可以给一个文件夹
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Files,

    [string]$Title,        # 文章标题（不给就从 Word 里认）
    [string]$Category,     # 分类，例如 "工作/诉讼实务"
    [string]$Tags,         # 标签，多个用逗号隔开
    [string]$Date,         # 发布日期，例如 2026-10-28
    [string]$Slug,         # 文件名编号，例如 post-051（默认自动续号）

    [switch]$Yes,          # 一个问题都不问，全部用默认值
    [switch]$DryRun,       # 只预览，不写任何文件
    [switch]$KeepTitle,    # 保留正文里被认成标题的那一行（默认删掉，避免标题显示两遍）

    [int]$MaxWidth = 1000, # 图片最大宽度（像素）
    [int]$MaxHeight = 3000,# 图片最大高度（像素），防超长截图
    [int]$JpegQuality = 85, # JPEG 压缩质量，1~100

    [string]$Root = '',    # 博客根目录（bat 会自动传进来，一般不用自己写）

    # 只想要 md 文件，不在这里发布？用它指定输出目录。
    # 不给时会自动判断：在博客里就进 _posts，不在博客里就进本工具文件夹的「输出」。
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'

# 关掉解压时的进度条，否则一行行进度会把转换结果刷得看不见
$ProgressPreference = 'SilentlyContinue'

# 在「非中文的 Windows」上，控制台默认编码装不下汉字，提示会变成一串问号。
# 碰到这种系统就临时切到 UTF-8；中文 Windows 不动它（切了反而可能影响粘贴中文路径）。
try {
    $encNow = [Console]::OutputEncoding
    if ($encNow -and $encNow.GetBytes([string][char]0x4FBF)[0] -eq 63) {
        try { & chcp.com 65001 > $null } catch { }
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    }
} catch { }

# =============================================================================
# 一、常量
# =============================================================================

# Word 内部 XML 各部分的命名空间（.docx 就是个 zip，里面装着这些 XML）
$W  = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
$RN = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
$A  = 'http://schemas.openxmlformats.org/drawingml/2006/main'
$WP = 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'
$V  = 'urn:schemas-microsoft-com:vml'

# 特殊占位字符（Markdown 里不会出现，用来标记位置）
$AUTO  = [string][char]1   # 自动链接占位
$BREAK = [string][char]2   # 段落内软换行
$IMGT  = [string][char]3   # 图片占位
$IMGSEP = [string][char]4  # 图片占位内部分隔（alt 与路径之间）

# 支持「网址加参数就缩图」的图床域名。
# 这些图床底层是阿里云 OSS，改网址就能让服务器当场缩图 + 转 WebP。
# 以后换用别的图床，把支持 OSS 参数的域名加进来即可，例如：
#   'itc.cn', 'aliyuncs.com', 'myqcloud.com'
$OSS_HOSTS = @('itc.cn')

# 你博客现有的分类体系（一级 3 个 / 二级共 13 个）
# 交互问答时列出来给用户挑，避免手打错别字把归类页弄裂
$CATEGORY_TREE = [ordered]@{
    '工作' = @('诉讼实务', '案例复盘', '非诉实务', '文书模板', '办案工具', '法律科普', '执业成长')
    '生活' = @('日常随笔', '爱妻日常', '办事指南')
    '学习' = @('建站笔记', '工具教程', '思考随记')
}

# 全局状态（PowerShell 里跨函数共享用 $script: 作用域最省事）
$script:S = @{
    Root       = ''
    PostsDir   = ''
    AssetsBase = ''     # 图片总目录：博客里是 assets\img，便携模式下是 输出\assets\img
    Mode       = 'blog' # blog = 直接写进博客；portable = 便携模式（输出到本文件夹）
    DryRun     = $false
    MaxWidth   = 1000
    MaxHeight  = 3000
    JpegQuality = 85
    WorkDir    = ''      # docx 解压出来的临时目录
    ZipRoot    = ''
    Rels       = $null
    Styles     = $null
    Numbering  = $null
    AssetsDir  = ''      # 当前文章图片输出目录
    ImgRel     = ''      # 当前文章图片在网站上的网址前缀
    Images     = 0       # 本次导出的图片数量
    ImageSaved = 0       # 其中压缩过的数量
    DrawingOk  = $null   # 图片压缩能力是否可用（null = 还没试过）
    AutoUrls   = $null
    KeepTitle  = $false  # $true = 正文开头的标题行保留下来，$false = 删掉
    TriedRoots = $null   # 找不到博客目录时，把找过的路径记下来用于提示
    NL         = "`r`n"
}

# =============================================================================
# 二、输出小工具
# =============================================================================

function Write-Line([string]$text) { Write-Host $text }
function Write-Head([string]$text) {
    Write-Host ''
    Write-Host ('=' * 64)
    Write-Host ('  ' + $text)
    Write-Host ('=' * 64)
}
function Write-Note([string]$text) { Write-Host ('  ' + $text) }

# =============================================================================
# 三、通用小工具
# =============================================================================

# 找博客根目录（判断标准：目录里有 _config.yml）。
# 路径这种事不能靠猜，所以按可信程度依次试：
#   1. bat 直接告诉我们的 -Root（最可靠）
#   2. 本脚本自己所在的目录
#   3. 当前所在的目录
# 每一轮都从该目录开始一层层往上找，找到含 _config.yml 的那层就是博客根目录。
function Find-Root {
    $cands = New-Object System.Collections.ArrayList
    if ($Root) { [void]$cands.Add($Root) }
    if ($PSScriptRoot) { [void]$cands.Add($PSScriptRoot) }
    if ($PSCommandPath) { [void]$cands.Add((Split-Path -Parent $PSCommandPath)) }
    [void]$cands.Add((Get-Location).Path)

    $tried = New-Object System.Collections.ArrayList
    foreach ($c in $cands) {
        if (-not $c) { continue }
        $p = $c
        # 把 tools\.. 这种带「..」的写法先换算成真正的完整路径
        try { $p = [System.IO.Path]::GetFullPath($c) } catch { }
        for ($i = 0; $i -lt 8; $i++) {
            [void]$tried.Add($p)
            if (Test-Path -LiteralPath (Join-Path $p '_config.yml')) { return $p }
            $parent = Split-Path -Parent $p
            if (-not $parent -or $parent -eq $p) { break }
            $p = $parent
        }
    }

    # 真找不到时，把「找过哪儿」记下来，报错时好排查
    $script:S.TriedRoots = $tried
    return ''
}

# 判断某个目录是不是博客根目录（标准：里面有 _config.yml）
function Test-BlogRoot([string]$dir) {
    if (-not $dir) { return '' }
    $d = $dir.Trim().Trim('"').Trim("'").TrimEnd('\', '/')
    if (-not $d) { return '' }
    try { $d = [System.IO.Path]::GetFullPath($d) } catch { return '' }
    if (Test-Path -LiteralPath (Join-Path $d '_config.yml')) { return $d }
    return ''
}

# 工具被复制到别处（比如桌面）时，把博客目录记在脚本旁边，下次直接读
function Get-RootMemoPath {
    if ($PSScriptRoot) { return (Join-Path $PSScriptRoot 'word2md.root.txt') }
    return ''
}
function Read-RootMemo {
    $f = Get-RootMemoPath
    if (-not $f -or -not (Test-Path -LiteralPath $f)) { return '' }
    try {
        $line = (Get-Content -LiteralPath $f -TotalCount 1 -ErrorAction Stop)
        if ($line) { return $line.Trim() }
    } catch { }
    return ''
}
function Save-RootMemo([string]$dir) {
    $f = Get-RootMemoPath
    if (-not $f) { return }
    try {
        $u = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($f, $dir, $u)
    } catch { }
}

# 找出 _posts 里已用到的最大 post-编号，返回下一个可用编号
function Get-NextPostNumber {
    $biggest = 0
    $dir = $script:S.PostsDir
    if (Test-Path -LiteralPath $dir) {
        foreach ($f in Get-ChildItem -LiteralPath $dir -Filter '*.md' -File) {
            foreach ($m in [regex]::Matches($f.Name, 'post-(\d+)')) {
                $n = [int]$m.Groups[1].Value
                if ($n -gt $biggest) { $biggest = $n }
            }
        }
    }
    return $biggest + 1
}

# 把标题安全地写进 YAML：含冒号、井号的必须整体加引号，否则解析出错
function Convert-YamlSafe([string]$text) {
    $text = ($text -replace '[\r\n]+', ' ').Trim()
    if (-not $text) { return '""' }
    $needQuote = $false
    # 这些符号在 YAML 里有特殊含义，出现在标题里就必须整体加引号
    foreach ($ch in @(':', '#', '[', ']', '{', '}', '&', '*', '!', '|', '>', '%', '@', '`', '"', "'")) {
        if ($text.Contains($ch)) { $needQuote = $true; break }
    }
    if (-not $needQuote) {
        $first = $text.Substring(0, 1)
        if ('-?<>| ' -contains $first) { $needQuote = $true }
    }
    if (-not $needQuote) { return $text }
    $escaped = $text.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
}

# 输出 Jekyll 认识的时间格式：2026-10-28 09:00:00 +0800
function Format-JekyllDate($dt) {
    return $dt.ToString('yyyy-MM-dd HH:mm:ss') + ' +0800'
}

# 解析用户输入的日期，看不懂就退回当前时间
function Convert-ToDate([string]$text) {
    $text = ($text + '').Trim()
    if ($text) {
        $formats = @('yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd HH:mm', 'yyyy-MM-dd', 'yyyy/MM/dd', 'yyyyMMdd')
        $parsed = [datetime]::MinValue
        foreach ($fmt in $formats) {
            if ([datetime]::TryParseExact($text, $fmt, [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
                if ($fmt -notmatch 'HH') {
                    $parsed = $parsed.Date.AddHours(9)
                }
                return $parsed
            }
        }
        Write-Note ('日期没看懂（' + $text + '），改用当前时间')
    }
    return (Get-Date)
}

# =============================================================================
# 四、行内文字渲染
# =============================================================================

# 网址正则。排除空白、引号、括号、中文标点和汉字，
# 这样「详见https://a.com/x，后文再说」只会取中间那段网址。
$script:UrlRx = [regex]'(?<![\w/])(https?://[^\s<>"''()（）\[\]【】《》，。；：！？、\u4e00-\u9fa5]+)'
$script:MailRx = [regex]'[\w.+\-]+@[\w\-]+\.[\w.\-]{2,}'

# 把裸网址先换成占位符藏起来，避免下一步转义时把网址里的符号弄坏
function Protect-AutoLinks([string]$text) {
    $script:S.AutoUrls = New-Object System.Collections.ArrayList

    $urlEval = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $raw = $m.Groups[1].Value
        # 网址末尾常粘着句号逗号，那些属于句子不属于网址
        $trim = $raw.TrimEnd([char[]]'.,;:!?')
        $tail = $raw.Substring($trim.Length)
        $idx = $script:S.AutoUrls.Add($trim)
        return ([string][char]1 + $idx + [string][char]1 + $tail)
    }
    $out = $script:UrlRx.Replace($text, $urlEval)

    $mailEval = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        # 不加 mailto: 前缀，Markdown 渲染器会自动把它变成邮件链接，源码更干净
        $idx = $script:S.AutoUrls.Add($m.Value)
        return ([string][char]1 + $idx + [string][char]1)
    }
    $out = $script:MailRx.Replace($out, $mailEval)
    return $out
}

# 给普通文字加 Markdown 转义，让它原样显示而不被当成排版符号
# -KeepStars：原文作者自己手打的 * 号是「他想要的标记」，不转义（详见 Render-Inline 的说明）
function Escape-Inline([string]$text, [bool]$keepStars = $false) {
    $t = $text.Replace('\', '\\')
    $chars = @('`', '*', '_', '[', ']', '$')
    if ($keepStars) { $chars = @('`', '_', '[', ']', '$') }
    foreach ($c in $chars) {
        $t = $t.Replace([string]$c, '\' + [string]$c)
    }
    # 尖括号会被当成 HTML 标签，换成实体，读者看到的还是 < 符号
    $t = $t.Replace('<', '&lt;')
    return $t
}

# 渲染一个「同格式文字片段」：处理图片、自动链接、转义、软换行
function Convert-SegmentText([string]$text, [bool]$isCode, [bool]$inTable, [bool]$keepStars = $false) {
    if (-not $text) { return '' }
    $sb = New-Object System.Text.StringBuilder

    # 用 \x03 切开，奇数段是图片（内容为 alt + \x04 + 路径），偶数段是普通文字
    $parts = $text -split [regex]::Escape($IMGT)
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $piece = $parts[$i]
        if (($i % 2) -eq 1) {
            $sep = $piece.IndexOf([char]4)
            if ($sep -ge 0) {
                $alt = $piece.Substring(0, $sep)
                $src = $piece.Substring($sep + 1)
            } else {
                $alt = '图片'
                $src = $piece
            }
            if ($src) {
                if (-not $alt) { $alt = '图片' }
                # 这里先原样留着占位符，等整篇转完再统一落盘换成真实路径
                [void]$sb.Append($IMGT + $alt + $IMGSEP + $src + $IMGT)
            }
            continue
        }
        if (-not $piece) { continue }
        if ($isCode) {
            [void]$sb.Append($piece)
            continue
        }
        $protected = Protect-AutoLinks $piece
        $escaped = Escape-Inline $protected $keepStars
        for ($k = 0; $k -lt $script:S.AutoUrls.Count; $k++) {
            $token = $AUTO + $k + $AUTO
            $escaped = $escaped.Replace($token, '<' + $script:S.AutoUrls[$k] + '>')
        }
        [void]$sb.Append($escaped)
    }

    $result = $sb.ToString()
    if ($inTable) {
        $result = $result.Replace($BREAK, '<br>')
    } else {
        $result = $result.Replace($BREAK, '  ' + $script:S.NL)
    }
    return $result
}

# 把一段的若干文字片段拼成一行 Markdown，相邻同格式的先合并
function Render-Inline($segs, [bool]$inTable) {
    if ($null -eq $segs -or $segs.Count -eq 0) { return '' }

    $merged = New-Object System.Collections.ArrayList
    foreach ($s in $segs) {
        $last = $null
        if ($merged.Count -gt 0) { $last = $merged[$merged.Count - 1] }
        if ($null -ne $last -and $last.Bold -eq $s.Bold -and $last.Italic -eq $s.Italic -and
            $last.Code -eq $s.Code -and $last.Url -eq $s.Url) {
            $last.Text = $last.Text + $s.Text
        } else {
            [void]$merged.Add([pscustomobject]@{
                Text = $s.Text; Bold = $s.Bold; Italic = $s.Italic; Code = $s.Code; Url = $s.Url
            })
        }
    }

    # ---- 作者自己手打了 Markdown 标记怎么办 ----
    # 有的人习惯先在记事本/别处写好 **加粗**、### 标题，再整段粘进 Word，
    # Word 里那些字同时也是加粗格式。此时如果照常「转义 * + 自动加粗」，
    # 就会叠加成 \*\***检索条件…\*\*** 这种四不像，看着像乱码。
    # 处理原则：加粗这一件事只表达一次。
    #   整段本来就有加粗格式 → 手打的 ** 是多余的，删掉，加粗交给格式还原
    #   整段没有任何加粗格式 → 手打的 ** 就是唯一的加粗信息，原样保留、不转义
    $plain = ''
    foreach ($s in $merged) { if ($s.Text) { $plain += $s.Text } }
    $hasAutoBold = $false
    foreach ($s in $merged) {
        if ($s.Bold -and $s.Text -and $s.Text.Trim()) { $hasAutoBold = $true; break }
    }
    $stripManual = $hasAutoBold -and ($plain -match '\*{2,}')
    $keepStars = (-not $hasAutoBold) -and ($plain -match '\*\*[^\s]')

    $out = New-Object System.Text.StringBuilder
    foreach ($s in $merged) {
        $segText = $s.Text
        if ($stripManual -and $segText) {
            # 只删「两个及以上的连续星号」，单个 * 多半是正文里的符号，留着让它照常转义
            $segText = [regex]::Replace($segText, '\*{2,}', '')
        }
        $body = Convert-SegmentText $segText $s.Code $inTable $keepStars
        if (-not $body.Trim()) { continue }
        if ($s.Code) { $body = '`' + $body.Trim() + '`' }
        if ($s.Bold -and $s.Italic) { $body = '***' + $body + '***' }
        elseif ($s.Bold) { $body = '**' + $body + '**' }
        elseif ($s.Italic) { $body = '*' + $body + '*' }
        if ($s.Url) { $body = '[' + $body + '](' + $s.Url + ')' }
        [void]$out.Append($body)
    }
    return $out.ToString().Trim()
}

# =============================================================================
# 五、.docx 解析
# =============================================================================

function Read-Xml([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $doc = New-Object System.Xml.XmlDocument
    $doc.PreserveWhitespace = $true
    $doc.Load($path)
    return $doc
}

# 读关系表：rId → 超链接网址，或图片在包内的路径
function Load-Rels {
    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
    $path = Join-Path $script:S.ZipRoot 'word\_rels\document.xml.rels'
    $doc = Read-Xml $path
    if ($null -eq $doc) { return $map }
    foreach ($rel in $doc.DocumentElement.ChildNodes) {
        if ($rel.NodeType -ne 'Element') { continue }
        $rid = $rel.GetAttribute('Id')
        $target = $rel.GetAttribute('Target')
        $mode = $rel.GetAttribute('TargetMode')
        if (-not $rid -or -not $target) { continue }
        if ($mode -eq 'External' -or $target -match '^(https?://|mailto:)') {
            $map[$rid] = $target
        } elseif ($target.StartsWith('/')) {
            $map[$rid] = $target.TrimStart('/')
        } else {
            $map[$rid] = 'word/' + ($target -replace '/', '\')
        }
    }
    return $map
}

# 读样式表：styleId → 样式名（中文版 Word 里「标题 1」的内部名字是 "heading 1"）
function Load-Styles {
    $map = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    $doc = Read-Xml (Join-Path $script:S.ZipRoot 'word\styles.xml')
    if ($null -eq $doc) { return $map }
    foreach ($st in $doc.DocumentElement.ChildNodes) {
        if ($st.NodeType -ne 'Element' -or $st.LocalName -ne 'style') { continue }
        $sid = $st.GetAttribute('styleId', $W)
        if (-not $sid) { continue }
        $name = $sid
        $outline = -1
        foreach ($c in $st.ChildNodes) {
            if ($c.NodeType -ne 'Element') { continue }
            if ($c.LocalName -eq 'name') {
                $name = $c.GetAttribute('val', $W)
            } elseif ($c.LocalName -eq 'pPr') {
                foreach ($d in $c.ChildNodes) {
                    if ($d.LocalName -eq 'outlineLvl') {
                        $v = 0
                        if ([int]::TryParse($d.GetAttribute('val', $W), [ref]$v)) { $outline = $v }
                    }
                }
            }
        }
        $map[$sid] = [pscustomobject]@{ Name = $name; Outline = $outline }
    }
    return $map
}

# 读编号表：numId → 这串列表用的是圆点还是数字
function Load-Numbering {
    $map = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    $doc = Read-Xml (Join-Path $script:S.ZipRoot 'word\numbering.xml')
    if ($null -eq $doc) { return $map }

    $abstract = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    foreach ($an in $doc.DocumentElement.ChildNodes) {
        if ($an.NodeType -ne 'Element' -or $an.LocalName -ne 'abstractNum') { continue }
        $aid = $an.GetAttribute('abstractNumId', $W)
        $lvls = New-Object 'System.Collections.Generic.Dictionary[string,string]'
        foreach ($lvl in $an.ChildNodes) {
            if ($lvl.NodeType -ne 'Element' -or $lvl.LocalName -ne 'lvl') { continue }
            $ilvl = $lvl.GetAttribute('ilvl', $W)
            $fmt = 'decimal'
            foreach ($c in $lvl.ChildNodes) {
                if ($c.LocalName -eq 'numFmt') { $fmt = $c.GetAttribute('val', $W) }
            }
            if ($null -eq $ilvl) { $ilvl = '0' }
            $lvls[$ilvl] = $fmt
        }
        if ($aid) { $abstract[$aid] = $lvls }
    }

    foreach ($num in $doc.DocumentElement.ChildNodes) {
        if ($num.NodeType -ne 'Element' -or $num.LocalName -ne 'num') { continue }
        $nid = $num.GetAttribute('numId', $W)
        foreach ($c in $num.ChildNodes) {
            if ($c.LocalName -eq 'abstractNumId') {
                $aid = $c.GetAttribute('val', $W)
                if ($aid -and $abstract.ContainsKey($aid)) { $map[$nid] = $abstract[$aid] }
            }
        }
    }
    return $map
}

# 读 .docx 里记录的创建时间（这篇稿子真正动笔的时间）
function Get-DocCreatedTime {
    $doc = Read-Xml (Join-Path $script:S.ZipRoot 'docProps\core.xml')
    if ($null -eq $doc) { return $null }
    foreach ($n in $doc.DocumentElement.ChildNodes) {
        if ($n.LocalName -eq 'created' -and $n.NamespaceURI -eq 'http://purl.org/dc/terms/') {
            $raw = ($n.InnerText + '').Trim()
            if (-not $raw) { return $null }
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse($raw, [ref]$parsed)) { return $parsed.ToLocalTime() }
            return $null
        }
    }
    return $null
}

# 读一个文字块（run）的格式：加粗 / 斜体 / 代码
function Get-RunProps($r) {
    $bold = $false; $italic = $false; $code = $false
    foreach ($ch in $r.ChildNodes) {
        if ($ch.NodeType -ne 'Element' -or $ch.LocalName -ne 'rPr') { continue }
        foreach ($p in $ch.ChildNodes) {
            if ($p.NodeType -ne 'Element') { continue }
            switch ($p.LocalName) {
                'b' { if ($p.GetAttribute('val', $W) -notin @('0', 'false', 'off')) { $bold = $true } }
                'i' { if ($p.GetAttribute('val', $W) -notin @('0', 'false', 'off')) { $italic = $true } }
                'rStyle' {
                    $rs = $p.GetAttribute('val', $W)
                    if ($rs -and ($rs.ToLower() -in @('htmlcode', 'code', 'codespan', '代码'))) { $code = $true }
                }
            }
        }
    }
    return [pscustomobject]@{ Bold = $bold; Italic = $italic; Code = $code }
}

# 从一个 run 里挖出图片：返回 alt 和图片在包内的路径
function Find-ImageRef($elem) {
    $blips = $elem.GetElementsByTagName('blip', $A)
    if ($blips.Count -gt 0) {
        $blip = $blips.Item(0)
        $rid = $blip.GetAttribute('embed', $RN)
        if (-not $rid) { $rid = $blip.GetAttribute('link', $RN) }
        if ($rid -and $script:S.Rels.ContainsKey($rid)) {
            $alt = ''
            $dps = $elem.GetElementsByTagName('docPr', $WP)
            if ($dps.Count -gt 0) {
                $alt = $dps.Item(0).GetAttribute('descr')
                if (-not $alt) { $alt = $dps.Item(0).GetAttribute('title') }
            }
            if (-not $alt) { $alt = '图片' }
            return [pscustomobject]@{ Alt = $alt; Target = $script:S.Rels[$rid] }
        }
    }
    $old = $elem.GetElementsByTagName('imagedata', $V)
    if ($old.Count -gt 0) {
        $rid = $old.Item(0).GetAttribute('id', $RN)
        if ($rid -and $script:S.Rels.ContainsKey($rid)) {
            return [pscustomobject]@{ Alt = '图片'; Target = $script:S.Rels[$rid] }
        }
    }
    return $null
}

# 把一个 run 里的文字拼起来，图片位置插占位符
function Get-RunText($r) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $r.ChildNodes) {
        if ($ch.NodeType -ne 'Element') { continue }
        if ($ch.NamespaceURI -ne $W) { continue }
        switch ($ch.LocalName) {
            't' { [void]$sb.Append($ch.InnerText) }
            'tab' { [void]$sb.Append(' ') }
            'br' { [void]$sb.Append($BREAK) }
            'cr' { [void]$sb.Append($BREAK) }
            'noBreakHyphen' { [void]$sb.Append('-') }
            'drawing' {
                $img = Find-ImageRef $ch
                if ($img) { [void]$sb.Append($IMGT + $img.Alt + $IMGSEP + $img.Target + $IMGT) }
            }
            'pict' {
                $img = Find-ImageRef $ch
                if ($img) { [void]$sb.Append($IMGT + $img.Alt + $IMGSEP + $img.Target + $IMGT) }
            }
            'object' {
                $img = Find-ImageRef $ch
                if ($img) { [void]$sb.Append($IMGT + $img.Alt + $IMGSEP + $img.Target + $IMGT) }
            }
        }
    }
    return $sb.ToString()
}

# 递归收集段落里的文字片段，链接里的文字会带上网址
function Add-Segments($elem, [string]$url, $acc) {
    foreach ($ch in $elem.ChildNodes) {
        if ($ch.NodeType -ne 'Element') { continue }
        if ($ch.NamespaceURI -ne $W) { continue }
        switch ($ch.LocalName) {
            'r' {
                $props = Get-RunProps $ch
                $text = Get-RunText $ch
                if ($text) {
                    [void]$acc.Add([pscustomobject]@{
                        Text = $text; Bold = $props.Bold; Italic = $props.Italic
                        Code = $props.Code; Url = $url
                    })
                }
            }
            'hyperlink' {
                $rid = $ch.GetAttribute('id', $RN)
                $target = $url
                if ($rid -and $script:S.Rels.ContainsKey($rid)) { $target = $script:S.Rels[$rid] }
                Add-Segments $ch $target $acc
            }
            'fldSimple' {
                # Word 的「插入超链接」常常是域代码，真实网址藏在 instr 里
                $instr = $ch.GetAttribute('instr', $W)
                $target = $url
                if ($instr) {
                    $m = [regex]::Match($instr, 'HYPERLINK\s+"([^"]+)"', 'IgnoreCase')
                    if ($m.Success) { $target = $m.Groups[1].Value }
                }
                Add-Segments $ch $target $acc
            }
            'ins' { Add-Segments $ch $url $acc }
            'smartTag' { Add-Segments $ch $url $acc }
            'customXml' { Add-Segments $ch $url $acc }
            'moveTo' { Add-Segments $ch $url $acc }
            'bdo' { Add-Segments $ch $url $acc }
            'dir' { Add-Segments $ch $url $acc }
            'sdt' { Add-Segments $ch $url $acc }
            'sdtContent' { Add-Segments $ch $url $acc }
        }
    }
}

function Collect-Segments($p) {
    $acc = New-Object System.Collections.ArrayList
    Add-Segments $p '' $acc
    return $acc
}

# 判断段落是几级标题：1~6 = 标题 N；0 = 文章大标题；-1 = 普通正文
function Get-HeadingLevel($p) {
    $styleId = ''
    $outline = -1
    foreach ($c in $p.ChildNodes) {
        if ($c.NodeType -ne 'Element' -or $c.LocalName -ne 'pPr') { continue }
        foreach ($d in $c.ChildNodes) {
            if ($d.NodeType -ne 'Element') { continue }
            if ($d.LocalName -eq 'pStyle') { $styleId = $d.GetAttribute('val', $W) }
            elseif ($d.LocalName -eq 'outlineLvl') {
                $v = 0
                if ([int]::TryParse($d.GetAttribute('val', $W), [ref]$v)) { $outline = $v }
            }
        }
    }

    $name = ''
    if ($styleId -and $script:S.Styles.ContainsKey($styleId)) {
        $st = $script:S.Styles[$styleId]
        $name = ($st.Name + '').ToLower()
        if ($outline -lt 0) { $outline = $st.Outline }
    } else {
        $name = ($styleId + '').ToLower()
    }

    if ($name) {
        $m = [regex]::Match($name, '^(?:heading|标题)\s*([1-6])$')
        if ($m.Success) { return [int]$m.Groups[1].Value }
        if ($name -match '^(title|标题|题目)$' -or $name.StartsWith('title')) { return 0 }
        if ($name.StartsWith('heading') -or $name.StartsWith('标题')) { return 1 }
        if ($name -match '^[1-6]$') { return [int]$name }
        if ($name.Contains('quote') -or $name.Contains('引用')) { return -1 }
        if ($name.Contains('副标题') -or $name.StartsWith('subtitle')) { return -1 }
    }

    if ($outline -ge 0 -and $outline -le 5) { return $outline + 1 }
    return -1
}

function Test-IsQuote($p) {
    foreach ($c in $p.ChildNodes) {
        if ($c.NodeType -ne 'Element' -or $c.LocalName -ne 'pPr') { continue }
        foreach ($d in $c.ChildNodes) {
            if ($d.LocalName -eq 'pStyle') {
                $sid = $d.GetAttribute('val', $W)
                $nm = ''
                if ($script:S.Styles.ContainsKey($sid)) { $nm = $script:S.Styles[$sid].Name }
                if (-not $nm) { $nm = $sid }
                $nm = ($nm + '').ToLower()
                if ($nm.Contains('quote') -or $nm.Contains('引用')) { return $true }
            }
        }
    }
    return $false
}

# 判断是不是列表：返回 类型（ul/ol）和层级
function Get-ListInfo($p) {
    $result = [pscustomobject]@{ Type = ''; Level = 0 }
    foreach ($c in $p.ChildNodes) {
        if ($c.NodeType -ne 'Element' -or $c.LocalName -ne 'pPr') { continue }
        foreach ($d in $c.ChildNodes) {
            if ($d.LocalName -ne 'numPr') { continue }
            $numId = ''
            $ilvl = 0
            foreach ($e in $d.ChildNodes) {
                if ($e.LocalName -eq 'numId') { $numId = $e.GetAttribute('val', $W) }
                elseif ($e.LocalName -eq 'ilvl') { [void][int]::TryParse($e.GetAttribute('val', $W), [ref]$ilvl) }
            }
            if (-not $numId -or $numId -eq '0') { continue }
            $fmt = 'decimal'
            if ($script:S.Numbering.ContainsKey($numId)) {
                $lvls = $script:S.Numbering[$numId]
                if ($lvls.ContainsKey([string]$ilvl)) { $fmt = $lvls[[string]$ilvl] }
            }
            if ($fmt -in @('bullet', 'none')) { $result.Type = 'ul' } else { $result.Type = 'ol' }
            $result.Level = $ilvl
            return $result
        }
    }
    return $result
}

# =============================================================================
# 六、图片处理
# =============================================================================

# 把各种「不完整」的网址补成能直接打开的完整网址。
# 老网页里特别常见这两种：
#   //up.itc.cn/a.jpg      → 少了协议，浏览器在本地打开会变成 file://up.itc.cn/...
#   /up.itc.cn/a.jpg       → 还少了一个斜杠，浏览器会当成「本机根目录下的文件夹」
# 两者都显示不出图片，所以统一补成 https:// 开头。
# 站内自己的 /assets/img/xx.jpg 不动，那是博客里的图片，得按原样发布。
function Repair-Url([string]$url) {
    if (-not $url) { return $url }
    $u = $url.Trim()
    if (-not $u) { return $u }
    if ($u -match '^(?i)(data|mailto|tel|javascript|about):') { return $u }
    if ($u -match '^(?i)https?://') { return $u }
    if ($u.StartsWith('//')) { return 'https:' + $u }
    if ($u.StartsWith('/')) {
        $seg = ($u.TrimStart('/') -split '/')[0]
        # 第一段长得像域名（带点），说明本意是 //域名/路径，补成 https://域名/路径
        if ($seg -match '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$') { return 'https:/' + $u }
        return $u
    }
    return $u
}

# 给图床网址补压缩参数（已带参数的就更新宽度，不重复叠加）
function Add-OssSuffix([string]$url) {
    if (-not $url) { return $url }
    $url = Repair-Url $url
    if ($url -notmatch '^https?://') { return $url }

    $host_ = ''
    $m = [regex]::Match($url, '^https?://([^/]+)')
    if ($m.Success) { $host_ = $m.Groups[1].Value.ToLower() }

    $supported = $false
    foreach ($h in $OSS_HOSTS) {
        if ($host_.EndsWith($h)) { $supported = $true; break }
    }
    if (-not $supported) { return $url }

    if ($url -match '\?[^#]*x-oss-process=') {
        # 已经有参数了，只把宽度改成当前设置
        return [regex]::Replace($url, 'resize,w_\d+', 'resize,w_' + $script:S.MaxWidth)
    }
    $joinChar = '?'
    if ($url.Contains('?')) { $joinChar = '&' }   # 网址本来就带别的参数，不能再用问号
    return $url + $joinChar + 'x-oss-process=image/resize,w_' + $script:S.MaxWidth + '/format,webp'
}

# 测试能不能用 .NET 的绘图功能做真实压缩（Windows 自带，但个别精简系统可能缺）
function Test-Drawing {
    if ($null -ne $script:S.DrawingOk) { return $script:S.DrawingOk }
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $script:S.DrawingOk = $true
    } catch {
        $script:S.DrawingOk = $false
    }
    return $script:S.DrawingOk
}

# 导出一张图片：压缩后写到 assets 目录，返回它在网站上的网址
function Save-Image([string]$zipPath) {
    # 网络图片：不落盘，只挂压缩参数
    if ($zipPath -match '^(https?://|data:)') {
        if ($zipPath.StartsWith('data:')) { return '' }   # 内嵌小图标忽略
        $script:S.Images++
        return (Add-OssSuffix $zipPath)
    }

    $srcPath = Join-Path $script:S.ZipRoot ($zipPath -replace '/', '\')
    if (-not (Test-Path -LiteralPath $srcPath)) { return '' }

    $name = Split-Path -Leaf $srcPath
    $destPath = Join-Path $script:S.AssetsDir $name
    $ext = [System.IO.Path]::GetExtension($name).ToLower()

    if ($script:S.DryRun) {
        $script:S.Images++
        return ($script:S.ImgRel + '/' + $name)
    }
    if (-not (Test-Path -LiteralPath $script:S.AssetsDir)) {
        New-Item -ItemType Directory -Force -Path $script:S.AssetsDir | Out-Null
    }

    $ok = $false
    if ((Test-Drawing) -and ($ext -in @('.jpg', '.jpeg', '.png', '.gif', '.bmp'))) {
        try {
            $img = [System.Drawing.Image]::FromFile($srcPath)
            try {
                $w = $img.Width
                $h = $img.Height
                $scale = [Math]::Min(1.0, $script:S.MaxWidth / $w)
                if (($h * $scale) -gt $script:S.MaxHeight) {
                    $scale = [Math]::Min($scale, $script:S.MaxHeight / $h)
                }
                $nw = [int][Math]::Round($w * $scale)
                $nh = [int][Math]::Round($h * $scale)
                if ($nw -lt 1) { $nw = 1 }
                if ($nh -lt 1) { $nh = 1 }

                $bmp = New-Object System.Drawing.Bitmap -ArgumentList $nw, $nh
                try {
                    $g = [System.Drawing.Graphics]::FromImage($bmp)
                    try {
                        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                        # 透明背景转成 JPEG 会变黑，先铺白底
                        $g.Clear([System.Drawing.Color]::White)
                        $g.DrawImage($img, 0, 0, $nw, $nh)
                    } finally { $g.Dispose() }

                    if ($ext -in @('.jpg', '.jpeg')) {
                        $codec = $null
                        foreach ($ce in [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()) {
                            if ($ce.MimeType -eq 'image/jpeg') { $codec = $ce; break }
                        }
                        if ($codec) {
                            $ep = New-Object System.Drawing.Imaging.EncoderParameters -ArgumentList 1
                            $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter -ArgumentList (
                                [System.Drawing.Imaging.Encoder]::Quality, [long]$script:S.JpegQuality)
                            $bmp.Save($destPath, $codec, $ep)
                            $ep.Dispose()
                        } else {
                            $bmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
                        }
                    } else {
                        $bmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
                    }
                    $ok = $true
                    $script:S.ImageSaved++
                } finally { $bmp.Dispose() }
            } finally { $img.Dispose() }
        } catch {
            # 压缩失败不要紧，下面会退回「原样复制」，绝不中断转换
            $ok = $false
        }
    }

    if (-not $ok) {
        Copy-Item -LiteralPath $srcPath -Destination $destPath -Force
    }
    $script:S.Images++
    return ($script:S.ImgRel + '/' + $name)
}

# 把正文里的图片占位符换成真正的图片文件 + 网址
function Resolve-Images([string]$text) {
    $eval = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $inner = $m.Groups[1].Value
        $sep = $inner.IndexOf([char]4)
        if ($sep -ge 0) {
            $alt = $inner.Substring(0, $sep)
            $src = $inner.Substring($sep + 1)
        } else {
            $alt = '图片'
            $src = $inner
        }
        if (-not $alt) { $alt = '图片' }
        $real = Save-Image $src
        if (-not $real) { return '' }
        return '![' + $alt + '](' + $real + ')'
    }
    $rx = [regex]($IMGT + '(.*?)' + $IMGT)
    return $rx.Replace($text, $eval)
}

# =============================================================================
# 七、表格转 Markdown
# =============================================================================

function Get-CellText($tc) {
    $parts = New-Object System.Collections.ArrayList
    foreach ($p in $tc.ChildNodes) {
        if ($p.NodeType -ne 'Element' -or $p.LocalName -ne 'p') { continue }
        $segs = Collect-Segments $p
        $line = Render-Inline $segs $true
        if ($line.Trim()) { [void]$parts.Add($line) }
    }
    $text = ($parts -join '<br>').Trim()
    # 表格竖线必须转义，否则会把一列劈成两列
    return $text.Replace('|', '\|')
}

function Get-CellSpan($tc) {
    foreach ($c in $tc.ChildNodes) {
        if ($c.NodeType -ne 'Element' -or $c.LocalName -ne 'tcPr') { continue }
        foreach ($d in $c.ChildNodes) {
            if ($d.LocalName -eq 'gridSpan') {
                $v = 1
                if ([int]::TryParse($d.GetAttribute('val', $W), [ref]$v)) { return [Math]::Max(1, $v) }
            }
        }
    }
    return 1
}

function Test-VMergeContinue($tc) {
    foreach ($c in $tc.ChildNodes) {
        if ($c.NodeType -ne 'Element' -or $c.LocalName -ne 'tcPr') { continue }
        foreach ($d in $c.ChildNodes) {
            if ($d.LocalName -eq 'vMerge') {
                $v = $d.GetAttribute('val', $W)
                if (-not $v -or $v -eq 'continue') { return $true }
            }
        }
    }
    return $false
}

function Render-Table($tbl) {
    $rows = New-Object System.Collections.ArrayList

    foreach ($tr in $tbl.ChildNodes) {
        if ($tr.NodeType -ne 'Element' -or $tr.LocalName -ne 'tr') { continue }
        $cells = New-Object System.Collections.ArrayList
        foreach ($tc in $tr.ChildNodes) {
            if ($tc.NodeType -ne 'Element' -or $tc.LocalName -ne 'tc') { continue }
            if (Test-VMergeContinue $tc) {
                # 纵向合并的「延续格」，沿用上一行同列的内容
                $col = $cells.Count
                $prev = ''
                if ($rows.Count -gt 0 -and $col -lt $rows[$rows.Count - 1].Count) {
                    $prev = $rows[$rows.Count - 1][$col]
                }
                [void]$cells.Add($prev)
                continue
            }
            [void]$cells.Add((Get-CellText $tc))
            $span = Get-CellSpan $tc
            for ($k = 1; $k -lt $span; $k++) { [void]$cells.Add('') }
        }
        $hasContent = $false
        foreach ($c in $cells) { if (($c + '').Trim()) { $hasContent = $true; break } }
        if ($hasContent) { [void]$rows.Add($cells) }
    }

    if ($rows.Count -eq 0) { return '' }

    # 统一列数：以最宽的行为准，短行补空
    $width = 1
    foreach ($r in $rows) { if ($r.Count -gt $width) { $width = $r.Count } }
    foreach ($r in $rows) {
        while ($r.Count -lt $width) { [void]$r.Add('') }
    }

    # 第一行如果是「横跨全表的大标题」（法律文书表格常见），挪到表格上方
    $caption = ''
    if ($width -gt 1) {
        $nonEmpty = @()
        foreach ($c in $rows[0]) { if (($c + '').Trim()) { $nonEmpty += $c } }
        if ($nonEmpty.Count -eq 1) {
            $caption = $nonEmpty[0]
            $rows.RemoveAt(0)
            if ($rows.Count -eq 0) { return '**' + $caption + '**' + $script:S.NL }
        }
    }
    if ($rows.Count -eq 0) { return '' }

    $header = $rows[0]
    $body = @()
    if ($rows.Count -gt 1) { $body = $rows[1..($rows.Count - 1)] }

    # Markdown 表格必须有表头，原表没有就补「列1 / 列2」
    $anyHeader = $false
    foreach ($c in $header) { if (($c + '').Trim()) { $anyHeader = $true; break } }
    if (-not $anyHeader) {
        $header = @()
        for ($i = 1; $i -le $width; $i++) { $header += ('列' + $i) }
    }

    $NL = $script:S.NL
    $lines = New-Object System.Collections.ArrayList
    if ($caption) { [void]$lines.Add('**' + $caption + '**'); [void]$lines.Add('') }
    [void]$lines.Add('| ' + ($header -join ' | ') + ' |')
    $sep = @()
    for ($i = 0; $i -lt $width; $i++) { $sep += '---' }
    [void]$lines.Add('| ' + ($sep -join ' | ') + ' |')
    foreach ($row in $body) {
        [void]$lines.Add('| ' + ($row -join ' | ') + ' |')
    }
    return (($lines -join $NL) + $NL)
}

# =============================================================================
# 七之二、HTML（.html / .htm）转 Markdown
#
# 思路：HTML 里真正麻烦的只有「块」和「嵌套」。
#   ① 先把代码块 <pre> 和表格 <table> 整段抽出来，单独转好放一边；
#   ② 剩下的按「标签 / 文字」一个个过，块级标签只顾断电（flush），
#      行内标签原样留着，等一小段（段落、列表项）攒完再统一处理；
#   ③ 最后把抽走的代码块、表格放回去。
# 这样不用做完整的 HTML 解析，也能扛住一般的嵌套。
# =============================================================================

# 读文本：认得 UTF-8（有无 BOM 都行），也认得 GBK 老网页
function Read-TextSmart([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    try {
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        return $strict.GetString($bytes)
    } catch {
        try {
            return [System.Text.Encoding]::GetEncoding(936).GetString($bytes)
        } catch {
            return [System.Text.Encoding]::UTF8.GetString($bytes)
        }
    }
}

# HTML 实体还原
function Convert-HtmlEntities([string]$text) {
    if (-not $text) { return '' }
    $t = $text
    $t = $t -replace '&nbsp;', ' '
    $t = $t -replace '&lt;', '<'
    $t = $t -replace '&gt;', '>'
    $t = $t -replace '&quot;', '"'
    $t = $t -replace '&#0*39;', "'"
    $t = $t -replace '&apos;', "'"
    # 注意：中文弯引号不能直接写进单引号字符串，PowerShell 会把它当成字符串边界，
    # 所以这里一律用字符编码拼出来
    $t = $t.Replace('&mdash;', [string][char]0x2014)
    $t = $t.Replace('&ndash;', [string][char]0x2013)
    $t = $t.Replace('&hellip;', [string][char]0x2026)
    $t = $t.Replace('&ldquo;', [string][char]0x201C)
    $t = $t.Replace('&rdquo;', [string][char]0x201D)
    $t = $t.Replace('&lsquo;', [string][char]0x2018)
    $t = $t.Replace('&rsquo;', [string][char]0x2019)
    $t = [regex]::Replace($t, '&#0*(\d+);', { param($m) [string][char][int]$m.Groups[1].Value })
    $t = [regex]::Replace($t, '&#[xX]([0-9a-fA-F]+);', { param($m) [string][char][Convert]::ToInt32($m.Groups[1].Value, 16) })
    $t = $t -replace '&amp;', '&'      # 放最后，免得把 &amp;lt; 解成 <
    return $t
}

# 从一段标签文字里取属性值，例如 Get-HtmlAttr '<a href="x">' 'href'
function Get-HtmlAttr([string]$tag, [string]$name) {
    $p = '(?i)(?<![\w-])' + [regex]::Escape($name) + '\s*=\s*("([^"]*)"|''([^'']*)''|([^\s>]+))'
    $m = [regex]::Match($tag, $p)
    if (-not $m.Success) { return '' }
    if ($m.Groups[2].Success) { return $m.Groups[2].Value }
    if ($m.Groups[3].Success) { return $m.Groups[3].Value }
    return $m.Groups[4].Value
}

# 行内代码 → `代码`
function Get-CodeMd([string]$inner) {
    $x = [regex]::Replace($inner, '(?s)<[^>]+>', '')
    $x = (Convert-HtmlEntities $x) -replace '\s+', ' '
    $x = $x.Trim()
    if (-not $x) { return '' }
    if ($x.Contains('`')) { return '`` ' + $x + ' ``' }
    return '`' + $x + '`'
}

# <a href="...">文字</a> → [文字](网址)；文字本身就是网址（或没有文字）时写成 <网址>
function Get-LinkMd([string]$attrs, [string]$inner) {
    $inner = [regex]::Replace($inner, '(?s)<[^>]+>', '')
    $text = (Convert-HtmlEntities $inner) -replace '\s+', ' '
    $text = $text.Trim()
    $href = Repair-Url (Convert-HtmlEntities (Get-HtmlAttr $attrs 'href')).Trim()
    if (-not $href -or $href -match '^(?i)(javascript:|#)') { return $text }
    # 文字本身就是那个网址（或只是「查看」之类的空文字），写成 <网址> 最干净
    if (-not $text -or $text -eq $href -or $text -match '^(?i)https?://\S+$') { return '<' + $href + '>' }
    return '[' + $text + '](' + $href + ')'
}

# 正文里的裸网址 → <网址>
# 网页上的网址常常就是一段纯文本（没包 <a>），直接照抄过去在博客里点了没反应。
# 网址后面遇到 * 就别再吞了：* 是加粗标记，吞进去会变成 <https://a.com/x**> 这种坏掉的链接。
$script:BareUrlRx = [regex]'(?<![\w/])(https?://[^\s<>"''()（）\[\]【】《》，。；：！？、*|\u4e00-\u9fa5]+)'
function Convert-BareUrls([string]$text) {
    if (-not $text -or $text.IndexOf('://') -lt 0) { return $text }
    $eval = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $raw = $m.Groups[1].Value
        # 网址末尾常粘着句号、逗号，那些属于句子不属于网址
        $trim = $raw.TrimEnd([char[]]'.,;:!?')
        if ($trim.Length -lt 10) { return $m.Value }
        $tail = $raw.Substring($trim.Length)
        return '<' + $trim + '>' + $tail
    }
    return $script:BareUrlRx.Replace($text, $eval)
}

# 行内标签 → Markdown（作用范围：一个段落 / 一个列表项 / 一个单元格）
function Convert-HtmlInline([string]$html) {
    if (-not $html) { return '' }
    $t = $html

    # 代码和链接先「整块藏起来」（换成占位符，五号/六号字符）：
    # 它们转成 Markdown 后是定稿，不能再被后面的去标签、自动加链接碰到，
    # 否则 <a href="https://a.com">https://a.com</a> 会被套成 <<https://a.com>>。
    $script:HtmlStash = New-Object System.Collections.ArrayList

    $stashEval = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $idx = $script:HtmlStash.Add($m.Value)
        return ([string][char]5 + $idx + [string][char]6)
    }
    $t = [regex]::Replace($t, '(?is)<code\b[^>]*>.*?</code\s*>', $stashEval)
    $t = [regex]::Replace($t, '(?is)<a\b[^>]*>.*?</a\s*>', $stashEval)

    # 加粗 / 斜体 / 删除线（先粗后斜，否则 <b><i>x</i></b> 会错）
    $t = [regex]::Replace($t, '(?is)<(strong|b)\b[^>]*>(.*?)</\1\s*>', '**$2**')
    $t = [regex]::Replace($t, '(?is)<(em|i)\b[^>]*>(.*?)</\1\s*>', '*$2*')
    $t = [regex]::Replace($t, '(?is)<(del|s|strike)\b[^>]*>(.*?)</\1\s*>', '~~$2~~')

    # 只剩下排版用的标签，拆掉留字
    $t = [regex]::Replace($t, '(?is)</?(span|font|u|small|sup|sub|mark|ins|abbr|label|time|q|cite|kbd|var|samp|bdi|bdo|big|tt|nobr|div|p|section|article)\b[^>]*>', '')
    # 兜底：还不认识的标签一律去掉
    $t = [regex]::Replace($t, '(?s)<[^>]+>', '')
    $t = Convert-HtmlEntities $t

    # 裸网址变自动链接（要在去标签之后做，否则尖括号会被当成标签删掉）
    $t = Convert-BareUrls $t

    # 把藏起来的代码和链接放回来（倒序：链接文字里如果嵌着代码，倒序正好能一起还原）
    for ($k = $script:HtmlStash.Count - 1; $k -ge 0; $k--) {
        $token = [string][char]5 + $k + [string][char]6
        if ($t.IndexOf($token) -lt 0) { continue }
        $raw = [string]$script:HtmlStash[$k]
        $md = ''
        if ($raw -match '(?is)^<code\b[^>]*>(.*)</code\s*>$') {
            $md = Get-CodeMd $Matches[1]
        } elseif ($raw -match '(?is)^<a\b([^>]*)>(.*)</a\s*>$') {
            $md = Get-LinkMd $Matches[1] $Matches[2]
        }
        $t = $t.Replace($token, $md)
    }

    # 空白整理：换行记号（char 2）先固定住，其余连续空白压成一个空格
    $t = [regex]::Replace($t, '[ \t\r\n\f]{0,}\u0002[ \t\r\n\f]{0,}', [string][char]2)
    $t = [regex]::Replace($t, '[ \t\r\n\f]+', ' ')
    # 中文与中文、中文与加粗标记之间的多余空格去掉
    $t = [regex]::Replace($t, '([\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]) (?=[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef])', '$1')
    $t = [regex]::Replace($t, '([\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]) (?=[*`])', '$1')
    $t = [regex]::Replace($t, '([*`]) (?=[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef])', '$1')
    # 换行记号 → Markdown 硬换行（行尾两个空格）
    $t = $t.Replace([string][char]2, '  ' + $script:S.NL)
    return $t.Trim()
}

# 表格 → Markdown 表格
function Convert-HtmlTable([string]$tbl) {
    $rows = New-Object System.Collections.ArrayList
    foreach ($tr in [regex]::Matches($tbl, '(?is)<tr\b[^>]*>(.*?)</tr\s*>')) {
        $cells = New-Object System.Collections.ArrayList
        foreach ($c in [regex]::Matches($tr.Groups[1].Value, '(?is)<(td|th)\b([^>]*)>(.*?)</\1\s*>')) {
            $txt = Convert-HtmlInline $c.Groups[3].Value
            $txt = $txt.Replace($script:S.NL, '<br>').Replace('|', '\|').Trim()
            [void]$cells.Add($txt)
            $span = 1
            $sm = [regex]::Match($c.Groups[2].Value, '(?i)colspan\s*=\s*("(\d+)"|''(\d+)''|(\d+))')
            if ($sm.Success) {
                $sv = ''
                if ($sm.Groups[2].Success) { $sv = $sm.Groups[2].Value }
                elseif ($sm.Groups[3].Success) { $sv = $sm.Groups[3].Value }
                else { $sv = $sm.Groups[4].Value }
                [int]$span = 0
                [void][int]::TryParse($sv, [ref]$span)
            }
            if ($span -gt 1) {
                for ($k = 1; $k -lt $span; $k++) { [void]$cells.Add('') }   # 合并单元格后面补空
            }
        }
        if ($cells.Count -gt 0) { [void]$rows.Add($cells) }
    }
    if ($rows.Count -eq 0) { return '' }

    $width = 0
    foreach ($r in $rows) { if ($r.Count -gt $width) { $width = $r.Count } }
    foreach ($r in $rows) { while ($r.Count -lt $width) { [void]$r.Add('') } }

    $NL = $script:S.NL
    $out = New-Object System.Collections.ArrayList
    $head = @()
    for ($i = 0; $i -lt $width; $i++) { $head += ('' + $rows[0][$i]) }
    $anyHeader = $false
    foreach ($c in $head) { if (($c + '').Trim()) { $anyHeader = $true; break } }
    if (-not $anyHeader) {
        $head = @()
        for ($i = 1; $i -le $width; $i++) { $head += ('列' + $i) }
    }
    [void]$out.Add('| ' + ($head -join ' | ') + ' |')
    $sep = @()
    for ($i = 0; $i -lt $width; $i++) { $sep += '---' }
    [void]$out.Add('| ' + ($sep -join ' | ') + ' |')
    for ($i = 1; $i -lt $rows.Count; $i++) {
        $cellsOut = @()
        for ($j = 0; $j -lt $width; $j++) { $cellsOut += ('' + $rows[$i][$j]) }
        [void]$out.Add('| ' + ($cellsOut -join ' | ') + ' |')
    }
    return ($out -join $NL)
}

# 把攒好的文字输出成一个 Markdown 块（段落 / 列表项 / 标题 / 引用）
function Flush-HtmlBuf($st) {
    $raw = $st.Buf.ToString()
    [void]$st.Buf.Clear()
    if (-not $raw.Trim()) { return }

    $md = Convert-HtmlInline $raw
    if (-not $md.Trim()) { return }

    $lines = @($md -split "`n")

    if ($st.Lists.Count -gt 0) {
        $top = $st.Lists[$st.Lists.Count - 1]
        $depth = $st.Lists.Count - 1
        $marker = '- '
        if ($top.Type -eq 'ol') {
            $top.Index = $top.Index + 1
            $marker = [string]$top.Index + '. '
        }
        $first = $true
        foreach ($ln in $lines) {
            $txt = $ln.Trim()
            if (-not $txt) { continue }
            if ($first) {
                [void]$st.Blocks.Add(('  ' * $depth) + $marker + $txt)
                $first = $false
            } else {
                [void]$st.Blocks.Add(('  ' * ($depth + 1)) + $txt)
            }
        }
        return
    }

    if ($st.Head -gt 0) {
        [void]$st.Blocks.Add(('#' * $st.Head) + ' ' + (($md -replace "`r?`n", ' ').Trim()))
        $st.Head = 0
        return
    }

    if ($st.Quote -gt 0) {
        foreach ($ln in $lines) {
            $txt = $ln.Trim()
            [void]$st.Blocks.Add('> ' + $txt)
        }
        return
    }

    [void]$st.Blocks.Add($md.Trim())
}

# 一张图片
function Add-HtmlImage($st, [string]$tag) {
    $src = ''
    # data-src 优先：很多站点的 src 只是张占位小图
    foreach ($attr in @('data-src', 'data-original', 'data-lazy-src', 'data-actualsrc', 'src')) {
        $v = (Get-HtmlAttr $tag $attr).Trim()
        if ($v) { $src = $v; break }
    }
    if (-not $src) { return }
    if ($src -match '^(?i)data:') { return }        # 内嵌的小图标不要
    $src = Add-OssSuffix (Convert-HtmlEntities $src)
    $alt = (Convert-HtmlEntities (Get-HtmlAttr $tag 'alt')).Trim()
    if (-not $alt) { $alt = '图片' }
    Flush-HtmlBuf $st
    [void]$st.Blocks.Add('![' + $alt + '](' + $src + ')')
    $script:S.Images = $script:S.Images + 1
}

# 主转换：HTML 文本 → Markdown 正文
function Convert-HtmlToMarkdown([string]$html) {
    $NL = $script:S.NL
    $PH = [string][char]5
    $t = $html

    # 注释先删掉
    $t = [regex]::Replace($t, '(?s)<!--.*?-->', '')

    # 抽走代码块
    $extra = New-Object System.Collections.ArrayList
    $t = [regex]::Replace($t, '(?is)<pre\b([^>]*)>(.*?)</pre\s*>', {
        param($m)
        $lang = ''
        $lm = [regex]::Match($m.Groups[1].Value + ' ' + $m.Groups[2].Value, '(?i)(?:language|lang)[-:]([\w+#-]+)')
        if ($lm.Success) { $lang = $lm.Groups[1].Value }
        $code = [regex]::Replace($m.Groups[2].Value, '(?s)<[^>]+>', '')
        $code = Convert-HtmlEntities $code
        $code = $code -replace "`r`n", "`n"
        $code = $code.Trim("`n")
        $block = '```' + $lang + "`n" + $code + "`n" + '```'
        $idx = $extra.Add($block)
        return ([string][char]5 + $idx + [string][char]5)
    })

    # 抽走表格
    $t = [regex]::Replace($t, '(?is)<table\b[^>]*>.*?</table\s*>', {
        param($m)
        $md = Convert-HtmlTable $m.Value
        if (-not $md) { return '' }
        $idx = $extra.Add($md)
        return ([string][char]5 + $idx + [string][char]5)
    })

    # 这些标签连内容一起丢
    foreach ($tag in @('script', 'style', 'noscript', 'svg', 'canvas', 'iframe', 'object', 'embed', 'template', 'select', 'textarea', 'button', 'form')) {
        $t = [regex]::Replace($t, '(?is)<' + $tag + '\b[^>]*>.*?</' + $tag + '\s*>', '')
        $t = [regex]::Replace($t, '(?is)<' + $tag + '\b[^>]*/?>', '')
    }

    $st = @{
        Blocks = New-Object System.Collections.ArrayList
        Buf    = New-Object System.Text.StringBuilder
        Lists  = New-Object System.Collections.ArrayList
        Quote  = 0
        Head   = 0
    }

    $tokens = [regex]::Matches($t, '(?s)<!--.*?-->|<[^>]{0,600}?>|[^<]+')
    foreach ($tk in $tokens) {
        $s = $tk.Value
        if (-not $s.StartsWith('<')) {
            [void]$st.Buf.Append($s)          # 普通文字，先攒着
            continue
        }
        $nm = [regex]::Match($s, '^</?([a-zA-Z][a-zA-Z0-9:-]*)')
        $name = ''
        if ($nm.Success) { $name = $nm.Groups[1].Value.ToLower() }
        $isEnd = $s.StartsWith('</')

        switch ($name) {
            'br' {
                if (-not $isEnd) { [void]$st.Buf.Append([string][char]2) }
            }
            'hr' {
                if (-not $isEnd) { Flush-HtmlBuf $st; [void]$st.Blocks.Add('---') }
            }
            'img' {
                if (-not $isEnd) { Add-HtmlImage $st $s }
            }
            'h1' { Flush-HtmlBuf $st; if ($isEnd) { $st.Head = 0 } else { $st.Head = 1 } }
            'h2' { Flush-HtmlBuf $st; if ($isEnd) { $st.Head = 0 } else { $st.Head = 2 } }
            'h3' { Flush-HtmlBuf $st; if ($isEnd) { $st.Head = 0 } else { $st.Head = 3 } }
            'h4' { Flush-HtmlBuf $st; if ($isEnd) { $st.Head = 0 } else { $st.Head = 4 } }
            'h5' { Flush-HtmlBuf $st; if ($isEnd) { $st.Head = 0 } else { $st.Head = 5 } }
            'h6' { Flush-HtmlBuf $st; if ($isEnd) { $st.Head = 0 } else { $st.Head = 6 } }
            'ul' {
                Flush-HtmlBuf $st
                if ($isEnd) {
                    if ($st.Lists.Count -gt 0) { $st.Lists.RemoveAt($st.Lists.Count - 1) }
                } else {
                    [void]$st.Lists.Add([pscustomobject]@{ Type = 'ul'; Index = 0 })
                }
            }
            'ol' {
                Flush-HtmlBuf $st
                if ($isEnd) {
                    if ($st.Lists.Count -gt 0) { $st.Lists.RemoveAt($st.Lists.Count - 1) }
                } else {
                    $startAt = 0
                    [void][int]::TryParse((Get-HtmlAttr $s 'start'), [ref]$startAt)
                    # 序号在用的时候先加 1，所以这里先减掉，保证 start="3" 从 3 开始
                    if ($startAt -lt 1) { $startAt = 0 } else { $startAt = $startAt - 1 }
                    [void]$st.Lists.Add([pscustomobject]@{ Type = 'ol'; Index = $startAt })
                }
            }
            'li' {
                if ($isEnd) { Flush-HtmlBuf $st }
                else { Flush-HtmlBuf $st }      # li 的结束标签常被省略，下个 li 开始时就得断开
            }
            'blockquote' {
                Flush-HtmlBuf $st
                if ($isEnd) { if ($st.Quote -gt 0) { $st.Quote = $st.Quote - 1 } }
                else { $st.Quote = $st.Quote + 1 }
            }
            { $_ -in @('p', 'div', 'section', 'article', 'main', 'header', 'footer', 'aside', 'nav', 'dl', 'dt', 'dd', 'figure', 'figcaption', 'address', 'center', 'fieldset', 'body', 'html') } {
                Flush-HtmlBuf $st
            }
            default {
                [void]$st.Buf.Append($s)       # 行内标签原样留着，flush 时统一处理
            }
        }
    }
    Flush-HtmlBuf $st

    # 拼起来：列表项之间只换行，其它块之间空一行
    $sb = New-Object System.Text.StringBuilder
    $prevList = $false
    foreach ($b in $st.Blocks) {
        $isList = ($b -match '^\s*(-|\d+\.) ')
        if ($sb.Length -gt 0) {
            if ($isList -and $prevList) { [void]$sb.Append($NL) }
            else { [void]$sb.Append($NL + $NL) }
        }
        [void]$sb.Append($b)
        $prevList = $isList
    }
    $text = $sb.ToString()

    # 把代码块和表格放回原处
    $text = [regex]::Replace($text, '\u0005(\d+)\u0005', {
        param($m)
        $i = [int]$m.Groups[1].Value
        if ($i -ge 0 -and $i -lt $extra.Count) { return $extra[$i] }
        return ''
    })

    $text = [regex]::Replace($text, '(\r?\n){3,}', ($NL + $NL))
    return ($text.Trim() + $NL)
}

# 读一个 .html/.htm 文件，转成 { 标题、正文、日期 }
function Convert-HtmlDocument([string]$path) {
    $raw = Read-TextSmart $path

    $title = ''
    $dateStr = ''

    # 文件自带 Markdown 表头的，沿用里面的标题和日期
    $fmm = [regex]::Match($raw, '(?s)^\s*---\r?\n(.*?)\r?\n---\r?\n?')
    if ($fmm.Success -and $fmm.Groups[1].Value -match '(?m)^\s*title\s*:') {
        $fm = $fmm.Groups[1].Value
        $tm = [regex]::Match($fm, '(?m)^\s*title\s*:\s*(.+)$')
        if ($tm.Success) { $title = $tm.Groups[1].Value.Trim().Trim('"').Trim("'") }
        $dm = [regex]::Match($fm, '(?m)^\s*date\s*:\s*(\d{4}-\d{2}-\d{2})')
        if ($dm.Success) { $dateStr = $dm.Groups[1].Value }
        $raw = $raw.Substring($fmm.Length)
    }

    # og:title / <title>
    if (-not $title) {
        $om = [regex]::Match($raw, '(?is)<meta\b[^>]*og:title[^>]*>')
        if ($om.Success) { $title = (Convert-HtmlEntities (Get-HtmlAttr $om.Value 'content')).Trim() }
    }
    if (-not $title) {
        $tm2 = [regex]::Match($raw, '(?is)<title[^>]*>(.*?)</title\s*>')
        if ($tm2.Success) {
            $title = (Convert-HtmlEntities $tm2.Groups[1].Value).Trim()
            # 网页标题常带站点名，例如「文章标题 - 某某博客」
            $parts = $title -split '\s*[-–—_|]\s+|\s+[-–—_|]\s*'
            if ($parts.Count -gt 1 -and $parts[0].Trim().Length -ge 4) { $title = $parts[0].Trim() }
        }
    }

    # 发布日期的线索
    if (-not $dateStr) {
        $pm = [regex]::Match($raw, '(?is)<meta\b[^>]*(?:published_time|publishdate|pubdate|article:published)[^>]*>')
        if ($pm.Success) {
            $dv = (Get-HtmlAttr $pm.Value 'content')
            $dmm = [regex]::Match($dv, '(\d{4})[-/年.](\d{1,2})[-/月.](\d{1,2})')
            if ($dmm.Success) { $dateStr = $dmm.Groups[1].Value + '-' + $dmm.Groups[2].Value + '-' + $dmm.Groups[3].Value }
        }
    }

    # 只要 body 里面的东西
    $bodyHtml = $raw
    $bm = [regex]::Match($raw, '(?is)<body\b[^>]*>(.*)</body\s*>')
    if ($bm.Success) { $bodyHtml = $bm.Groups[1].Value }

    # 先去掉导航、页脚这类页面装饰
    foreach ($tag in @('nav', 'footer', 'aside', 'head')) {
        $bodyHtml = [regex]::Replace($bodyHtml, '(?is)<' + $tag + '\b[^>]*>.*?</' + $tag + '\s*>', '')
    }

    # 有 <article> 就只用它（正文更纯）
    $am = [regex]::Match($bodyHtml, '(?is)<article\b[^>]*>(.*?)</article\s*>')
    if ($am.Success -and ($am.Groups[1].Value -replace '<[^>]+>', '').Trim().Length -ge 120) {
        $bodyHtml = $am.Groups[1].Value
    }

    $body = Convert-HtmlToMarkdown $bodyHtml

    # 正文里第一个一级标题当作文章标题。
    # 默认把它从正文里移除（页面上标题只显示一次）；想保留就把 KeepTitle 打开。
    if (-not $title) {
        $h1 = [regex]::Match($body, '(?m)^#\s+(.+)$')
        if ($h1.Success) { $title = $h1.Groups[1].Value.Trim() }
    }
    if ($title -and -not $script:S.KeepTitle) {
        $wantNorm = $title -replace '\s+', ''
        $body = [regex]::Replace($body, '(?m)^#\s+(.+)\r?$', {
            param($m)
            $got = ($m.Groups[1].Value -replace '\s+', '')
            if ($got -eq $wantNorm) { return '' }
            return $m.Value
        })
    }
    # 删掉标题后可能留下连续空行，统一收一遍
    $body = [regex]::Replace($body, '(\r?\n){3,}', ($script:S.NL + $script:S.NL)).Trim() + $script:S.NL

    $created = $null
    if ($dateStr) {
        $parsedDate = [datetime]::MinValue
        if ([datetime]::TryParse($dateStr, [ref]$parsedDate)) { $created = $parsedDate }
    }
    # 以前这里会退回「文件修改时间」，但那只是文件属性，不是文章日期；
    # 现在不再用它，没有网页发布时间就走「默认昨天」。

    return [pscustomobject]@{
        Title   = $title
        Body    = $body
        Created = $created
    }
}

# =============================================================================
# 八、正文转换
# =============================================================================

function Convert-Body {
    $doc = Read-Xml (Join-Path $script:S.ZipRoot 'word\document.xml')
    if ($null -eq $doc) {
        throw '这个文件里读不到正文，可能不是有效的 .docx 文件'
    }

    $body = $null
    foreach ($c in $doc.DocumentElement.ChildNodes) {
        if ($c.LocalName -eq 'body') { $body = $c; break }
    }
    if ($null -eq $body) { throw '这个文件里读不到正文内容' }

    $blocks = New-Object System.Collections.ArrayList
    $docTitle = ''
    $seenContent = $false
    $lastListType = ''

    foreach ($child in $body.ChildNodes) {
        if ($child.NodeType -ne 'Element') { continue }

        if ($child.LocalName -eq 'p' -and $child.NamespaceURI -eq $W) {
            $segs = Collect-Segments $child
            $line = Render-Inline $segs $false
            if (-not $line.Trim()) { continue }   # 空段落跳过，Markdown 不需要

            $level = Get-HeadingLevel $child

            # 作者手打的「### 案例1：…」也当标题。
            # Word 里这种段落常常整段加粗，会被包成 **### 案例1**，看着像乱码，这里拆开还原。
            $headline = $line
            $wrapMatch = [regex]::Match($headline, '^\*\*(?<inner>[\s\S]+)\*\*$')
            if ($wrapMatch.Success) { $headline = $wrapMatch.Groups['inner'].Value }
            $handHash = [regex]::Match($headline, '^\s*(#{1,6})\s+')
            if ($handHash.Success) {
                $level = $handHash.Groups[1].Value.Length
                $line = ($headline.Substring($handHash.Length) -replace '\*\*', '').Trim()
            }

            # 第一段如果是「标题」样式，把它当文章标题抽出来
            if ($level -eq 0 -and -not $docTitle) {
                $docTitle = ($line -replace '\*\*|^#+\s*', '').Trim()
                $seenContent = $true
                if ($script:S.KeepTitle) { [void]$blocks.Add('# ' + $docTitle) }
                continue
            }
            if ($level -eq 1 -and -not $docTitle -and -not $seenContent) {
                $docTitle = ($line -replace '\*\*|^#+\s*', '').Trim()
                $seenContent = $true
                if ($script:S.KeepTitle) { [void]$blocks.Add('# ' + $docTitle) }
                continue
            }

            $seenContent = $true

            if ($level -ge 1) {
                # 标题本身自带层级和加粗，里面的 ** 只会让源码变脏（Markdown 标题里也没必要再加粗）
                $titleText = ($line -replace '\*\*', '').Trim()
                if ($titleText) { [void]$blocks.Add(('#' * $level) + ' ' + $titleText) }
                $lastListType = ''
                continue
            }
            if (Test-IsQuote $child) {
                [void]$blocks.Add('> ' + $line.Replace($script:S.NL, '  ' + $script:S.NL + '> '))
                $lastListType = ''
                continue
            }
            $li = Get-ListInfo $child
            if ($li.Type) {
                $indent = '  ' * [Math]::Min($li.Level, 4)
                $marker = '- '
                if ($li.Type -eq 'ol') { $marker = '1. ' }
                $blockText = $indent + $marker + $line.Trim()
                if ($lastListType -eq $li.Type -and $blocks.Count -gt 0) {
                    # 连续的同类型列表项之间不空行，否则 Markdown 会渲染成「松散列表」，
                    # 每项都被包上一层段落、间距变大，看着很散
                    $blocks[$blocks.Count - 1] = $blocks[$blocks.Count - 1] + $script:S.NL + $blockText
                } else {
                    [void]$blocks.Add($blockText)
                }
                $lastListType = $li.Type
                continue
            }
            [void]$blocks.Add($line.Trim())
            $lastListType = ''
        }
        elseif ($child.LocalName -eq 'tbl') {
            $tableMd = Render-Table $child
            if ($tableMd.Trim()) {
                [void]$blocks.Add($tableMd.TrimEnd())
            }
            $lastListType = ''
        }
        # w:sectPr 等其它节点直接忽略
    }

    $text = $blocks -join ($script:S.NL + $script:S.NL)
    $text = Resolve-Images $text
    # 清掉可能残留的占位符
    $text = $text.Replace($IMGT, '').Replace($IMGSEP, '')
    # 压缩多余空行
    $text = [regex]::Replace($text, '(\r?\n){3,}', ($script:S.NL + $script:S.NL))
    $text = $text.Trim() + $script:S.NL

    return [pscustomobject]@{ Title = $docTitle; Body = $text }
}

# =============================================================================
# 九、表头生成
# =============================================================================

function Build-FrontMatter([string]$title, [string]$dateStr, $categories, $tags) {
    $NL = $script:S.NL
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('---')
    [void]$lines.Add('title: ' + (Convert-YamlSafe $title))
    [void]$lines.Add('date: ' + $dateStr)
    [void]$lines.Add('categories: [' + ($categories -join ', ') + ']')
    if ($tags -and $tags.Count -gt 0) {
        [void]$lines.Add('tags: [' + ($tags -join ', ') + ']')
    } else {
        [void]$lines.Add('tags: []')
    }
    [void]$lines.Add('---')
    return (($lines -join $NL) + $NL)
}

# =============================================================================
# 十、交互问答
# =============================================================================

function Ask-Text([string]$prompt, [string]$default) {
    if ($default) {
        $hint = '（直接回车 = ' + $default + '）'
    } else {
        $hint = '（直接回车 = 不填）'
    }
    $got = Read-Host ($prompt + ' ' + $hint)
    if ($null -eq $got) { return $default }
    $got = $got.Trim()
    if (-not $got) { return $default }
    return $got
}

function Ask-Category {
    Write-Host ''
    Write-Host '  可选分类（输入前面的编号，例如 12）'
    $table = @{}
    $idx = 0
    foreach ($top in $CATEGORY_TREE.Keys) {
        foreach ($sub in $CATEGORY_TREE[$top]) {
            $idx++
            $table[[string]$idx] = @($top, $sub)
            $mark = ''
            if ($top -eq '工作' -and $sub -eq '诉讼实务') { $mark = '   ← 默认' }
            Write-Host ('    {0,2}. {1} / {2}{3}' -f $idx, $top, $sub, $mark)
        }
    }
    $got = Ask-Text '  分类编号' '1'
    if ($table.ContainsKey($got)) { return $table[$got] }
    # 也可能直接打了「工作/诉讼实务」
    $parts = @($got -split '[/,，、]' | Where-Object { $_.Trim() })
    if ($parts.Count -ge 2) { return @($parts[0].Trim(), $parts[1].Trim()) }
    Write-Note '没看懂这个分类，先用默认的 工作 / 诉讼实务'
    return @('工作', '诉讼实务')
}

function Ask-Tags {
    $got = Ask-Text '  标签（多个用逗号隔开，2~4 个比较好看）' ''
    return @($got -split '[,，、]' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
}

# 正文里被认成「文章标题」的那一行，是删掉还是留着
function Ask-TitlePolicy {
    Write-Host ''
    Write-Host '  正文开头那行标题，怎么处理？'
    Write-Host '    1) 删掉（默认）—— 网页顶部已经显示标题，正文里再出现一次就重复了'
    Write-Host '    2) 保留 —— 正文开头照样留一条标题'
    $got = Ask-Text '  请选 1 或 2' '1'
    if ($got -eq '2' -or $got -eq '保留' -or $got -eq '留') { return $true }
    return $false
}

# 读一个 .docx 文件，转成 { 标题、正文、日期 }
function Convert-DocxDocument([string]$path) {
    $docTitle = ''
    $bodyText = ''
    $created = $null

    # ---- 解压 docx 到临时目录 ----
    $script:S.WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ('word2md_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:S.WorkDir | Out-Null
    try {
        $extract = Join-Path $script:S.WorkDir 'x'
        New-Item -ItemType Directory -Force -Path $extract | Out-Null

        # 优先用 .NET 自带的解压，比 Expand-Archive 快得多；
        # 万一系统策略禁止加载该类，就退回 Expand-Archive（慢一点但一定有）
        $unzipped = $false
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            [System.IO.Compression.ZipFile]::ExtractToDirectory($path, $extract)
            $unzipped = $true
        } catch {
            $unzipped = $false
        }
        if (-not $unzipped) {
            $zipCopy = Join-Path $script:S.WorkDir 'doc.zip'
            Copy-Item -LiteralPath $path -Destination $zipCopy -Force
            Expand-Archive -LiteralPath $zipCopy -DestinationPath $extract -Force
        }
        $script:S.ZipRoot = $extract

        $script:S.Rels = Load-Rels
        $script:S.Styles = Load-Styles
        $script:S.Numbering = Load-Numbering

        $parsed = Convert-Body
        $docTitle = $parsed.Title
        $bodyText = $parsed.Body
        # 文档属性里的「创建时间」不等于发布日期（往往就是刚才另存的时间），
        # 所以不再拿它当文章日期，统一走「默认昨天」。
        $created = $null
    }
    finally {
        if (Test-Path -LiteralPath $script:S.WorkDir) {
            Remove-Item -LiteralPath $script:S.WorkDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    return [pscustomobject]@{
        Title   = $docTitle
        Body    = $bodyText
        Created = $created
    }
}

# =============================================================================
# 十一、单个文件转换
# =============================================================================

function Convert-One {
    param(
        [string]$DocxPath,
        $Preset,
        [bool]$Interactive,
        [int]$Number
    )

    Write-Head ('正在处理：' + (Split-Path -Leaf $DocxPath))

    $slug = $Slug
    if (-not $slug) { $slug = ('post-{0:D3}' -f $Number) }

    $script:S.AssetsDir = Join-Path $script:S.AssetsBase $slug
    $script:S.ImgRel = '/assets/img/' + $slug
    $script:S.Images = 0
    $script:S.ImageSaved = 0

    # ---- 按文件类型分头转换 ----
    $ext = [System.IO.Path]::GetExtension($DocxPath).ToLower()
    if ($ext -eq '.html' -or $ext -eq '.htm') {
        $parsed = Convert-HtmlDocument $DocxPath
    } else {
        $parsed = Convert-DocxDocument $DocxPath
    }
    $docTitle = $parsed.Title
    $bodyText = $parsed.Body
    $created = $parsed.Created

    # ---- 标题 ----
    $autoTitle = $docTitle
    if (-not $autoTitle) { $autoTitle = [System.IO.Path]::GetFileNameWithoutExtension($DocxPath) }
    if ($Title) {
        $useTitle = $Title
    } elseif ($Interactive) {
        $useTitle = Ask-Text '【1/4】文章标题' $autoTitle
    } else {
        $useTitle = $autoTitle
    }

    # ---- 分类 ----
    if ($Preset) {
        $cats = $Preset.Categories
    } elseif ($Category) {
        $cats = @($Category -split '[/,，、]' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
    } elseif ($Interactive) {
        $cats = Ask-Category
    } else {
        $cats = @('工作', '诉讼实务')
    }
    if ($cats.Count -lt 2) { $cats = @($cats[0], '待整理') }

    # ---- 标签 ----
    if ($Preset) {
        $tagList = $Preset.Tags
    } elseif ($Tags) {
        $tagList = @($Tags -split '[,，、]' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
    } elseif ($Interactive) {
        $tagList = Ask-Tags
    } else {
        $tagList = @()
    }

    # ---- 日期 ----
    # 默认用「昨天」：稿子多半是隔天发布，日期写昨天更符合实际。
    # 明确指定了 -Date、或原文里带发布时间（网页 published_time / 文档创建时间），仍按那个来。
    if ($Preset -and $Preset.Date) {
        $when = $Preset.Date
    } elseif ($Date) {
        $when = Convert-ToDate $Date
    } elseif ($Interactive) {
        $dft = $created
        if (-not $dft) { $dft = (Get-Date).AddDays(-1) }
        $input = Ask-Text '【4/4】发布日期（格式 2026-10-28）' $dft.ToString('yyyy-MM-dd')
        $when = Convert-ToDate $input
    } else {
        $when = $created
        if (-not $when) { $when = (Get-Date).AddDays(-1) }
    }

    # Jekyll 不发布「未来日期」的文章，这里兜底，免得转完却看不到
    if ($when -gt (Get-Date)) {
        Write-Note '[提示] 识别出的日期在未来，已改用当前时间'
        $when = Get-Date
    }
    $dateStr = Format-JekyllDate $when

    # ---- 组装 ----
    $fm = Build-FrontMatter $useTitle $dateStr $cats $tagList
    $content = $fm + $script:S.NL + $bodyText

    $outName = $when.ToString('yyyy-MM-dd') + '-' + $slug + '.md'
    $outPath = Join-Path $script:S.PostsDir $outName

    Write-Note ('标题：' + $useTitle)
    if ($script:S.KeepTitle) {
        Write-Note '正文标题：保留（正文开头也留着这条标题）'
    } else {
        Write-Note '正文标题：已从正文删掉（页面顶部仍显示，不会重复）'
    }
    Write-Note ('分类：' + ($cats -join ' / '))
    if ($tagList.Count -gt 0) {
        Write-Note ('标签：' + ($tagList -join '、'))
    } else {
        Write-Note '标签：（没填，之后可以在 md 里补）'
    }
    Write-Note ('日期：' + $dateStr)
    if ($DryRun) {
        Write-Note ('图片：共 ' + $script:S.Images + ' 张（预览模式不实际压缩）')
    } else {
        Write-Note ('图片：共 ' + $script:S.Images + ' 张，其中 ' + $script:S.ImageSaved + ' 张已压缩')
    }

    if ($DryRun) {
        Write-Host ''
        Write-Note '---- 以下是转换结果预览（--DryRun 模式，没有写任何文件）----'
        Write-Host ''
        Write-Host $content
        Write-Host ''
        Write-Note '---- 预览结束 ----'
        return $null
    }

    # 关键：必须写「不带 BOM 的 UTF-8」。
    # 带 BOM 的话文件开头会多一个看不见的字符，Jekyll 会认不出表头、整篇文章失效。
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($outPath, $content, $utf8NoBom)

    Write-Host ''
    Write-Note ('[完成] 文章已生成：' + $outPath)
    # 只有真的把图片导出来了才提示这个文件夹（网页里的图片是外链，不需要导出）
    if (-not $DryRun -and (Test-Path -LiteralPath $script:S.AssetsDir)) {
        Write-Note ('[完成] 图片已放进：' + $script:S.AssetsDir)
    }
    return $outPath
}

# =============================================================================
# 十二、主流程
# =============================================================================

function Main {
    # 注意：PowerShell 不区分大小写，这里千万别再叫 $root，
    # 否则会把用户传进来的 -Root 参数覆盖掉（就分不清「他自己指定」还是「自动找到」了）。
    $found = Find-Root

    # 常规位置没找到时，翻一下上次记住的博客目录（老版本留下的功能，兼容保留）
    if (-not $found) {
        $memo = Read-RootMemo
        if ($memo) { $found = Test-BlogRoot $memo }
        if ($found) { Write-Note ('[提示] 用上次记住的博客目录：' + $found) }
    }

    $script:S.DryRun = [bool]$DryRun
    $script:S.KeepTitle = [bool]$KeepTitle
    $script:S.MaxWidth = $MaxWidth
    $script:S.MaxHeight = $MaxHeight
    $script:S.JpegQuality = $JpegQuality

    # ---------- 决定这次把文件写到哪儿 ----------
    # 三种情况，全自动判断，绝不因为「找不到博客」而罢工
    $toolDir = $PSScriptRoot
    if (-not $toolDir -and $PSCommandPath) { $toolDir = Split-Path -Parent $PSCommandPath }
    if (-not $toolDir) { $toolDir = (Get-Location).Path }

    # 明确写了 -OutDir（且没写 -Root）时，以 -OutDir 为准：
    # 不能因为脚本恰好躺在博客目录里，就把文件偷偷写进 _posts。
    if ($found -and -not ($OutDir -and -not $Root)) {
        # ① 在博客里：直接写进 _posts + assets\img
        $script:S.Mode = 'blog'
        $script:S.Root = $found
        $script:S.PostsDir = Join-Path $found '_posts'
        $script:S.AssetsBase = Join-Path $found 'assets\img'
        if ($Root -and $Root.TrimEnd('\', '/') -ne $found.TrimEnd('\', '/')) {
            Write-Note ('[提示] 自动往上找到了博客根目录：' + $found)
        }
    }
    elseif ($OutDir) {
        # ② 用户指定了输出目录：只管存文件，不需要是博客
        $out = $OutDir.Trim().Trim('"').Trim("'")
        try { $out = [System.IO.Path]::GetFullPath($out) } catch { }
        $script:S.Mode = 'outdir'
        $script:S.Root = $out
        $script:S.PostsDir = $out
        $script:S.AssetsBase = Join-Path $out 'assets\img'
    }
    else {
        # ③ 便携模式：拷到哪儿就在哪儿用，输出到本文件夹的「输出」子目录
        $script:S.Mode = 'portable'
        $script:S.Root = $toolDir
        $script:S.PostsDir = Join-Path $toolDir '输出'
        $script:S.AssetsBase = Join-Path $script:S.PostsDir 'assets\img'
    }

    # 输出目录不存在就建；建不了（比如放在只读U盘、或在 C:\ 根目录）才报错
    if (-not $DryRun) {
        try {
            if (-not (Test-Path -LiteralPath $script:S.PostsDir)) {
                New-Item -ItemType Directory -Force -Path $script:S.PostsDir | Out-Null
            }
        } catch {
            Write-Host ''
            Write-Host '[错误] 没法在这里创建输出文件夹：' + $script:S.PostsDir
            Write-Host '       可能是这个位置不允许写文件（只读U盘、光盘、系统目录）。'
            Write-Host '       把整个工具文件夹复制到桌面或文档里再用，或者加 -OutDir 指定别处。'
            return
        }
    }

    if ($script:S.Mode -eq 'portable') {
        Write-Host ''
        Write-Host '  ── 便携模式 ──────────────────────────────────────────'
        Write-Host '  这个位置不是博客目录，所以不往 _posts 里写。'
        Write-Host ('  生成的文章会放进：' + $script:S.PostsDir)
        Write-Host '  （md 拿去放进博客 _posts；图片文件夹放进博客 assets\img 即可）'
        Write-Host '  ──────────────────────────────────────────────────────'
    }

    # ---------- 收集要处理的文件 ----------
    $targets = New-Object System.Collections.ArrayList
    if (-not $Files -or $Files.Count -eq 0) {
        Write-Host ''
        Write-Host '  请把要转换的文件拖进本窗口，然后回车。'
        Write-Host '  支持两种：Word 文档（.docx）、网页文件（.html / .htm）'
        Write-Host '  （拖进来后窗口里会出现一串文件路径，这是正常的）'
        Write-Host ''
        $typed = Read-Host '  文件路径'
        if (-not $typed) {
            Write-Host '  没有输入文件，已退出。'
            return
        }
        $Files = @($typed)
    }

    foreach ($item in $Files) {
        if (-not $item) { continue }
        $clean = $item.Trim().Trim('"').Trim("'")
        if (Test-Path -LiteralPath $clean -PathType Container) {
            foreach ($f in Get-ChildItem -LiteralPath $clean -File) {
                $e = [System.IO.Path]::GetExtension($f.Name).ToLower()
                if ($e -eq '.docx' -or $e -eq '.html' -or $e -eq '.htm') {
                    [void]$targets.Add($f.FullName)
                }
            }
        } elseif (Test-Path -LiteralPath $clean -PathType Leaf) {
            [void]$targets.Add((Resolve-Path -LiteralPath $clean).Path)
        } else {
            Write-Note ('[跳过] 找不到这个文件：' + $clean)
        }
    }

    # 过滤 Word 打开文件时产生的 ~$ 锁文件和用不上的格式
    $valid = New-Object System.Collections.ArrayList
    foreach ($t in $targets) {
        $name = Split-Path -Leaf $t
        if ($name.StartsWith('~$')) { continue }
        $e = [System.IO.Path]::GetExtension($t).ToLower()
        if ($e -ne '.docx' -and $e -ne '.html' -and $e -ne '.htm') {
            Write-Note ('[跳过] 只支持 .docx / .html / .htm，不支持：' + $name)
            continue
        }
        [void]$valid.Add($t)
    }

    if ($valid.Count -eq 0) {
        Write-Host ''
        Write-Host '[错误] 没有可转换的文件。'
        Write-Host '       支持 .docx、.html、.htm 三种。'
        Write-Host '       如果文件是老的 .doc 格式，请先用 Word 打开它，'
        Write-Host '       点「文件 → 另存为」，类型选 .docx，存一份再转。'
        return
    }

    $interactive = (-not $Yes)

    # ---------- 正文里的标题要不要留（只问一次，本次全部文件通用） ----------
    if ($interactive -and -not $KeepTitle) {
        $script:S.KeepTitle = Ask-TitlePolicy
    }

    # ---------- 批量时先把公共信息问一遍 ----------
    $preset = $null
    if ($interactive -and $valid.Count -gt 1) {
        Write-Host ''
        Write-Host ('一共 {0} 个文件。先统一回答一次，所有文件共用：' -f $valid.Count)
        $pcats = Ask-Category
        $ptags = Ask-Tags
        $pd = Ask-Text '  发布日期（格式 2026-10-28，留空 = 各用文件里的创建时间）' ''
        $preset = [pscustomobject]@{
            Categories = $pcats
            Tags       = $ptags
            Date       = $(if ($pd) { Convert-ToDate $pd } else { $null })
        }
    }

    $number = Get-NextPostNumber
    Write-Host ''
    Write-Note ('本次从 post-{0:D3} 开始编号。' -f $number)

    $done = New-Object System.Collections.ArrayList
    foreach ($f in $valid) {
        try {
            $out = Convert-One -DocxPath $f -Preset $preset -Interactive $interactive -Number $number
            if ($out) { [void]$done.Add($out) }
            $number++
        } catch {
            Write-Host ''
            Write-Note ('[失败] ' + (Split-Path -Leaf $f) + '：' + $_.Exception.Message)
        }
    }

    # ---------- 汇总 ----------
    Write-Host ''
    Write-Host ('=' * 64)
    if ($DryRun) {
        Write-Host ('  预览完毕，共 ' + $valid.Count + ' 个文件，没有写任何文件。')
    } else {
        Write-Host ('  全部完成，共生成 ' + $done.Count + ' 篇文章：')
        foreach ($d in $done) { Write-Host ('    ' + $d) }
        Write-Host ''
        Write-Host '  下一步：'
        if ($script:S.Mode -eq 'blog') {
            Write-Host '    1. 打开上面这些 .md 文件，检查排版和图片位置'
            Write-Host '    2. 确认没问题，双击 deploy.bat 发布'
        } else {
            Write-Host '    1. 双击同目录的「6-文章编辑器.html」，把 md 拖进去边改边看'
            Write-Host '    2. 要发到博客：md 放进 _posts；输出\assets\img\ 里的文件夹放进博客 assets\img\'
        }
    }
    Write-Host ('=' * 64)
}

# 启动
try {
    Main
} catch {
    Write-Host ''
    Write-Host '[出错了] ' + $_.Exception.Message
    Write-Host ''
    Write-Host '如果看不懂这个错误，请把上面这几行截图发给帮你做网站的人。'
    Write-Host '你的 Word 原件没有被改动。'
}
