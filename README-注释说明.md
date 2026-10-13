# 「注释版」文件夹说明

本文件夹是 `wangzhiman123.github.io-main` 的**中文注释版**。
所有文件都**只增加了中文注释**，代码逻辑、变量名、文件结构、缩进格式**完全没有改动**，
可以**直接使用**，运行效果和运行性能与原始版本**完全一致**。

---

## 一、这个网站是什么

这是一个基于 **Jekyll** 静态网站生成器 + **Chirpy 主题（v7.6.0）** 搭建的个人博客网站，
由 GitHub 免费托管并自动发布到 `https://2019527.xyz`。

**它能实现的效果：**

| 功能 | 说明 |
|---|---|
| 发文章 | 在 `_posts/` 里写 Markdown 文件，推送后自动变成网页文章 |
| 首页 | 展示文章卡片列表，置顶文章永远排最前 |
| 文章浏览量 | 用"不蒜子"免费统计，数字随访问增长（自动纠正误差） |
| 评论 | 自带 Artalk 评论系统（在服务器上自建） |
| 热门文章 | 文章页右侧显示浏览量最高的 5 篇 |
| 搜索 | 输入关键词实时筛选文章 |
| 分类 / 标签 / 归档 | 三种方式浏览历史文章 |
| 百度统计 | 后台看访客来源报表（不显示在前台） |
| 纯自托管 | 字体、图标等资源从自己网站加载，不再依赖国外 CDN，国内访问更快 |
| 一键部署 | 在 Windows 上双击 `deploy.bat`，自动把网站推送到 GitHub |

---

## 二、怎么看注释

每个文件开头都有一段 **"这个东西干什么用 / 运行效果 / 怎么改"** 的三段式说明。

正文里的注释分成两类：

- **普通中文注释** —— 解释"这行代码做了什么、为什么这么做"，用大白话写的。
- **【可DIY修改】** —— 标注出您可以安全自行修改的地方（文字、颜色、尺寸、数量、开关等），
  后面会说明改完会出现什么效果。

---

## 三、文件清单（共 38 个）

### 网站本体（构建网站必需）

| 文件 | 作用 |
|---|---|
| `_config.yml` | **网站总配置**（最重要的文件）：标题、域名、语言、统计、评论、外观等 |
| `index.html` | 首页入口，只有 4 行 |
| `_layouts/home.html` | 首页版式：文章卡片列表、置顶逻辑、站点统计条、浏览量显示 |
| `_layouts/post.html` | 文章详情页版式：标题、封面图、目录、正文、版权、分享 |
| `_includes/hot-posts.html` | 右侧"热门文章"面板 |
| `_includes/footer.html` | 页脚：版权、网站运行天数、建站技术说明、ICP 备案、公安备案 |
| `_includes/pageviews/goatcounter.html` | 浏览量填充脚本（本站的浏览量核心） |
| `_includes/analytics/baidu.html` | 百度统计代码 |
| `_includes/analytics/goatcounter.html` | **故意留空**的文件（用来屏蔽主题自带的 GoatCounter，详见文件内注释） |
| `_includes/comments/artalk.html` | Artalk 评论系统 |
| `Gemfile` | 网站依赖的"零件采购清单" |
| `_posts/` | 文章存放处（本次未加注释，内容即文章正文） |

### 网站数据

| 文件 | 作用 |
|---|---|
| `_data/authors.yml` | 作者名片（作者名、GitHub、个人主页） |
| `_data/contact.yml` | 侧边栏联系方式图标栏 |
| `_data/share.yml` | 文章底部分享按钮 |
| `_data/origin/basic.yml` | 自托管资源路径表（让网站不用国外 CDN） |
| `_data/views.json` | 各文章**真实浏览量**的账本（由脚本自动维护，不要手改） |
| `_data/pv_state.json` | 各文章**查询次数**的账本（用于纠正不蒜子的误差，不要手改） |

### 页面导航

| 文件 | 作用 |
|---|---|
| `_tabs/about.md` | "关于"页面（个人简介正文） |
| `_tabs/archives.md` | "归档"页面（按时间列出文章） |
| `_tabs/categories.md` | "分类"页面 |
| `_tabs/tags.md` | "标签"页面 |

### 自动化发布

| 文件 | 作用 |
|---|---|
| `.github/workflows/pages-deploy.yml` | GitHub 自动构建并发布的流水线 |
| `.github/workflows/update-views.yml` | 定时抓取浏览量并回写的流水线 |
| `_plugins/posts-lastmod-hook.rb` | 自动读取每篇文章的 git 修改次数，显示"更新于" |
| `scripts/update_views.py` | 抓取浏览量、计算真实值的 Python 脚本 |

### 一键部署（Windows 本机使用）

| 文件 | 作用 |
|---|---|
| `deploy.bat` | **双击这个就能一键发布**（最简单入口） |
| `deploy.ps1` | 一键部署的完整脚本（988 行，注释最详尽） |

### 服务器部署（迁移到自己的云服务器时使用）

| 文件 | 作用 |
|---|---|
| `deploy/01-server-init.sh` | 服务器初始化（装 Nginx、配网站目录、开防火墙） |
| `deploy/02-first-deploy.sh` | 首次部署（把代码拉下来、生成网站） |
| `deploy/publish.sh` | **核心发布脚本**：原子切换 + 秒级回滚 |
| `deploy/03-https.sh` | 申请并自动续期 HTTPS 证书 |
| `deploy/04-install-views-cron.sh` | 安装"定时刷新浏览量"任务 |
| `deploy/views-refresh.sh` | 定时刷新浏览量（被上面的任务调用） |
| `deploy/update-from-git.sh` | 从 git 拉取最新代码（短别名脚本） |
| `deploy/deploy-aliyun.ps1` | 在本机把代码打包上传到服务器 |
| `deploy/deploy-aliyun.bat` | 上面脚本的批处理入口 |
| `deploy/config.env.example` | 服务器部署配置模板（复制成 `config.env` 再改） |
| `deploy/config.local.ps1.example` | 本机上传配置模板（复制成 `config.local.ps1` 再改） |

### 本地开发工具

| 文件 | 作用 |
|---|---|
| `tools/run.sh` | 本地预览网站（`./tools/run.sh` 后浏览器访问提示的地址） |
| `tools/test.sh` | 构建 + 检查死链接、图片缺失等质量问题 |

---

## 四、关于两个 JSON 文件

`_data/views.json` 与 `_data/pv_state.json` 是 **JSON 格式，本身不支持写注释**
（写注释会导致程序无法读取）。这里用文字说明代替：

- **`views.json`** —— 记录**每篇文章的真实浏览量**，格式是 `"文章网址": 数字`。
  例如 `"/posts/post-001/": 25` 表示第一篇文章有 25 次浏览。
  **这个数字是脚本自动算出来写进去的，请不要手工修改。**

- **`pv_state.json`** —— 记录**累计查询次数**，作用是用来"修正误差"。
  因为免费统计服务（不蒜子）给出的数字包含脚本自己的查询，
  真实浏览量的计算公式是：**接口返回的数字 − 累计查询次数**。
  **同样请不要手工修改。**

这两个文件会被 GitHub Actions 或服务器上的定时任务自动更新，每次自动提交一次。

---

## 五、验证情况

为了确保"只加注释、不改代码"，已对全部文件做过一致性校验：

| 校验项 | 结果 |
|---|---|
| 9 个 shell 脚本语法（`bash -n`） | 全部通过 |
| `scripts/update_views.py` 编译 + 去注释后语法树比对 | 完全一致 |
| `_plugins/posts-lastmod-hook.rb` 去注释后比对 | 核心代码完全一致 |
| `_config.yml` 解析结果比对（31 个配置项） | 完全一致 |
| 4 个 `_data/*.yml` 解析结果比对 | 完全一致 |
| 9 个 Liquid/HTML 模板去注释后逐行比对 | 完全一致 |
| 2 个 GitHub Actions 工作流键集合比对 | 完全一致 |
| `deploy.ps1` 去注释后比对 | 核心代码完全一致 |
| 2 个 `.bat` 去注释后比对 | 核心代码完全一致 |
| `Gemfile`、4 个 `.md` 页面、2 个配置模板比对 | 完全一致 |

**结论：注释版与原版在功能上完全等价，可以直接使用。**
