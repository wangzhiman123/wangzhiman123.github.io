#Requires -Version 5.1
<#
================================================================================
  王志满律师博客 · 一键部署脚本（PowerShell 版，不需要安装 Git）
================================================================================

  怎么用：双击同目录下的  deploy.bat  就行（推荐）。
           也可以在本目录按住 Shift 右键 →「在此处打开 PowerShell 窗口」，然后运行：
               .\deploy.ps1

  它做了什么：
     1. 刷新每篇文章的浏览量（写入 _data/views.json、_data/pv_state.json）
     2. 把本地文件和线上仓库逐一比对，算出「新增 / 修改 / 删除」
     3. 通过 GitHub 官方接口，把改动组装成一次提交并推送到仓库
        （效果等同于 git add + commit + push，但本机不用装 Git）
     4. 自动等待 GitHub 构建，构建完成后告诉你结果和线上地址

  推送成功后，GitHub Actions 会自动构建并发布到：
     · 2019527.xyz          （火山引擎服务器）
     · GitHub Pages         （备用地址）

  可用参数：
     -DryRun         只预览会改动哪些文件，不真的上传（不需要令牌）
     -Message "..."  自定义提交说明
     -SkipViews      跳过刷新浏览量
     -SkipWatch      推送后不等待构建结果
     -Status         只看最近几次部署的状态，不做任何改动
     -SetToken       重新设置 / 更换 GitHub 令牌
     -Yes            删除较多「非文章」文件时不再询问（谨慎使用）
     -ResetBaseline  重新记录本地基准（确认本地副本已是最新时才用）
     -AllowStale     明知线上还有本地没有的更新，仍要覆盖（谨慎，可能丢文章）

  两道安全闸（默认开启，不用做任何设置）：
     1. 线上 SHA 乐观锁：部署前先比对「本地基准提交」和线上最新提交。
        只要线上存在本地副本不知道的改动（例如在 GitHub 网页上发过文章），
        脚本会直接中止并列出冲突文件，绝不用旧副本覆盖线上。
     2. 删除保护：本次只要涉及任意 .md 文件的删除，一定会列出来要求确认，
        -Yes 也绕不过；非 .md 文件删除达到 5 个以上时同样会询问。

  首次使用需要在 GitHub 生成一个「访问令牌」填一次，之后脚本自动记住。
================================================================================
#>

[CmdletBinding()]
param(
    [string] $Message,
    [switch] $DryRun,
    [switch] $SkipViews,
    [switch] $SkipWatch,
    [switch] $Status,
    [switch] $SetToken,
    [switch] $Yes,
    [switch] $ResetBaseline,
    [switch] $AllowStale
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ============================== 基本配置 =====================================
$RepoOwner = 'wangzhiman123'
$RepoName  = 'wangzhiman123.github.io'
$Repo      = "$RepoOwner/$RepoName"
$Branch    = 'main'
$SiteUrl   = 'https://2019527.xyz'
$ActionsUrl = "https://github.com/$Repo/actions"

$TokenDir  = Join-Path $env:USERPROFILE '.wangzhiman-deploy'
$TokenFile = Join-Path $TokenDir 'token.dat'

$Root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$Root = (Resolve-Path -LiteralPath $Root).Path
Set-Location -LiteralPath $Root

# 不参与同步的目录 / 文件（等价于 .gitignore 的作用）
$ExcludeDirNames = @(
    '.git', '.workbuddy', '_site', 'node_modules', '.idea',
    '.bundle', 'vendor', '.jekyll-cache', '.sass-cache'
)
$ExcludeFileNames = @(
    'Gemfile.lock', 'package-lock.json', '.DS_Store', 'Thumbs.db',
    '.jekyll-metadata', 'deploy.log'
)
$ExcludePathPrefixes = @('assets/lib', '_sass/vendors', 'assets/js/dist')

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:Token = $null

# ============================== 输出小工具 ===================================
function Head([string] $m) { Write-Host ''; Write-Host "=== $m ===" -ForegroundColor Cyan }
function Say([string] $m)  { Write-Host "  $m" }
function Ok([string] $m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn([string] $m) { Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Fail([string] $m) { Write-Host "  [x]  $m" -ForegroundColor Red }

function Die([string] $m) {
    Write-Host ''
    Fail $m
    Write-Host ''
    try {
        if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
            Write-Host '按任意键退出…' -ForegroundColor DarkGray
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
    } catch { }
    exit 1
}

# ============================== 公共函数 =====================================
function Get-ApiError($ErrorRecord) {
    $resp = $null
    try { $resp = $ErrorRecord.Exception.Response } catch { }
    if ($null -ne $resp) {
        $code = ''
        try { $code = [int]$resp.StatusCode } catch { }
        $txt = ''
        try {
            $stream = $resp.GetResponseStream()
            if ($null -ne $stream) {
                $reader = New-Object IO.StreamReader($stream)
                $txt = $reader.ReadToEnd()
                $reader.Close()
            }
        } catch { }
        if ($txt.Length -gt 400) { $txt = $txt.Substring(0, 400) }
        return "HTTP $code $txt"
    }
    return $ErrorRecord.Exception.Message
}

function Invoke-GitHub {
    param(
        [Parameter(Mandatory)] [string] $Method,
        [Parameter(Mandatory)] [string] $Path,
        $Body,
        [int] $TimeoutSec = 300
    )
    $headers = @{
        'User-Agent' = 'wzm-blog-deploy'
        'Accept'     = 'application/vnd.github+json'
    }
    if ($script:Token) { $headers['Authorization'] = "token $script:Token" }

    $params = @{
        Method     = $Method
        Uri        = 'https://api.github.com' + $Path
        Headers    = $headers
        TimeoutSec = $TimeoutSec
    }
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 30 -Compress
        $params['Body'] = [Text.Encoding]::UTF8.GetBytes($json)
        $params['ContentType'] = 'application/json; charset=utf-8'
    }
    try {
        return Invoke-RestMethod @params
    } catch {
        throw (Get-ApiError $_)
    }
}

function Test-GitHubToken([string] $Plain) {
    try {
        $headers = @{ 'User-Agent' = 'wzm-blog-deploy'; 'Authorization' = "token $Plain" }
        $null = Invoke-WebRequest -Uri "https://api.github.com/repos/$Repo" -Headers $headers `
            -UseBasicParsing -TimeoutSec 30
        return $true
    } catch {
        return $false
    }
}

function Get-TokenScopes([string] $Plain) {
    try {
        $headers = @{ 'User-Agent' = 'wzm-blog-deploy'; 'Authorization' = "token $Plain" }
        $r = Invoke-WebRequest -Uri 'https://api.github.com/user' -Headers $headers `
            -UseBasicParsing -TimeoutSec 30
        return [string]$r.Headers['x-oauth-scopes']
    } catch {
        return ''
    }
}

function Save-Token([string] $Plain) {
    if (-not (Test-Path -LiteralPath $TokenDir)) {
        $null = New-Item -ItemType Directory -Path $TokenDir -Force
    }
    $sec = ConvertTo-SecureString $Plain -AsPlainText -Force
    $enc = ConvertFrom-SecureString $sec
    [IO.File]::WriteAllText($TokenFile, $enc, [Text.Encoding]::ASCII)
    try { (Get-Item -LiteralPath $TokenFile).Attributes = 'Hidden' } catch { }
}

function Read-StoredToken {
    if (-not (Test-Path -LiteralPath $TokenFile)) { return $null }
    try {
        $enc = ([IO.File]::ReadAllText($TokenFile, [Text.Encoding]::ASCII)).Trim()
        if (-not $enc) { return $null }
        $sec  = ConvertTo-SecureString $enc
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    } catch {
        return $null
    }
}

function Prompt-Token {
    Write-Host ''
    Write-Host '---- 需要设置 GitHub 访问令牌（只需一次，之后自动记住）----' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  获取步骤：'
    Write-Host '    1. 浏览器打开  https://github.com/settings/tokens/new'
    Write-Host '    2. Note 随便填，例如  blog-deploy'
    Write-Host '    3. Expiration 建议选  No expiration'
    Write-Host '    4. 勾选两个权限：  repo（整项）  和  workflow（整项）'
    Write-Host '    5. 拉到最下面点  Generate token，复制 ghp_ 开头的那串字符'
    Write-Host ''
    Write-Host '  （粘贴：在这个窗口按 鼠标右键 或 Ctrl+V；输入时不显示是正常的）' -ForegroundColor DarkGray
    Write-Host ''
    $sec = Read-Host '  把令牌粘贴到这里后按回车'
    return $sec
}

function Get-Token {
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }

    for ($round = 1; $round -le 3; $round++) {
        $stored = Read-StoredToken
        if ($stored) {
            if (Test-GitHubToken $stored) {
                $scopes = Get-TokenScopes $stored
                if ($scopes -and ($scopes -notmatch 'repo')) {
                    Warn "已保存的令牌缺少 repo 权限（当前权限：$scopes），请重新生成。"
                    Remove-Item -LiteralPath $TokenFile -Force -ErrorAction SilentlyContinue
                } else {
                    if ($scopes -and ($scopes -notmatch 'workflow')) {
                        Warn '令牌没有 workflow 权限，本次无法更新 .github/workflows 里的文件。'
                    }
                    return $stored
                }
            } else {
                Warn '本机保存的令牌已失效（可能被撤销或过期），需要重新设置。'
                Remove-Item -LiteralPath $TokenFile -Force -ErrorAction SilentlyContinue
            }
        }

        $plain = Prompt-Token
        $plain = ([string]$plain) -replace '\s', ''
        if (-not $plain) { Warn '没有输入内容，请重试。'; continue }

        if (-not (Test-GitHubToken $plain)) {
            Fail '这个令牌无法访问仓库，请确认：复制完整、且勾选了 repo + workflow 权限。'
            continue
        }
        Save-Token $plain
        Ok '令牌验证通过，已加密保存在本机（只能在这台电脑上使用）。'
        $scopes = Get-TokenScopes $plain
        if ($scopes -and ($scopes -notmatch 'workflow')) {
            Warn '注意：该令牌没有 workflow 权限，.github/workflows 下的文件将无法更新。'
        }
        return $plain
    }
    Die '连续 3 次都没能设置成功，已退出。'
}

# ---------------------------- 路径 / 文件处理 --------------------------------
function Test-ExcludedPath([string] $rel) {
    foreach ($p in $ExcludePathPrefixes) {
        if ($rel -eq $p -or $rel.StartsWith($p + '/')) { return $true }
    }
    return $false
}

function Get-LocalFiles {
    param([string] $Dir, [string] $Rel = '')

    foreach ($d in [IO.Directory]::GetDirectories($Dir)) {
        $name = [IO.Path]::GetFileName($d)
        if ($ExcludeDirNames -contains $name) { continue }
        $childRel = if ($Rel) { "$Rel/$name" } else { $name }
        if (Test-ExcludedPath $childRel) { continue }
        Get-LocalFiles -Dir $d -Rel $childRel
    }
    foreach ($f in [IO.Directory]::GetFiles($Dir)) {
        $name = [IO.Path]::GetFileName($f)
        if ($ExcludeFileNames -contains $name) { continue }
        if ($name -like '*.log' -or $name -like '*~') { continue }
        $childRel = if ($Rel) { "$Rel/$name" } else { $name }
        if (Test-ExcludedPath $childRel) { continue }
        [PSCustomObject]@{ Rel = $childRel; Full = $f }
    }
}

function Get-GitBlobSha {
    param([byte[]] $Bytes)
    $header = [Text.Encoding]::ASCII.GetBytes(("blob {0}" -f $Bytes.Length) + [char]0)
    $buf = New-Object byte[] ($header.Length + $Bytes.Length)
    [Buffer]::BlockCopy($header, 0, $buf, 0, $header.Length)
    if ($Bytes.Length -gt 0) {
        [Buffer]::BlockCopy($Bytes, 0, $buf, $header.Length, $Bytes.Length)
    }
    $sha1 = [Security.Cryptography.SHA1]::Create()
    try { $hash = $sha1.ComputeHash($buf) } finally { $sha1.Dispose() }
    return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

# ------------------------------ JSON 读写 ------------------------------------
# 刻意与 scripts/update_views.py 的输出格式保持逐字节一致：
#   2 空格缩进、键名升序、文件末尾一个换行、无 BOM
# 这样本地脚本和 GitHub 定时任务互相不会产生无意义的差异。
function Read-JsonMap([string] $path) {
    $map = @{}
    if (-not (Test-Path -LiteralPath $path)) { return $map }
    try {
        $raw = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
        $raw = $raw.TrimStart([char]0xFEFF).Trim()
        if (-not $raw) { return $map }
        $obj = $raw | ConvertFrom-Json
        foreach ($prop in $obj.PSObject.Properties) {
            $map[$prop.Name] = [int]$prop.Value
        }
    } catch { }
    return $map
}

function Write-JsonMap([string] $path, $map) {
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    $keys = @($map.Keys | Sort-Object)
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("{`n")
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $k = $keys[$i]
        $comma = if ($i -lt $keys.Count - 1) { ',' } else { '' }
        [void]$sb.Append(('  "{0}": {1}{2}' -f $k, [int]$map[$k], $comma))
        [void]$sb.Append("`n")
    }
    [void]$sb.Append("}`n")
    [IO.File]::WriteAllText($path, $sb.ToString(), (New-Object Text.UTF8Encoding $false))
}

# --------------------------- 文章路径推导 ------------------------------------
function Get-PostSlug([string] $fileName) {
    $base = $fileName
    foreach ($ext in @('.md', '.markdown')) {
        if ($base.EndsWith($ext, [StringComparison]::OrdinalIgnoreCase)) {
            $base = $base.Substring(0, $base.Length - $ext.Length)
            break
        }
    }
    if ($base -match '^\d{4}-\d{1,2}-\d{1,2}-(.*)$') { return $Matches[1] }
    return $base
}

function Get-PostUrlPath {
    param([string] $File, [string] $Slug)

    $head = ''
    try {
        $all = [IO.File]::ReadAllText($File, [Text.Encoding]::UTF8)
        $head = if ($all.Length -gt 4096) { $all.Substring(0, 4096) } else { $all }
    } catch { }

    if ($head.StartsWith('---')) {
        $end = $head.IndexOf('---', 3)
        if ($end -gt 0) {
            $fm = $head.Substring(3, $end - 3)
            foreach ($line in ($fm -split "`r?`n")) {
                if ($line -match '^\s*permalink\s*:\s*(.+?)\s*$') {
                    $perm = $Matches[1].Trim().Trim('"').Trim("'")
                    if ($perm) { return '/' + $perm.Trim('/') + '/' }
                    break
                }
            }
        }
    }
    return "/posts/$Slug/"
}

# ============================ 刷新浏览量 =====================================
function Update-Views {
    Head '刷新文章浏览量'

    $postsDir  = Join-Path $Root '_posts'
    $viewsFile = Join-Path $Root '_data\views.json'
    $stateFile = Join-Path $Root '_data\pv_state.json'
    $api = 'https://busuanzi.ibruce.info/busuanzi?jsonpCallback=BusuanziCb'
    $ua  = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
           '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

    if (-not (Test-Path -LiteralPath $postsDir)) { Warn '_posts 目录不存在，跳过这一步。'; return }

    $posts = @(Get-ChildItem -LiteralPath $postsDir -File |
        Where-Object { $_.Name -match '\.(md|markdown)$' } | Sort-Object Name)
    if ($posts.Count -eq 0) { Warn '没有找到文章，跳过这一步。'; return }

    # 基准数据优先取自线上仓库（GitHub 的定时任务也在维护这两个文件），
    # 避免本地和线上各记一套、互相覆盖。
    $fetchMap = {
        param([string] $name)
        $res = Invoke-GitHub -Method GET -Path "/repos/$Repo/contents/_data/$name?ref=$Branch"
        $txt = [Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String(($res.content -replace '\s', '')))
        $obj = $txt | ConvertFrom-Json
        $map = @{}
        foreach ($prop in $obj.PSObject.Properties) { $map[$prop.Name] = [int]$prop.Value }
        return $map
    }

    $state = $null
    try { $state = & $fetchMap 'pv_state.json'; Say '  已读取线上账本作为基准。' } catch { }
    if ($null -eq $state) {
        $state = Read-JsonMap $stateFile
        Say '  线上暂无账本，改用本地账本。'
    }

    $prevViews = $null
    try { $prevViews = & $fetchMap 'views.json' } catch { }
    if ($null -eq $prevViews) { $prevViews = Read-JsonMap $viewsFile }

    Say "  共 $($posts.Count) 篇文章，逐篇查询（约需 1～2 分钟，请勿关闭窗口）…"

    $views = @{}
    $okCount = 0; $failCount = 0; $idx = 0

    foreach ($p in $posts) {
        $idx++
        $slug    = Get-PostSlug $p.Name
        $urlPath = Get-PostUrlPath -File $p.FullName -Slug $slug
        $pageUrl = $SiteUrl + $urlPath

        $raw = $null
        for ($try = 0; $try -le 2; $try++) {
            try {
                $r = Invoke-WebRequest -Uri $api -Headers @{ 'Referer' = $pageUrl; 'User-Agent' = $ua } `
                    -UseBasicParsing -TimeoutSec 25
                $content = [string]$r.Content
                if ($content -match '"page_pv"\s*:\s*(\d+)') { $raw = [int]$Matches[1]; break }
            } catch { }
            if ($try -lt 2) { Start-Sleep -Milliseconds 1200 }
        }

        if ($null -eq $raw) {
            # 查询失败：沿用上一次的数值，账本不动（页面上不会突然变成 0）
            $failCount++
            if ($prevViews.ContainsKey($urlPath)) { $views[$urlPath] = $prevViews[$urlPath] }
            Write-Host ("    [{0,2}/{1}] {2,-14} 查询失败，沿用上次数值" -f $idx, $posts.Count, $slug)
        } else {
            $polls  = [int]$state[$urlPath] + 1
            $truePv = $raw - $polls
            if ($truePv -lt 0) { $truePv = 0 }
            $views[$urlPath] = $truePv
            $state[$urlPath] = $polls
            $okCount++
            Write-Host ("    [{0,2}/{1}] {2,-14} 接口={3}  已查询{4}次  ->  真实={5}" -f `
                $idx, $posts.Count, $slug, $raw, $polls, $truePv)
        }
        Start-Sleep -Milliseconds 400
    }

    Write-JsonMap $viewsFile $views
    Write-JsonMap $stateFile $state

    $total = 0
    foreach ($v in $views.Values) { $total += [int]$v }
    Ok "成功 $okCount 篇，失败 $failCount 篇，全站合计 $total 次浏览"
}

# ============================== 部署主流程 ===================================
function Get-RemoteSnapshot {
    $ref    = Invoke-GitHub -Method GET -Path "/repos/$Repo/git/ref/heads/$Branch"
    $commit = Invoke-GitHub -Method GET -Path "/repos/$Repo/git/commits/$($ref.object.sha)"
    $tree   = Invoke-GitHub -Method GET -Path "/repos/$Repo/git/trees/$($commit.tree.sha)?recursive=1"

    if ($tree.truncated) {
        Warn '仓库文件过多，接口返回被截断，比对可能不完整。'
    }

    $blobs = @{}
    foreach ($e in $tree.tree) {
        if ($e.type -eq 'blob') { $blobs[$e.path] = @{ Sha = $e.sha; Mode = $e.mode } }
    }
    return @{
        CommitSha = $ref.object.sha
        TreeSha   = $commit.tree.sha
        Blobs     = $blobs
    }
}

# ----------------------------------------------------------------------------
# 线上 SHA 乐观锁相关：本地基准 = 「这份本地副本是从哪个提交来的」
# 基准文件只存在本机（不进仓库、不上传），用来判断本地副本是否已经落后。
# ----------------------------------------------------------------------------
function Get-BaselinePath {
    $safe = $Repo -replace '[^A-Za-z0-9._-]', '-'
    return Join-Path $TokenDir "baseline-$safe.json"
}

function Read-Baseline {
    $f = Get-BaselinePath
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try {
        $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $j -and $j.sha) { return $j }
    } catch { }
    return $null
}

function Write-Baseline {
    param([Parameter(Mandatory)] [string] $Sha)
    $f = Get-BaselinePath
    if (-not (Test-Path -LiteralPath $TokenDir)) {
        New-Item -ItemType Directory -Path $TokenDir -Force | Out-Null
    }
    $obj = [PSCustomObject]@{
        repo    = $Repo
        branch  = $Branch
        sha     = $Sha
        updated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
    ($obj | ConvertTo-Json) | Set-Content -LiteralPath $f -Encoding UTF8
}

# 比对两个提交之间有哪些文件被改动过（用于判断「线上有多少本地不知道的改动」）
function Get-Divergence {
    param([string] $BaseSha, [string] $HeadSha)

    $res = @{ Ok = $false; AheadBy = 0; Commits = 0; Files = @(); Reason = '' }
    try {
        $cmp = Invoke-GitHub -Method GET -Path "/repos/$Repo/compare/$BaseSha...$HeadSha"
    } catch {
        $res.Reason = Get-ApiError $_
        return $res
    }
    $res.Ok = $true
    try { $res.AheadBy = [int]$cmp.ahead_by } catch { $res.AheadBy = 0 }
    try { $res.Commits = @($cmp.commits).Count } catch { $res.Commits = 0 }

    $names = New-Object System.Collections.ArrayList
    foreach ($f in @($cmp.files)) {
        if ($f.filename) { [void]$names.Add([string]$f.filename) }
    }
    $res.Files = $names.ToArray()
    return $res
}

function Show-Status {
    Head '最近几次部署情况'
    try {
        $runs = Invoke-GitHub -Method GET -Path "/repos/$Repo/actions/runs?per_page=5"
    } catch {
        Fail "查不到部署记录：$_"
        return
    }
    if (-not $runs.workflow_runs -or @($runs.workflow_runs).Count -eq 0) {
        Warn '还没有任何构建记录。'
        return
    }
    foreach ($r in @($runs.workflow_runs)) {
        $when = ''
        try { $when = ([datetime]$r.created_at).ToLocalTime().ToString('MM-dd HH:mm') } catch { }
        $mark = switch ($r.conclusion) {
            'success'   { '[OK]' }
            'failure'   { '[失败]' }
            'cancelled' { '[取消]' }
            default     { "[$($r.status)]" }
        }
        Write-Host ("  {0,-8} {1}  {2}" -f $mark, $when, $r.display_title)
        Write-Host ("           {0}" -f $r.html_url) -ForegroundColor DarkGray
    }
    Say ''
    Say "全部记录：$ActionsUrl"
}

function Wait-Deploy {
    param([string] $Sha, [int] $MaxMinutes = 15)

    Head '等待 GitHub 构建与发布'
    Say '  GitHub 正在编译网站并发布，通常 1～3 分钟…'

    $run = $null
    $elapsed = 0
    $deadline = (Get-Date).AddMinutes($MaxMinutes)

    while ((Get-Date) -lt $deadline) {
        try {
            $runs = Invoke-GitHub -Method GET -Path "/repos/$Repo/actions/runs?per_page=20"
            $run = @($runs.workflow_runs | Where-Object { $_.head_sha -eq $Sha }) | Select-Object -First 1
        } catch { $run = $null }

        if ($run -and $run.status -eq 'completed') { break }

        if ($run) {
            Write-Host ("    [{0,3}s] 状态：{1}" -f $elapsed, $run.status)
        } else {
            Write-Host ("    [{0,3}s] 等待任务启动…" -f $elapsed)
        }
        Start-Sleep -Seconds 10
        $elapsed += 10
    }

    if (-not $run) {
        Warn '暂时没有查到对应的构建任务，可能还在排队。'
        Say  "  请稍后到 $ActionsUrl 查看。"
        return
    }

    if ($run.status -ne 'completed') {
        Warn "等待超时，任务仍在进行（状态：$($run.status)）。"
        Say  "  查看进度：$($run.html_url)"
        return
    }

    Write-Host ''
    if ($run.conclusion -eq 'success') {
        Ok '构建部署成功！'
    } else {
        Fail "构建没有成功（结果：$($run.conclusion)）"
        Say  "  打开日志看看原因：$($run.html_url)"
    }

    # 逐个任务报告，特别是「推送到火山引擎服务器」那一步有没有跑
    try {
        $jobs = Invoke-GitHub -Method GET -Path "/repos/$Repo/actions/runs/$($run.id)/jobs"
        Say ''
        Say '  各步骤结果：'
        foreach ($j in @($jobs.jobs)) {
            $res = if ($j.conclusion) { $j.conclusion } else { $j.status }
            $color = switch ($j.conclusion) {
                'success' { 'Green' }
                'skipped' { 'DarkGray' }
                default   { 'Yellow' }
            }
            Write-Host ("    - {0,-40} {1}" -f $j.name, $res) -ForegroundColor $color
        }
        $serverJob = @($jobs.jobs | Where-Object { $_.name -like '*server*' })
        if ($serverJob -and $serverJob[0].conclusion -eq 'skipped') {
            Warn '推送到服务器那一步被跳过了 —— 说明仓库里 DEPLOY_TO_SERVER 变量不是 true，'
            Warn '2019527.xyz 上的内容不会更新（只有 GitHub Pages 会更新）。'
        }
    } catch { }
}

function Test-LiveSite {
    Head '验证线上站点'
    for ($try = 1; $try -le 3; $try++) {
        try {
            $r = Invoke-WebRequest -Uri $SiteUrl -UseBasicParsing -TimeoutSec 30
            if ($r.StatusCode -eq 200) {
                Ok "$SiteUrl 访问正常（HTTP 200）"
                return
            }
            Warn "返回 HTTP $($r.StatusCode)"
        } catch {
            Warn "第 $try 次访问失败：$($_.Exception.Message)"
        }
        if ($try -lt 3) { Start-Sleep -Seconds 10 }
    }
    Warn '站点暂时访问不到，稍后再看看（不影响已完成的部署）。'
}

# ================================ 开始执行 ===================================
try { Clear-Host } catch { }
Write-Host ''
Write-Host '  王志满律师博客 · 一键部署' -ForegroundColor White
Write-Host "  项目目录：$Root" -ForegroundColor DarkGray

Head '环境检查'
if (-not (Test-Path -LiteralPath (Join-Path $Root '_config.yml'))) {
    Die '这个目录里找不到 _config.yml，不像是博客项目。请确认 deploy.bat 放在项目根目录。'
}
Ok '找到 Jekyll 项目文件'
Ok "PowerShell $($PSVersionTable.PSVersion)"

if ($Status) { Show-Status; Write-Host ''; exit 0 }

# 只有真正要写入时才需要令牌
if (-not $DryRun) {
    if ($SetToken) { Remove-Item -LiteralPath $TokenFile -Force -ErrorAction SilentlyContinue }
    Head 'GitHub 身份验证'
    try { $script:Token = Get-Token } catch { Die $_ }
    Ok '身份验证通过'
} elseif ($SetToken) {
    Die '-SetToken 不能和 -DryRun 一起用。'
}

# ---------- 1. 刷新浏览量 ----------
if ($SkipViews) {
    Head '刷新文章浏览量'
    Warn '按你的要求跳过（-SkipViews）'
} elseif ($DryRun) {
    Head '刷新文章浏览量'
    Warn '预览模式下跳过，避免产生额外的查询记录'
} else {
    try {
        Update-Views
    } catch {
        Warn "刷新浏览量时出错，已跳过：$_"
    }
}

# ---------- 2. 对比远程仓库 ----------
Head '对比线上仓库'
try {
    $remote = Get-RemoteSnapshot
} catch {
    Die "无法读取仓库信息：$_
请检查网络是否能访问 GitHub。"
}
Ok "线上仓库共 $($remote.Blobs.Count) 个文件（基准提交 $($remote.CommitSha.Substring(0,7))）"

$localMap = @{}
foreach ($f in (Get-LocalFiles -Dir $Root)) { $localMap[$f.Rel] = $f.Full }
Say "  本地共 $($localMap.Count) 个文件待同步"

$changed = New-Object System.Collections.ArrayList
foreach ($rel in @($localMap.Keys | Sort-Object)) {
    $full = $localMap[$rel]
    $bytes = [IO.File]::ReadAllBytes($full)
    $sha = Get-GitBlobSha $bytes
    if ($remote.Blobs.ContainsKey($rel)) {
        if ($remote.Blobs[$rel].Sha -ne $sha) {
            [void]$changed.Add([PSCustomObject]@{
                Path = $rel; Kind = '修改'; Full = $full; Size = $bytes.Length
            })
        }
    } else {
        [void]$changed.Add([PSCustomObject]@{
            Path = $rel; Kind = '新增'; Full = $full; Size = $bytes.Length
        })
    }
}

$deleted = New-Object System.Collections.ArrayList
foreach ($rel in @($remote.Blobs.Keys | Sort-Object)) {
    if (-not $localMap.ContainsKey($rel)) {
        if (Test-ExcludedPath $rel) { continue }
        [void]$deleted.Add($rel)
    }
}

# ---------- 2.5 线上 SHA 乐观锁：本地副本落后就中止 ----------
# 这两个文件由定时任务自动生成，本地每次部署也会重新生成，
# 所以「线上比本地新」不算落后，不触发中止。
$AutoGenFiles = @('_data/views.json', '_data/pv_state.json')

$baseline    = Read-Baseline
$lockBlocked = $false
$lockDel     = @()
$lockChg     = @()

if ($ResetBaseline) {
    Write-Baseline $remote.CommitSha
    Ok "已重新记录本地基准：$($remote.CommitSha.Substring(0,7))（线上最新提交）"
    Warn '仅在确认这份本地副本确实是最新的之后才该这么做。'
    $baseline = Read-Baseline
}

if ($null -eq $baseline) {
    Warn '本机还没有「基准提交」记录，无法证明这份副本是最新的。'
    if ($deleted.Count -gt 0) {
        $lockBlocked = $true
    } else {
        Say '  本次不会删除任何线上文件，先继续；部署成功后会自动记录基准。'
    }
} elseif ($baseline.sha -ne $remote.CommitSha) {
    $div = Get-Divergence -BaseSha $baseline.sha -HeadSha $remote.CommitSha
    if (-not $div.Ok) {
        $lockBlocked = $true
        Warn "本地基准 $($baseline.sha.Substring(0,7)) 已无法与线上比对：$($div.Reason)"
    } else {
        $divSet = @{}
        foreach ($f in $div.Files) { $divSet[$f] = $true }
        $lockDel = @($deleted | Where-Object {
            $divSet.ContainsKey($_) -and ($AutoGenFiles -notcontains $_)
        })
        $lockChg = @($changed | Where-Object {
            $divSet.ContainsKey($_.Path) -and ($AutoGenFiles -notcontains $_.Path)
        })
        if ($lockDel.Count -gt 0 -or $lockChg.Count -gt 0) {
            $lockBlocked = $true
        } else {
            Say "  线上有 $($div.Commits) 个新提交，但都只涉及自动生成的浏览量数据，基准已自动跟进。"
            Write-Baseline $remote.CommitSha
        }
    }
} else {
    Say "  本地基准 $($baseline.sha.Substring(0,7)) 与线上最新一致，可以安全部署。"
}

if ($lockBlocked) {
    if ($AllowStale) {
        Write-Host ''
        Warn '已按 -AllowStale 跳过乐观锁：本次会用本地副本覆盖线上内容。'
    } else {
        Write-Host ''
        Fail '已中止：本地副本落后于线上，继续部署会覆盖或删除线上内容。'
        Write-Host ''
        if ($lockChg.Count -gt 0) {
            Say '  线上改过、本次会被本地旧版本覆盖的文件：'
            foreach ($c in $lockChg) { Write-Host "      $($c.Path)" -ForegroundColor Yellow }
        }
        if ($lockDel.Count -gt 0) {
            Say '  线上新增或改过、本次会被删除的文件：'
            foreach ($d in $lockDel) { Write-Host "      $d" -ForegroundColor Red }
        }
        if ($lockChg.Count -eq 0 -and $lockDel.Count -eq 0) {
            Say '  本机缺少有效的「基准提交」记录，无法证明这份副本是最新的；'
            Say '  而本次又要删除线上文件，风险太高，先停下来。'
        }
        if ($null -ne $baseline) {
            Say "  本地基准：$($baseline.sha.Substring(0,7))（记录于 $($baseline.updated)）"
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
        Die '已中止，线上内容保持原样，没有被破坏。'
    }
}

$addedCount   = @($changed | Where-Object { $_.Kind -eq '新增' }).Count
$changedCount = @($changed | Where-Object { $_.Kind -eq '修改' }).Count

Write-Host ''
if ($changed.Count -eq 0 -and $deleted.Count -eq 0) {
    Ok '本地内容和线上完全一致，不需要部署。'
    Write-Host ''
    exit 0
}

Say "  待上传：新增 $addedCount 个，修改 $changedCount 个"
Say "  待删除：$($deleted.Count) 个"
Write-Host ''

foreach ($c in $changed) {
    $color = if ($c.Kind -eq '新增') { 'Green' } else { 'Yellow' }
    Write-Host ("    + {0,-9} {1}  ({2:N1} KB)" -f $c.Kind, $c.Path, ($c.Size / 1KB)) -ForegroundColor $color
}
foreach ($d in $deleted) {
    Write-Host ("    - 删除      $d") -ForegroundColor Red
}

if ($DryRun) {
    Write-Host ''
    Ok '预览结束：以上就是要改动的内容。'
    Say '  这次没有上传任何东西。去掉 -DryRun 就会真正部署。'
    Write-Host ''
    exit 0
}

# ---------- 3. 删除确认 ----------
function Confirm-Deletions {
    param(
        [object[]] $Deleted,
        [switch] $Yes
    )
    # 规则一：只要涉及任意 .md 文件（文章 / 页面）的删除，一律确认，-Yes 也绕不过。
    # 规则二：删除非 .md 文件达到 5 个以上时确认（-Yes 可跳过）。
    $mdDeletes = @($Deleted | Where-Object { $_ -like '*.md' })

    if ($mdDeletes.Count -gt 0) {
        Write-Host ''
        Warn "本次会从线上删除 $($mdDeletes.Count) 个 .md 文件（文章或页面）："
        foreach ($m in $mdDeletes) { Write-Host "      - $m" -ForegroundColor Red }
        Write-Host ''
        Say '  常见误判：这些文章其实是在 GitHub 网页上删掉的，而你手里这份'
        Say '  本地副本比线上旧，脚本就以为「线上有、本地没有」。'
        Say '  请先到 GitHub 确认这些文章确实是不需要的。'
        if ($Yes) { Warn '你用了 -Yes，但删除 .md 文件仍然必须确认。' }
        $ans = Read-Host '  确认无误请输入 DELETE 并回车继续，其它任意输入取消'
        if ($ans -ne 'DELETE') {
            Say '  如果这些文件在线上是最新的，请先同步线上副本，再运行：  .\deploy.ps1 -ResetBaseline'
            return $false
        }
        return $true
    }

    if ($Deleted.Count -ge 5 -and -not $Yes) {
        Write-Host ''
        Warn "这次会从线上删除 $($Deleted.Count) 个文件，数量偏多。"
        $ans = Read-Host '  确认要删除这些文件吗？输入 y 继续，其它任意键取消'
        if ($ans -notmatch '^[yY]') { return $false }
    }
    return $true
}

if (-not (Confirm-Deletions -Deleted $deleted -Yes:$Yes)) {
    Write-Host ''
    Say '已取消，没有做任何改动。'
    Write-Host ''
    exit 0
}

# ---------- 4. 组装并推送提交 ----------
$commitMsg = if ($Message) { $Message } else { "更新站点内容 - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }

Head '上传并提交'
$newCommitSha = $null
$attempts = 0
while ($attempts -lt 3 -and -not $newCommitSha) {
    $attempts++
    try {
        $treeEntries = New-Object System.Collections.ArrayList
        $n = 0
        foreach ($c in $changed) {
            $n++
            Write-Host ("    ({0}/{1}) 上传 {2}" -f $n, $changed.Count, $c.Path)
            $bytes = [IO.File]::ReadAllBytes($c.Full)
            $b64 = [Convert]::ToBase64String($bytes)
            $blob = Invoke-GitHub -Method POST -Path "/repos/$Repo/git/blobs" `
                -Body @{ content = $b64; encoding = 'base64' }
            $mode = if ($remote.Blobs.ContainsKey($c.Path)) { $remote.Blobs[$c.Path].Mode } else { '100644' }
            [void]$treeEntries.Add(@{ path = $c.Path; mode = $mode; type = 'blob'; sha = $blob.sha })
        }
        foreach ($d in $deleted) {
            [void]$treeEntries.Add(@{ path = $d; mode = '100644'; type = 'blob'; sha = $null })
        }

        $newTree = Invoke-GitHub -Method POST -Path "/repos/$Repo/git/trees" `
            -Body @{ base_tree = $remote.TreeSha; tree = @($treeEntries) }

        $commitBody = @{
            message = $commitMsg
            tree    = $newTree.sha
            parents = @($remote.CommitSha)
        }
        $newCommit = Invoke-GitHub -Method POST -Path "/repos/$Repo/git/commits" -Body $commitBody

        $null = Invoke-GitHub -Method PATCH -Path "/repos/$Repo/git/refs/heads/$Branch" `
            -Body @{ sha = $newCommit.sha; force = $false }

        $newCommitSha = $newCommit.sha
    } catch {
        $msg = "$_"
        if ($attempts -lt 3 -and ($msg -match 'HTTP 422' -or $msg -match 'HTTP 409' -or $msg -match 'fast forward')) {
            Warn '仓库刚才被更新过（可能是定时的浏览量任务），正在自动重试…'
            Start-Sleep -Seconds 3
            $remote = Get-RemoteSnapshot
            continue
        }
        Write-Host ''
        Fail "上传失败：$msg"
        if ($msg -match 'workflow') {
            Warn '看起来是令牌缺少 workflow 权限，无法更新 .github/workflows 下的文件。'
            Warn '请到 https://github.com/settings/tokens 重新勾选 workflow 权限后，运行：  .\deploy.ps1 -SetToken'
        }
        Die '部署中断，线上内容保持原样，没有被破坏。'
    }
}

Ok "提交成功：$($newCommitSha.Substring(0,7))  说明：$commitMsg"

# 记录本次提交为新的本地基准（下次部署时用它判断本地副本是否落后）
try {
    Write-Baseline $newCommitSha
    Say "  已记录本地基准：$($newCommitSha.Substring(0,7))"
} catch {
    Warn "记录本地基准失败，下次部署会提示基准缺失：$_"
}

# ---------- 5. 等待构建 ----------
if ($SkipWatch) {
    Head '等待 GitHub 构建与发布'
    Warn '按你的要求跳过（-SkipWatch）'
    Say  "  稍后到这里看结果：$ActionsUrl"
} else {
    Wait-Deploy -Sha $newCommitSha
    Test-LiveSite
}

Write-Host ''
Write-Host '------------------------------------------------------------' -ForegroundColor DarkGray
Ok '部署流程结束'
Say "  网站首页：$SiteUrl"
Say "  构建记录：$ActionsUrl"
Say '  小提示：页面有缓存，看到旧内容时按 Ctrl+F5 强制刷新即可。'
Write-Host ''
