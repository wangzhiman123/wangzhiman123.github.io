# Jekyll 博客主题 Chirpy 的官方启动模板

![Gem Version](https://img.shields.io/gem/v/jekyll-theme-chirpy)

![GitHub license](https://img.shields.io/github/license/cotes2020/chirpy-starter.svg?color=blue)

一个简约、现成的模板，用于创建带有 [**Chirpy**](https://github.com/cotes2020/jekyll-theme-chirpy/) Jekyll 主题的博客。几分钟内就能启动，所有关键文件都已预先配置好。

## 前言

通过 [RubyGems.org](https://rubygems.org/gems/jekyll-theme-chirpy)安装Cherpy时,Jekyll只能读取部分主题文件和有限的选项。因此，用户无法享受Cherpy开箱即用的完整体验。 (`_data`, `_layouts`, `_includes`, `_sass`, `assets`)  
要解锁所有功能，必须在你的 Jekyll 网站上具备以下文件:

```shell
.
├── _config.yml
├── _plugins
├── _tabs
└── index.html
```

这个入门工具捆绑了最新**Chirpy** 发行的这些文件和[CD](https://en.wikipedia.org/wiki/Continuous_deployment) 工作流程，让你可以立即开始写作。

## 使用

点击查看使用说明（[官方演示教程](https://github.com/cotes2020/jekyll-theme-chirpy/wiki)）。

## 反馈

该仓库会自动更新主题仓库的新版本。如果你遇到任何问题或想为改进做出贡献，请访问 [theme repository](https://github.com/cotes2020/jekyll-theme-chirpy/) 提供反馈。

## 致谢

本项目采用 [MIT](https://github.com/cotes2020/chirpy-starter/blob/master/LICENSE) 许可协议发布。

# 2026.10.13 更新

本模板是在Jekyll主题 Chirpy7.6.0 版本上进行的修改。

（已移除）原「阅读量展示」与「热门文章模块」功能，已于 2026-10-27 整体删除，详见本文末尾的 2026-10-27 更新说明。

在页脚中增加icp备案号、公安备案号展示功能。如果希望把网站部署到国内服务器，可以使用该功能以便符合国内法规要求。

在页眉中增加文章数统计、字数统计、图片统计、视频数等功能。在页眉中，会展示文章统计、字数统计、图片统计等功能，以便用户直观知道网站内容的数据。

（已移除）原页眉「首页访问量」统计（不蒜子服务）已于 2026-10-27 一并删除。

改进页眉页脚文本居中功能。Jekyll 主题 Chirpy7.6.0 版本中，在手机端显示时，页眉页脚的文章统计、字数统计、图片统计、备案号等排版不会居中，影响美观，故改进成居中显示，且换行更智能。

（已移除）原「自动把静态网页同步到国内云服务器」功能，已于 2026-10-27 整体删除（含 `deploy/` 整个目录与工作流里的 `deploy-server` 任务），网站现在只发布到 GitHub Pages。

增加一键部署的功能。在前期部署时，受GitHub的限制，无法批量对文件进行删除等操作，也无法一次性上传超过100个文件，这个功能可以允许现在本地改文件，然后双击本地一个文件，即可自动化上传到GitHub完成自动发布。同时也不影响直接在GitHub仓库操作文件。

页脚中的个人图标链接修改为GitHub、知乎、哔哩哔哩、微信公众号等。因为网站主要面对是国内，所以作此修改。

基本进行了中文注释，方便国内用户阅读代码并进行个性化DIY。

字体、图标等资源直接从仓库中加载，不再依赖国外 CDN调用其他接口，减少图标、字体加载异常的现象。

增加了百度统计的代码，以便可以在百度统计中查看网站的浏览量、访问情况等数据。

# 2026-10-14 更新

在页脚中增加了网站运行天数的统计。

一键部署中增加了将github线上仓库代码同步到本机电脑的功能。

# 2026-10-15 更新

新增友情链接板块。

新增giscus评论区功能

# 2026-10-20 更新

新增首页缩略图和描述，读者在把网站分享到微信聊天页面或者朋友圈时，会展示网站标题、背景缩略图、描述等。

启用Artalk评论区功能，关闭giscus评论区功能。

# 2026-10-27 更新

改用twikoo评论区功能。

新增首页文章卡片页评论数显示

新增网站底部网站模版版本号显示

修改deploy.bat一键部署（2026-10-27 再次精简：浏览量移除后，-SkipViews / -WithViews 两个模式已取消，双击即直接部署）

新增一键整理分类和标签自动化脚本

**重大精简：移除「浏览量」与「热门文章」全部功能**

- 页面层面：首页卡片上的浏览量、文章页的「N 次浏览」、首页顶部「本站总访问量」、侧边栏「热门文章」面板，全部不再显示。
- 代码层面：删除 `_includes/hot-posts.html`、`_includes/busuanzi-site-pv.html`、`_includes/pageviews/`（两个组件）、`_includes/js-selector.html`（恢复主题原版即可）、`_includes/analytics/goatcounter.html`。
- 数据管线：删除 `_data/views.json`、`_data/pv_state.json`、`scripts/update_views.py`、`.github/workflows/update-views.yml`、`deploy/views-refresh.sh`、`deploy/04-install-views-cron.sh`。
- 配置层面：`_config.yml` 移除 `pageviews` / `viewcount` 两段；`analytics.goatcounter.id` 恢复为空。
- 部署脚本：`deploy.ps1` 移除 `Update-Views` 及 `-SkipViews` / `-SkipData`；`deploy.bat` 取消模式分支；`deploy-aliyun.ps1` 去掉浏览量数据排除项；`pages-deploy.yml` 去掉「为刷新浏览量而定时重建」的 cron。
- 影响：GitHub Actions 每天不再自动重建，服务器上也不再需要浏览量定时任务；站点不再对外显示、也不再抓取任何浏览数据。