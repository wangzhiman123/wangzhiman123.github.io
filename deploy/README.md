# deploy/ —— 阿里云 ECS 自主部署工具

这一套脚本把网站从「GitHub Pages 托管」搬到「你自己的阿里云 ECS」上，
并替代原来依赖 GitHub Actions 的三件事（构建、发布、浏览量定时刷新）。

> 完整零基础图文步骤见仓库外的《阿里云迁移-零基础操作指南.md》。

## 文件一览

| 文件 | 在哪运行 | 作用 |
|---|---|---|
| `config.env.example` | 服务器 | 服务器端配置模板（域名、目录、邮箱） |
| `config.local.ps1.example` | 本机 | 本机一键上传的配置模板（服务器 IP、密钥） |
| `01-server-init.sh` | 服务器（root） | **只需跑一次**：装 Nginx/Ruby/Python、建目录、写 Nginx 配置 |
| `02-first-deploy.sh` | 服务器（root） | **首次部署**：拉源码 + 首次构建发布 |
| `publish.sh` | 服务器 | **核心**：构建 → 自检 → 原子切换 → 清理旧版本 |
| `update-from-git.sh` | 服务器 | `git pull` 后再发布（= `publish.sh --from-git`） |
| `views-refresh.sh` | 服务器 | 抓浏览量 → 重建发布（替代 update-views.yml） |
| `03-https.sh` | 服务器（root） | 申请 Let's Encrypt 证书 + 自动续期 |
| `04-install-views-cron.sh` | 服务器（root） | 安装浏览量定时任务（可 `--remove` 卸载） |
| `doctor.sh` | 服务器 | **一键体检**：检查整站是否正常，给出修复建议 |
| `deploy-aliyun.ps1` / `.bat` | 本机 | **双击一键**：打包源码上传 + 远程构建发布 |

## 最短使用路径

### 第一次（服务器上，root）
```bash
apt-get update -y && apt-get install -y git
git clone https://github.com/wangzhiman123/wangzhiman123.github.io.git /opt/site/src
cd /opt/site/src/deploy
cp config.env.example config.env && vi config.env     # 改 DOMAIN / LE_EMAIL
bash 01-server-init.sh
bash 02-first-deploy.sh
bash 03-https.sh
bash 04-install-views-cron.sh
bash doctor.sh
```

### 日常更新（两种任选）
- **本机双击** `deploy-aliyun.bat`（需先 `cp config.local.ps1.example config.local.ps1` 并填 IP）
- **服务器上** `bash /opt/site/src/deploy/update-from-git.sh`

## 常用命令

```bash
# 发布 / 更新
bash publish.sh                 # 用当前源码构建发布
bash publish.sh --from-git      # 先 git pull 再发布
bash views-refresh.sh           # 立刻刷新一次浏览量

# 回滚（秒级）
ls -1dt /var/www/releases/*            # 看有哪些版本
ln -sfn /var/www/releases/<版本> /var/www/2019527.xyz

# 体检
bash doctor.sh

# 卸载浏览量定时任务
bash 04-install-views-cron.sh --remove
```

## 运行前检查清单

- [ ] 阿里云**安全组**已放行 `22 / 80 / 443`
- [ ] 域名已完成**备案接入**（否则 80/443 会被拦）
- [ ] `config.env` 里 `DOMAIN` / `LE_EMAIL` 已改成自己的
- [ ] 源码已放到 `SRC_DIR`（默认 `/opt/site/src`）
- [ ] 内存 ≥ 2GB（或加了 swap），否则 Ruby 构建可能 OOM

## 设计要点（为什么这么做）

- **原子发布**：每次构建到 `releases/<时间戳>/`，成功后才把软链指过去 →
  构建期间线上仍是旧版，用户看不到「传一半的网站」。
- **秒级回滚**：旧版本目录都留着，改一条软链即可回退，无需重新构建。
- **数据不打架**：本机上传时**排除** `_data/views.json`、`_data/pv_state.json`，
  避免覆盖服务器上由定时任务写入的实时浏览量。
- **不动 GitHub 也能跑**：所有脚本零 GitHub 依赖；仓库只用来放源码（可选）。
