# Twikoo 免费部署手册（Vercel + MongoDB Atlas）

> 适用：**完全不懂代码**，服务器 12 月到期不想再续费。
> 全程约 **40～50 分钟**，**不花一分钱**，只用两个免费账号（都可以用 GitHub 登录）。
> 只要复制粘贴 **1 段连接串 + 3 个文件**，其余全是点鼠标。

---

## 〇、先放心：你的网站不会跟着服务器一起没

我查了你的域名解析和响应头：

- `2019527.xyz` → 腾讯云 EdgeOne 加速 → 回源是 **GitHub Pages**（响应头 `Server: GitHub.com`）
- 也就是说：**网站本体一直免费托管在 GitHub 上，那台服务器只跑了一个 Artalk 评论**

**结论：12 月服务器到期 → 只有 Artalk 评论消失，网站、文章、图片、浏览量都照常。**
所以我们把评论也搬到免费方案上，之后**服务器可以彻底不续费**。

---

## 一、免费方案长什么样

| 角色 | 用什么 | 花钱吗 | 免费额度够用多久 |
|---|---|---|---|
| 网站 | GitHub Pages（你已有，EdgeOne 加速） | 免费 | 长期 |
| 评论后端 | **Vercel**（云函数） | 免费 | 每月 100 万次调用、100GB 流量 —— 博客级用量用不完 |
| 评论数据库 | **MongoDB Atlas M0** | 免费 | **500MB 永久免费**，一条评论约 1～3KB，够存十几万条 |

> 和原来"自托管"的区别：以前评论服务 24 小时跑在你的服务器上（要交机器钱）；
> 现在是"有人留言才启动一下"的云函数（平时零成本），数据库也托管在云端。
> 代价：数据不在你自己硬盘上了，在 MongoDB 的免费库里。

**为什么不干脆用原来那台服务器？** 因为 12 月到期。现在要是装上去，两个月后又要搬一次。

---

# 第 1 步：申请 MongoDB 免费数据库（约 10 分钟）

### 1.1 注册

打开 <https://www.mongodb.com/cloud/atlas/register>

- 建议直接点「**Sign up with GitHub**」（用你现有 GitHub 账号，最省事）
- 或填邮箱 + 密码注册
- ⚠️ **不需要信用卡**，全程不会问你要钱

### 1.2 建一个免费集群

登录后按提示（可能让你填"组织名/项目名"，随便填，比如 `twikoo`），然后：

1. 点「**Create**」（或 + Create a cluster / Build a Database）
2. 部署类型选 **M0 / FREE / Shared**（三个词里出现哪个就选哪个，都是免费档）
3. 云服务商选 **AWS**
4. 区域（Region）选：
   - 首选 **N. Virginia (us-east-1)** —— Vercel 默认也在美东，两个机房离得近，存评论快
   - 列表里找不到或你不确定，就选 **Oregon (us-west-2)**（官方推荐，稳定）
5. 集群名随便（`Cluster0` 就行）→ 点「**Create Deployment**」

> ✅ 看到 "Your cluster is being created…" 就对了，等 1～3 分钟变成绿色。

### 1.3 建数据库用户（这是 Twikoo 登录数据库用的账号）

左侧菜单 **Security → Database Access** → 「**Add New Database User**」：

1. Authentication Method 选 **Password**
2. Username 填 `twikoo`
3. Password：点「**Auto Generate**」（自动生成，**不含特殊符号，后面填连接串不会出错**）
   → **把这串密码复制到记事本存好**
4. 下方「Database User Privileges」→「**Add Built In Role**」→ Select Role 选「**Atlas Admin**」
5. 点「**Add User**」

### 1.4 允许 Vercel 连进来（白名单）

左侧 **Security → Network Access** → 「**Add IP Address**」：

1. Access List Entry 填：`0.0.0.0/0`（意思是"允许任何 IP"，因为 Vercel 的出口 IP 不固定）
2. 备注可写 `vercel`
3. 点「**Confirm**」

> ⚠️ 这步不做的话，评论会一直报"数据库连接失败"。

### 1.5 拿到连接串（最关键的一串字符）

左侧 **Database**（或 Deployment）→ 你的集群右边点「**Connect**」→ 选「**Drivers**」→

会看到类似这样一行：

```
mongodb+srv://<username>:<password>@cluster0.ab1cd.mongodb.net/?retryWrites=true&w=majority
```

**你要做两件事：**

1. 把 `<username>` 换成 `twikoo`，`<password>` 换成刚才 Auto Generate 的那串密码
   （**尖括号 `< >` 也要删掉**，只留文字）
2. 建议在 `mongodb.net/` 后面加上库名 `twikoo`，将来好认：

改完应该是这样（示意）：

```
mongodb+srv://twikoo:你的密码@cluster0.ab1cd.mongodb.net/twikoo?retryWrites=true&w=majority
```

📌 **把这一整行复制到记事本里存好**，下一步要用。它等于你数据库的钥匙，别发到公开的地方。

---

# 第 2 步：把评论后端部署到 Vercel（约 10 分钟）

### 2.1 注册 Vercel

打开 <https://vercel.com/signup> → 点「**Continue with GitHub**」→ 授权（点 Authorize）。
免费版叫 **Hobby**，不用填卡。

### 2.2 一键部署 Twikoo

登录 Vercel 后，直接点这个官方链接：

<https://vercel.com/import/project?template=https://github.com/twikoojs/twikoo/tree/main/templates/vercel-min>

（如果链接点不动，就去 <https://twikoo.js.org/backend.html> 找到「Vercel 部署」那张卡片，点蓝色的 **Deploy** 按钮，效果一样）

接下来：

1. 第一次会让你**授权 GitHub** 并选择把项目建在哪个账号下 → 选你的 `wangzhiman123`
2. 仓库名/项目名填 `twikoo`（会影响默认域名，起个好认的）
3. 点「**Deploy**」→ 等 1～2 分钟，出现彩带 = 部署成功
4. 这时先别急着用，**还差两步配置**

### 2.3 填数据库连接串

项目页 → 顶部「**Settings**」→ 左侧「**Environment Variables**」：

| Key | Value |
|---|---|
| `MONGODB_URI` | 第 1.5 步存的那一整行连接串 |

⚠️ Key 一个字都不能错，是 `MONGODB_URI`（**不是** `MONGO_URL`，写错了一定连不上）。
Environment 保持默认（Production/Preview/Development 全选）→ 点「**Save**」。

### 2.4 关掉访问保护（不做这步评论区永远 401）

还在「Settings」里 → 左侧「**Deployment Protection**」→
把「**Vercel Authentication**」设为 **Disabled** → 点「**Save**」。

> 这个功能是给内部演示用的，开着的话外人都进不来，读者当然也留不了言。

### 2.5 重新部署一次，让配置生效

顶部「**Deployments**」→ 最新那条右边「**⋯**」→「**Redeploy**」→ 弹窗再点「**Redeploy**」。

### 2.6 验证后端活了

等 30 秒 → 点顶部「**Overview**」→ 在「**Domains**」下面点那个链接（形如 `https://twikoo-xxxx.vercel.app`）。

✅ 页面上显示「**Twikoo 云函数运行正常**」= 后端 + 数据库都通了。

❌ 显示 401 / 让你登录 → 回 2.4。
❌ 显示连接数据库失败 → 回 2.3 检查 `MONGODB_URI`（密码是否含特殊符号、白名单是否 `0.0.0.0/0`）。

---

# 第 3 步：绑自己的域名（强烈建议，别跳过）

默认的 `xxx.vercel.app` 在**国内经常打不开**（这是 Vercel 的已知问题）。
绑上 `twikoo.2019527.xyz` 之后，国内访问稳定性会好很多。

### 3.1 在 Vercel 里加域名

项目 →「**Settings**」→「**Domains**」→ 输入 `twikoo.2019527.xyz` →「**Add**」。

Vercel 会告诉你需要加一条 DNS 记录，通常是：

| 类型 | 名称/主机记录 | 值 |
|---|---|---|
| CNAME | `twikoo` | `cname.vercel-dns.com` |

（**以 Vercel 页面上显示为准**，它有时给的是别的一串。）

### 3.2 去域名后台加这条记录

你的域名解析在**阿里云**（云解析 DNS）：

1. 登录阿里云 →「域名」→ 找到 `2019527.xyz` →「**解析设置**」
2. 「**添加记录**」
3. 记录类型：`CNAME`
4. 主机记录：`twikoo`
5. 记录值：`cname.vercel-dns.com`
6. TTL：`10 分钟`
7. 确定

> ⚠️ 如果列表里已经有一条 `twikoo` 的旧记录（之前试过 A 记录之类），**先删掉再加**，一个主机记录只能有一条 CNAME。

### 3.3 等生效

回到 Vercel 的 Domains 页面，等状态从 "Invalid Configuration" 变成 **Valid Configuration**（一般 1～10 分钟，最长几小时）。
变绿后 Vercel 会**自动签好 HTTPS 证书**，不用你做任何事。

✅ 打开 `https://twikoo.2019527.xyz` 也能看到「Twikoo 云函数运行正常」= 完成。

---

# 第 4 步：让网站改用 Twikoo（改 4 个文件）

> 这一步才是让文章底部换成 Twikoo 的关键。**4 个文件必须一起改**。

### 4.1 新增前端组件（1 个新文件）

1. 打开 <https://github.com/wangzhiman123/wangzhiman123.github.io>
2. 进 `_includes` → `comments`
3. 右上「**Add file**」→「**Create new file**」
4. 文件名：`twikoo.html`
5. 把附件 `twikoo.html` 的全部内容粘进去
6. 「**Commit changes...**」→「**Commit changes**」

### 4.2 替换配置文件（3 个已有文件）

附件里这三个文件**已经是改好的整份**，最稳的做法是整份替换：

| 文件 | 仓库里的路径 | 改了什么 |
|---|---|---|
| `_config.yml` | `_config.yml` | provider 改成 twikoo + 新增 twikoo 段（填你的 Vercel 地址） |
| `links.yml` | `_data/links.yml` | 友链页跳转锚点改成 `#twikoo-comments` |
| `friend-links-apply.html` | `_includes/friend-links-apply.html` | 加 1 个"评论区是否可用"的判断分支 |

**替换方法（每个文件都一样）：**

1. 在 GitHub 上打开该文件
2. 点右上角**铅笔图标**
3. 编辑框里 `Ctrl+A` 全选 → 粘贴附件里的整份内容 → 
4. 「**Commit changes...**」→「**Commit changes**」

> ⚠️ 提交前先确认 `_config.yml` 里这一行是你的域名：
> ```yaml
>     env_id: https://twikoo.2019527.xyz
> ```
> 必须 `https://` 开头、**结尾不带斜杠**、和你第 3 步绑的域名一字不差。

### 4.3（只想改几行的话）

- `_config.yml`：找 `provider:` 改成 `twikoo`；再找 `  twikoo:` 那段，确认 `env_id` 和 `assets_url`
- `_data/links.yml`：找 `comment_anchor:` 改成 `"#twikoo-comments"`
- `_includes/friend-links-apply.html`：找 `{%- elsif _prov == 'artalk'` 那两行，在下面加：
  ```liquid
  {%- elsif _prov == 'twikoo' and _cm.twikoo.env_id and _cm.twikoo.env_id != '' -%}
    {%- assign _cm_ok = true -%}
  ```
  （不加这个：友链页会把「前往评论区留言」自动换成"发邮件"）

### 4.4 等自动构建

打开 <https://github.com/wangzhiman123/wangzhiman123.github.io/actions>，
黄点在转 = 构建中（2～4 分钟），**绿勾** = 成功，**红叉** = 失败（基本都是 YAML 缩进被改坏了 → 用附件整份重做）。

---

# 第 5 步：验证 + 设管理员密码

1. 打开任意一篇文章，**滚到最底部**（评论区是懒加载的，不滚下去不会加载）
2. 应该看到「评论」区 + 昵称/邮箱/内容输入框
3. 自己发一条测试留言 → 能看到 = 全线打通
4. **马上点评论区右上角的小齿轮 ⚙️ → 设置管理员密码**（8 位以上，记进密码本）
5. 以后再点齿轮输入密码，就能进管理面板：删评论、看全部留言

顺手检查：
- 切深色模式，输入框不应刺眼发白
- 手机打开一篇文章滚到底，输入框字号不应被放大
- 友链页点「前往评论区留言」应能跳到评论区（不跳页顶）

---

# 第 6 步：12 月前的收尾（不然会留一堆死链）

### 6.1 把 Artalk 的老评论留个档（可选，但建议）

评论数据就是服务器上这一个文件：`/opt/artalk/data/artalk.db`

- 用云控制台的「文件管理」或 WinSCP 把它下载到电脑上存着
- 想看内容：这是 SQLite 数据库，用「DB Browser for SQLite」（免费小软件）打开就能看到所有评论文字
- **如果你想把这些老评论搬到 Twikoo**：数量不多的话，手工复制几段重发最快；数量多的话告诉我，我帮你把 `artalk.db` 转成 Twikoo 能导入的格式

### 6.2 到期后清理 DNS

服务器到期后，`artalk.2019527.xyz` 会变成打不开的死链（可能已被搜索引擎收录）。
到时候去阿里云解析里**把 `artalk` 那条记录删掉**即可，避免访客点到死链。

### 6.3 服务器到期就不用再续了

网站和评论都已经不在那台机器上了，**可以放心不续费**。

---

# 常见问题

### 1. Vercel 打开就让我登录 / 返回 401
「Settings → Deployment Protection → Vercel Authentication」没关。关掉后必须 **Redeploy** 一次才生效。

### 2. 页面显示"Twikoo 云函数运行正常"，但评论区提示连接失败
按顺序查：
1. `MONGODB_URI` 的 Key 拼错（必须是 `MONGODB_URI`）
2. 连接串里的 `<password>` 尖括号没删、或密码含 `@ : / ?` 等特殊符号（**用 Auto Generate 生成的密码就不会有这个问题**）
3. Atlas 的 Network Access 没加 `0.0.0.0/0`
4. 改完环境变量后**没有 Redeploy**

### 3. 评论区一片空白，或提示"评论暂时没能加载出来"
1. 先单独打开 `https://twikoo.2019527.xyz` 看后端是否正常
2. 再查 `_config.yml` 的 `env_id`（结尾斜杠、http/https 写错都会这样）
3. 浏览器按 `F12` → Console，把红色报错发我

### 4. 国内访问 `xxx.vercel.app` 很慢 / 打不开
正常现象，这就是必须做**第 3 步绑自定义域名**的原因。绑完就好了。

### 5. 免费额度会不会突然扣钱
- Atlas M0 **不绑卡**，不存在扣费
- Vercel Hobby **不绑卡**也不会扣费；如果哪天你绑了卡，去 Settings → Billing 设一个 Spending Limit = 0
- 另外：Vercel 免费版条款是"个人非商业项目"。你的博客属于个人分享，正常用没问题；以后要是做付费服务页，再考虑升级

### 6. 网站改了看不到变化
本站开了 PWA 缓存，按 **`Ctrl + F5`** 强制刷新；手机就把页面关掉重开。

### 7. 想换回 Artalk
`_config.yml` 的 `provider` 改回 `artalk`，提交即可。但要记住：**服务器 12 月到期后 Artalk 就没了**，这只是短期回退手段。

### 8. 以后 Twikoo 出 BUG / 想升级
Vercel 项目 → Deployments → 最新一条「⋯」→「**Redeploy**」。后端会自动拉到最新版，你什么都不用改。

---

# 附件说明

| 文件 | 干什么的 | 放哪 |
|---|---|---|
| `files/_includes/comments/twikoo.html` | 评论区前端组件（懒加载、多 CDN 兜底、深色适配） | **新增** |
| `files/_config.yml` | provider=twikoo + twikoo 配置段（已填 twikoo.2019527.xyz） | 覆盖 |
| `files/_data/links.yml` | 友链跳转锚点已改 `#twikoo-comments` | 覆盖 |
| `files/_includes/friend-links-apply.html` | 已加 twikoo 的"评论区可用"判断 | 覆盖 |

> 之前那套"自托管 Docker"的包（`twikoo改造包/`）留着当备份，
> 但**不建议现在装**——服务器 12 月到期，装了也是白装。
