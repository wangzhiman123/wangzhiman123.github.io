# 一键部署使用说明

> 这个脚本让你不用再走「下载 zip → 改文件 → 网页上传」那套流程。
> 以后改完博客内容，**双击 `deploy.bat`** 就自动发布上线。

---

## 一、第一次使用（只需做一次）

### 1. 生成一个 GitHub 访问令牌

脚本需要你的授权才能把文件推送到仓库。令牌只保存在你自己电脑上（加密存放），不会泄露给任何人。

1. 浏览器打开 <https://github.com/settings/tokens/new>
2. **Note** 随便填，例如 `blog-deploy`
3. **Expiration** 建议选 `No expiration`（永不过期），省得以后重复设置
4. **勾选权限**（这一步很关键，两个都要勾）：
   - ☑ `repo` —— 勾最上面那个总开关，下面会自动全选
   - ☑ `workflow` —— 也在列表里，单独勾上
5. 拉到最下面点 **Generate token**
6. 复制那串 `ghp_` 开头的字符（**离开页面后就再也看不到了，务必先复制**）

### 2. 运行一次脚本，把令牌填进去

双击 `deploy.bat`，窗口会提示你粘贴令牌：

- 在这个窗口里按 **鼠标右键** 或 **Ctrl+V** 粘贴
- 输入时屏幕上不显示任何字符，这是正常的
- 按回车确认

看到「令牌验证通过」就设置好了，以后**再也不用输入**。

---

## 二、日常使用

改完文章 / 图片 / 配置后，**双击 `deploy.bat`**，等它跑完就行。

脚本会自动完成：

| 步骤 | 说明 |
|---|---|
| 1 | 刷新每篇文章的浏览量 |
| 2 | 和线上仓库逐一比对，列出「新增 / 修改 / 删除」 |
| 3 | 把改动组装成一次提交并推送到 GitHub |
| 4 | 等待 GitHub 自动构建，报告每个步骤的结果 |
| 5 | 检查 `2019527.xyz` 能不能正常打开 |

推送成功后，GitHub 会自动发布到：

- **2019527.xyz** —— 火山引擎服务器（主站）
- **GitHub Pages** —— 备用地址

> 页面有缓存，如果看到旧内容，按 `Ctrl + F5` 强制刷新一下。

---

## 三、常用参数（进阶）

不双击 `deploy.bat` 的话，也可以在本目录按住 `Shift` 右键 →「在此处打开 PowerShell 窗口」，然后：

```powershell
.\deploy.ps1                  # 正常部署
.\deploy.ps1 -DryRun          # 只预览会改哪些文件，不上传（不改动任何东西）
.\deploy.ps1 -Message "新增文章"   # 自定义提交说明
.\deploy.ps1 -SkipViews       # 跳过刷新浏览量
.\deploy.ps1 -SkipWatch       # 推送后不等待构建结果（马上就能关窗口）
.\deploy.ps1 -Status          # 查看最近几次部署的状态
.\deploy.ps1 -SetToken        # 换一个令牌（比如旧的过期了）
.\deploy.ps1 -Yes             # 删除较多「非文章」文件时不再询问（谨慎）
.\deploy.ps1 -ResetBaseline   # 重新记录本地基准（确认本地副本已是最新时才用）
.\deploy.ps1 -AllowStale      # 明知线上还有本地没有的更新，仍要覆盖（谨慎，可能丢文章）
```

`-DryRun` 特别有用：**改完东西先预览一遍**，确认文件列表没问题再正式部署。

### 两道安全闸（默认开启，不用做任何设置）

**① 线上 SHA 乐观锁 —— 防止旧副本覆盖线上**

脚本会在本机记一个「基准提交」（存在 `C:\Users\<你>\.wangzhiman-deploy\baseline-*.json`，不进仓库、不上传），
代表「这份本地副本是从哪个提交来的」。每次部署前先比对：

| 比对结果 | 脚本行为 |
| --- | --- |
| 本地基准 = 线上最新 | 正常部署 |
| 线上只有浏览量数据的自动更新 | 正常部署，基准自动跟进（定时任务每 6 小时改一次 `_data/views.json`，不算落后） |
| 线上有本地副本不知道的改动 | **直接中止**，列出会被覆盖 / 删除的文件，线上保持原样 |
| 本机没有基准记录，且本次要删除文件 | **中止**，先记录基准再重试 |

中止时按提示操作即可：重新下载线上最新副本 → `.\deploy.ps1 -ResetBaseline` → `.\deploy.ps1`。
只有在你确认本地才是最新的时候，才用 `.\deploy.ps1 -AllowStale` 强行覆盖。

**② 删除保护 —— 防止文章被悄悄删掉**

只要本次涉及**任意 `.md` 文件**（文章 / 页面）的删除，脚本一定会把文件名列出来，
要求你手动输入 `DELETE` 才继续，`-Yes` 也绕不过。
（非 `.md` 文件仍是删除 5 个以上才询问，可用 `-Yes` 跳过。）

> 为什么这么严：本次事故（post-047 被误删）就是因为手里是一份旧副本，
> 脚本误以为「线上有、本地没有 → 该删」。现在这两道闸能挡住同类问题。

---

## 四、常见问题

**Q：提示「令牌无法访问仓库」？**
权限没勾全。重新到 <https://github.com/settings/tokens> 生成一个，`repo` 和 `workflow` 两个都要勾，然后运行 `.\deploy.ps1 -SetToken` 重新填写。

**Q：提示「令牌已失效」？**
令牌被撤销或过期了。同样重新生成一个，再运行 `.\deploy.ps1 -SetToken`。

**Q：构建失败的红色提示？**
脚本会给你一个链接，点开能看到 GitHub 的详细日志。最常见的原因是文章里某段 Markdown / YAML 格式写错了。
若日志里出现 `HTML-Proofer ... 失败案例`、`不是HTTPS链接`，说明文章里有 `http://` 链接——
先双击 `tools/preflight.bat` 跑一遍自检定位（见第八节），再改成 `https://` 即可。

**Q：提示 `DEPLOY_TO_SERVER` 变量不是 true？**
说明推送到火山引擎服务器那一步被跳过了，`2019527.xyz` 不会更新（只有 GitHub Pages 更新）。去仓库 `Settings → Secrets and variables → Actions → Variables` 里把 `DEPLOY_TO_SERVER` 设为 `true`。

**Q：会把我线上仓库删掉东西吗？**
不会误删。脚本只删除「你本地确实已经删掉、但线上还存在」的文件，并且有三重保护：
① 涉及**任意 `.md` 文件**的删除，一定会列出来让你输入 `DELETE` 确认（`-Yes` 绕不过）；
② 非 `.md` 文件一次删除 5 个以上时也会先问你；
③ 若检测到线上有本地副本不知道的改动，会**直接中止**（见第三节「线上 SHA 乐观锁」）。
子模块目录 `assets/lib` 也已被明确排除，绝不会被当作垃圾清理。

**Q：提示「本机还没有基准提交记录」？**
说明这是升级脚本后的第一次部署（或记录文件被删了）。若本次不删除任何文件，
脚本会照常部署，并在成功后自动记录基准；若本次要删文件，则会先中止，
让你确认本地副本是最新的之后运行 `.\deploy.ps1 -ResetBaseline` 再部署。

**Q：提示「已中止：本地副本落后于线上」？**
见第三节「线上 SHA 乐观锁」。最常见的原因是你在 GitHub 网页端发过 / 改过文章，
而手里这份本地副本是那之前的。重新下载线上最新副本后再部署即可。

**Q：浏览量显示的数字是怎么来的？**
卡片和文章页共用同一份 `_data/views.json`，所以两处**永远一致**。这个文件由脚本在部署前刷新，GitHub 上还有一个每 6 小时跑一次的定时任务在更新它（北京时间 03:00 / 09:00 / 15:00 / 21:00）。注意它不是秒级实时的——这是静态博客的固有限制，你此刻的访问要等下一次刷新才会显示出来。

---

## 五、⚠️ 修改 `_includes/pageviews/goatcounter.html` 时的铁律

这个文件是文章页「浏览量」的显示逻辑，**改动时有一个必须遵守的规则**：

> **文件里的 JavaScript 绝对不能出现 `//` 开头的行为注释。**

**原因**：`_config.yml` 里开了 `compress_html`，网站在 GitHub 上正式构建时，
会把整份 HTML 的换行**全部压掉**（线上页面实测 0 个换行）。一旦代码里有 `//`，
这个注释就会把「本行之后」的所有代码一路注释到脚本结尾，整个脚本变成空函数。

**后果**：文章页的浏览量会**永远转圈**，而且不会报错——很难发现。

**正确写法**（2026-10 已修复过一次，就是踩了这个坑）：

```js
/* 用块注释，不要用 // */
var raw = 12;
try { ... } catch (e) { /* 忽略 */ }
```

三条规则：
1. 注释一律用 `/* */`，禁用 `//`
2. 每条语句以 `;` 结尾，不要依赖 JavaScript 的自动补分号
3. `if` / `for` 等分支一律加花括号 `{ }`

> 顺带一提：Chirpy 主题自带的内联脚本也是按这个规则写成单行的，原因就在这。
>
> 同样规则也适用于**其它含内联 JS 的自定义组件**，目前有：
> `_includes/pageviews/goatcounter.html`、`_includes/hot-posts.html`、
> `_includes/comments/artalk.html`（见第十节）。改这些文件时一律照上面的三条规则写。

## 六、文件说明

| 文件 | 作用 |
|---|---|
| `deploy.bat` | 双击启动器（日常就用它） |
| `deploy.ps1` | 真正的部署脚本 |
| `.github/workflows/pages-deploy.yml` | GitHub 上的构建发布流程 |
| `.github/workflows/update-views.yml` | 每 6 小时定时刷新浏览量 |
| `_data/views.json` | 各篇文章的浏览量（页面实际读取这个） |
| `_data/pv_state.json` | 浏览量查询账本，**不要手动改** |
| `scripts/update_views.py` | GitHub 定时任务用的抓取脚本 |
| `scripts/fix_post_links.py` | 把正文里的纯文本网址批量转成 Markdown 链接（见第七节） |
| `scripts/remove_post_images.py` | 批量去掉文章封面图引用（默认预览，加 `--apply` 才写入） |
| `_includes/hot-posts.html` | 侧栏「热门文章」板块组件（首页 + 文章页共用，见第九节） |
| `_layouts/home.html` | 首页布局：把 `hot-posts` 挂到 `panel_includes` |
| `_layouts/post.html` | 文章页布局：主题布局的覆盖版，仅 `panel_includes` 增加 `hot-posts`（见第九节） |
| `_includes/comments/artalk.html` | 文章页评论组件（Artalk，自托管；见第十节） |
| `_config.yml` | 站点配置：`comments.provider: artalk` 及各评论 provider 的参数（见第十节） |
| `tools/preflight.py` | 部署前一键自检：环境准备 → 构建 → 运行 → 结果校验（见第八节） |
| `tools/preflight.bat` | 双击即可跑自检（Windows） |
| `tools/preflight.sh` | 同上，macOS / Linux / CI 用 |

## 七、批量把正文里的纯文本网址变成可点击链接

有些文章里的网址是「裸」的（没写成链接），读者点不了。这个脚本可以一次性处理：

```bash
python scripts/fix_post_links.py                 # 预览：列出每一处改动，不写文件
python scripts/fix_post_links.py --apply         # 确认后执行（自动备份到仓库外的 backups/）
python scripts/fix_post_links.py --dirs _posts _tabs   # 连同 _tabs 页面一起处理
```

**它会改什么**：把 `网址：https://example.com` 变成 `网址：[https://example.com](https://example.com)`。
链接文字就是原网址本身，不做任何截断或改写。

**它绝不会碰什么**：图片外链、已有的 Markdown/HTML 链接、`<https://…>` 自动链接、
代码块与行内代码、以及 front matter 字段值。

**几个特意注意的点**：

- 网址后面紧跟中文时（如 `（宝塔面板官网：www.bt.cn）`），只会取到 `www.bt.cn`，
  不会把后面的中文或标点吞进链接。
- `https://www.xxx` 里的 `www.` 不会被当成第二个网址重复处理。
- 源码里带 Markdown 转义符的网址（如 `art\_5078\_331032.html`、`...?a=1\&b=2`）会**跳过并单独列出**。
  因为转义符会被渲染器还原，直接套链接可能导致打开后地址不对，需要人工确认后再处理。
- 重复运行**不会**产生重复嵌套（已转换的网址会被识别为「已有链接」而跳过）。
- 每次 `--apply` 前都会把 `_posts`/`_tabs` 完整备份到**仓库外**的 `backups/posts-links-<时间戳>/`，
  不会随部署上传；也可以直接用 Git 回滚。

运行结束后会生成一份报告（默认写到仓库外的 `link-fix-report.md`），
内容包括：被修改的文件、每处改动的前后对比、被跳过的内容及跳过原因，便于抽查复核。

> **⚠️ 重要：脚本给裸域名补的是 `https://`，不是 `http://`。**
> 原因见第八节——部署流水线用 html-proofer 检查，**任何 `http://` 链接都会让构建失败**。
> 脚本跑完会额外做一次「`http://` 链接自检」，若仍有残留会单独列出并给出处理建议。

---

## 八、部署前一键自检（`preflight`）

### 为什么需要它

GitHub 上的构建流程（`.github/workflows/pages-deploy.yml`）里有一个「Test site」步骤：

```
bundle exec htmlproofer _site --disable-external --ignore-urls "..."
```

`html-proofer` 默认开启 `--enforce-https`：**只要产物 HTML 里出现 `http://` 链接，
就会报「不是HTTPS链接」并让整个构建失败**，网站也就不会更新。

> 2026-10-09 就因为这个原因失败过一次：`HTML-Proofer 发现了 9 个失败案例!`
> 起因是链接化脚本给裸域名补了 `http://`。现在脚本已改为补 `https://`。

### 怎么用

**最简单**：双击 `tools/preflight.bat`（或在本目录执行 `python tools/preflight.py`）。

它会依次完成四步，全程自动、无需任何手动干预：

| 步骤 | 做什么 |
|---|---|
| 1 环境准备 | 检测 python / ruby / bundler / jekyll 是否就绪 |
| 2 构建 | 电脑上有 Ruby 就真正跑 `jekyll build`；没有就自动改用「源码等价模式」 |
| 3 运行 | 按与 html-proofer **完全相同**的规则扫描 `http://` 链接 |
| 4 结果校验 | 汇总，给出 `PASS` / `FAIL`，并给出修复建议 |

```bash
python tools/preflight.py                  # 自动（有 Ruby 就构建）
python tools/preflight.py --no-build       # 最快：只查链接规则
python tools/preflight.py --site _site     # 检查已构建好的产物目录
python tools/preflight.py --report out.md  # 顺便导出报告
```

> 说明：`html-proofer` 只能检查**构建产物**，所以本机没装 Ruby 时，
> 自检会退回到「源码等价模式」——它应用的是同一条规则（禁 `http://` 链接），
> 只是没有真正渲染 HTML，足以拦住上面那类报错。

### 遇到 `FAIL` 怎么办

1. 优先把链接改成 `https://`；
2. 若目标站点确实不支持 https（例如个别政府老站点），把它加进忽略名单——
   需要同时改两处，保持一致：
   - `.github/workflows/pages-deploy.yml` 里的 `--ignore-urls`
   - `tools/test.sh` 里的 `--ignore-urls`

当前忽略名单（除本机地址外）：
`http://lsrz.cs.mfa.gov.cn` —— 领事服务中心登录页，实测仅支持 http（https 返回 400）。

## 九、侧栏「热门文章」板块（首页 + 文章页共用）

右侧栏「热门标签」下方有一个「热门文章」板块，按浏览量从高到低展示前 5 篇。

### 涉及文件（共 3 个）

| 文件 | 作用 |
|---|---|
| `_includes/hot-posts.html` | **板块本体**：数据、排序、渲染、样式全在这一个文件里 |
| `_layouts/home.html` | 首页：`panel_includes: [hot-posts]` |
| `_layouts/post.html` | 文章页：主题布局的覆盖版，`panel_includes: [hot-posts, toc]` |

### 数据与样式（全部复用，无独立变体）

- **数据源**：`_data/views.json` —— 与首页文章卡片、文章页浏览量**同一份数据**，
  三处数值永远一致；构建时静态渲染，前端零请求、不会转圈。
- **排序**：按浏览量降序取前 5（Liquid 里用「常数 − 浏览量」作为排序键）。
- **样式**：沿用主题 `panel-heading` / `list-unstyled`，与「最近更新」「热门标签」一致。
- 文章页与首页**用的是同一个 include、同一套样式**，没有另建变体。

### 渲染位置由谁决定

主题 `_layouts/default.html` 会依次渲染「最近更新 → 热门标签」，再按
**当前页面所用布局**的 `panel_includes` 顺序渲染其余板块：

| 页面 | panel_includes | 侧栏最终顺序 |
|---|---|---|
| 首页 | `[hot-posts]` | 最近更新 → 热门标签 → **热门文章** |
| 文章页 | `[hot-posts, toc]` | 最近更新 → 热门标签 → **热门文章** → 目录 |

> 想让「热门文章」排在目录**之后**，把 `_layouts/post.html` 里的
> `panel_includes` 改成 `[toc, hot-posts]` 即可。

### ⚠️ 关于 `_layouts/post.html`（主题升级时请注意）

这个文件是**主题 `jekyll-theme-chirpy` v7.6.0 的 `_layouts/post.html` 副本**，
与主题原版**只有一处不同**：`panel_includes` 由 `[toc]` 改成了 `[hot-posts, toc]`。
其余内容（`layout: default`、`tail_includes`、`script_includes`、正文结构）与主题原版逐字一致。

之所以要整份复制，是因为 Jekyll 的布局覆盖只能「整文件替换」，无法只改其中一行；
而 `layout: default` 这一项必须保留——`default.html` 靠 `layout.layout == 'default'`
判断是否对正文做图片包裹 / 代码复制按钮 / 标题锚点等处理，改掉会让文章正文样式出错。

**升级主题后**：对照新版主题的 `_layouts/post.html` 重新同步本文件，
只保留 `panel_includes` 那一处差异即可。

---

## 十、评论系统：Artalk（自托管）

文章页底部的评论区由 **Artalk** 提供（`_config.yml` 里 `comments.provider: artalk`）。
它与之前的 giscus 最大的区别是：**评论界面和数据都跑在你自己的服务器上**，不依赖 GitHub。

### 涉及文件（共 2 个）

| 文件 | 作用 |
|---|---|
| `_includes/comments/artalk.html` | 评论组件本体：注入前端资源、初始化、跟随主题、懒加载 |
| `_config.yml` 的 `comments.artalk` | 服务端地址、站点名等参数 |

> 组件是「即插即用」的：主题自带的 `_includes/comment.html` 是一个通用切换器，
> 会按 `comments/{{ provider }}.html` 去加载对应文件。所以只要
> `provider: artalk` 且存在 `_includes/comments/artalk.html`，就自动生效，**无需改动任何主题文件**。

### 1. 服务端地址要求（`comments.artalk.server`）

| 要求 | 说明 |
|---|---|
| 公网可访问 | 评论由访客浏览器**直接**向该地址发请求，必须访客也能打开（不能是内网 / localhost） |
| 使用 `https` | 站点是 https，混用 `http` 会被浏览器拦截；同时 html-proofer 会判「不是 HTTPS 链接」使构建失败 |
| 结尾**不要**带 `/` | 组件内部会自动拼 `/dist/Artalk.js`，多一个 `/` 会变成 `//dist` |
| 跨域（CORS） | 若 Artalk 与站点不同域，需把站点域名加入 Artalk `conf.yml` 的 `trusted_domains` |

示例：`server: https://artalk.2019527.xyz`

> 想改用公共 CDN 提供前端资源（而不是由你自己的服务端提供），可另填
> `comments.artalk.assets_url: https://cdn.jsdelivr.net/npm/artalk@2/dist`。

### 2. 需填写的配置项（`_config.yml`）

```yaml
comments:
  provider: artalk        # 当前启用的评论系统
  artalk:
    server:               # 必填：Artalk 服务端地址，留空则评论区整体不显示
    site: 王志满律师       # 站点名，对应 Artalk 后台「站点管理」里的名称
    assets_url:           # 可选：前端资源地址，留空 = server + /dist
    locale: auto          # 界面语言：auto / zh-CN / en
```

**必填只有 `server` 一项。** 留空时评论区**不会渲染**（页面干净、无报错）；填上并部署后刷新即可看到评论框。

### 3. 本地与生产环境的差异

本地预览（`bundle exec jekyll s`，地址 `http://127.0.0.1:4000`）与线上（`https://2019527.xyz`）
用的是**同一份 `_config.yml`**，所以 `server` 的取值会互相影响：

| 环境 | 建议 | 原因 |
|---|---|---|
| 本地开发 | `server: http://localhost:23366`（本机已起 Artalk） | 本地不跑 html-proofer，`http` 无妨；`compress_html` 在 development 环境也不生效 |
| 生产 | `server: https://你的域名`（必须 https） | 会同时被访客浏览器与 html-proofer 校验 |

若要频繁在本地 / 生产之间切换又不想改文件，可用覆盖文件启动：

```bash
# 本地：以 _config.yml 为底，再用 _config.dev.yml 覆盖 artalk.server
bundle exec jekyll s --config _config.yml,_config.dev.yml
```

（`_config.dev.yml` 仅本地使用、无需上传，内容一行即可：`comments: { artalk: { server: http://localhost:23366 } }`。）

### 4. 启用后的验证步骤

1. 填好 `comments.artalk.server`（必要时再填 `site`）。
2. 本地双击 `tools/preflight.bat` 跑自检，确认 `PASS`。
3. 双击 `deploy.bat` 部署，等构建变绿。
4. 打开任意一篇文章，**滚到页面底部**，应出现评论框（懒加载，滚到附近才请求）。
5. 按 `F12` 开控制台 → Network，应能看到对 `server` 的请求（`Artalk.js`、`/api/`）返回 `200`。
6. 若已登录管理员账号，评论框右下角会出现**控制台入口**按钮。

> 排查：评论框一直显示「评论加载中…」→ 多半是 `server` 地址不对、服务端没启动或被 CORS 拦截。
> 先直接用浏览器打开 `你的 server 地址`，看能不能出现 Artalk 界面。

### 5. 回退方式（恢复成原来的 giscus）

原 giscus 的配置**原样保留**在 `_config.yml` 里，所以回退只需改一行：

1. 打开 `_config.yml`，把 `comments.provider: artalk` 改回 `comments.provider: giscus`；
2. 重新部署（`deploy.bat`）。

即可立刻恢复为 giscus 评论，**无需改代码、无需删文件**。

其它回退选项：

| 目标 | 操作 |
|---|---|
| 临时关闭所有评论 | 把 `provider:` 的值清空（保留键名，值留空） |
| 彻底移除 Artalk 组件 | **必须先**把 `provider` 改成 giscus（或清空），**再**删除 `_includes/comments/artalk.html` |
| 整体回滚本次改动 | 用 Git 回滚本次提交 |

> ⚠️ **顺序不能反**：主题切换器是按 `comments/{{ provider }}.html` 去加载文件的。
> 若 `provider` 还是 `artalk` 却把 `artalk.html` 删了，Jekyll 会因「找不到 include 文件」
> 直接**构建失败**。所以务必先改 `provider`，再删文件。
