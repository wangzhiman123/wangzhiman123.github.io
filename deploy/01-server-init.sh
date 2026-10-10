#!/usr/bin/env bash
# ============================================================
#  01-server-init.sh —— 服务器初始化（全新 ECS 上只需跑一次）
#
#  做什么：设置时区 → 安装 Nginx/Git/Ruby/Python → 建目录 → 写 Nginx 配置
#
#  用法（在服务器上，用 root）：
#      cd /opt/site/src/deploy
#      cp config.env.example config.env
#      vi config.env                 # 改 DOMAIN / LE_EMAIL
#      bash 01-server-init.sh
# ============================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HERE/config.env"
if [[ ! -f "$CONF" ]]; then
  echo "❌ 找不到配置文件：$CONF"
  echo "   请先执行： cp config.env.example config.env && vi config.env"
  exit 1
fi
# shellcheck disable=SC1090
source "$CONF"

log() { echo -e "\n\033[1;34m▶ $*\033[0m"; }
ok()  { echo -e "\033[1;32m✅ $*\033[0m"; }
warn(){ echo -e "\033[1;33m⚠️  $*\033[0m"; }

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "❌ 请用 root 运行： sudo bash $0"
  exit 1
fi

if [[ -z "${DOMAIN:-}" || "$DOMAIN" == "2019527.xyz" && "${LE_EMAIL:-}" == *"请改"* ]]; then
  warn "请确认 config.env 里的 DOMAIN / LE_EMAIL 已改成你自己的。"
fi

# ------------------------------------------------------------
log "1/7  设置时区为 Asia/Shanghai（保证文章日期正确）"
timedatectl set-timezone Asia/Shanghai
date

# ------------------------------------------------------------
log "2/7  更新系统并安装依赖（这一步最慢，约 2~5 分钟）"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y \
  nginx git curl unzip vim ca-certificates rsync \
  build-essential ruby-full zlib1g-dev libffi-dev \
  python3 python3-pip fail2ban

ok "依赖安装完成"
echo "   Ruby 版本： $(ruby -v 2>/dev/null || echo '未安装')"
echo "   Nginx 版本： $(nginx -v 2>&1 || echo '未安装')"

# ------------------------------------------------------------
log "3/7  关闭 Nginx 默认站点，创建网站目录"
rm -f /etc/nginx/sites-enabled/default

mkdir -p "$RELEASES_DIR" "$(dirname "$WEB_ROOT")" "$SRC_DIR"

# 让 Nginx 用户与部署者都能读写发布目录（2775 = 组内共享 + 目录继承）
chown -R root:"$WEB_USER" "$(dirname "$WEB_ROOT")"
chmod 2775 "$(dirname "$WEB_ROOT")" "$RELEASES_DIR"

ok "目录已就绪："
echo "   发布目录根： $(dirname "$WEB_ROOT")"
echo "   版本目录：   $RELEASES_DIR"
echo "   源码目录：   $SRC_DIR"

# ------------------------------------------------------------
log "4/7  写入 Nginx 站点配置 /etc/nginx/sites-available/${DOMAIN}.conf"
NGINX_TMPL='/etc/nginx/sites-available/__DOMAIN__.conf'
cat > "$NGINX_TMPL" <<'NGINX_EOF'
server {
    listen 80;
    listen [::]:80;
    server_name __DOMAIN__ __WWW__;

    root __WEB_ROOT__;
    index index.html;

    # ① 静态资源长缓存（图片/CSS/JS 30 天）
    location ~* \.(?:css|js|jpg|jpeg|png|gif|webp|svg|ico|woff2?|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, max-age=2592000";
        access_log off;
    }

    # ② HTML 不缓存，保证「更新后刷新就能看到」
    location ~* \.html$ {
        add_header Cache-Control "no-cache, must-revalidate";
    }

    # ③ gzip 压缩（Chirpy 的 CSS/JS 较大，强烈建议开启）
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_types text/plain text/css text/xml application/javascript application/json application/xml image/svg+xml;

    # ④ 404 页面（Chirpy 会生成 404.html）
    error_page 404 /404.html;
    location = /404.html { internal; }

    # ⑤ 保护隐藏文件（.git 等），但放行 .well-known（证书校验要用）
    location ~ /\.(?!well-known) { deny all; }

    # ⑥ 目录式链接：/posts/xxx/ 自动找 index.html
    try_files $uri $uri/ =404;
}
NGINX_EOF

# 把占位符替换成真实值
sed -i "s|__DOMAIN__|${DOMAIN}|g; s|__WWW__|${WWW_DOMAIN}|g; s|__WEB_ROOT__|${WEB_ROOT}|g" "$NGINX_TMPL"

ln -sfn "$NGINX_TMPL" "/etc/nginx/sites-enabled/${DOMAIN}.conf"

# ------------------------------------------------------------
log "5/7  校验并启动 Nginx"
nginx -t
systemctl enable nginx
systemctl restart nginx
systemctl is-active --quiet nginx && ok "Nginx 已运行"

# ------------------------------------------------------------
log "6/7  开启 fail2ban（防 SSH 暴力破解）"
systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban >/dev/null 2>&1 || true
ok "fail2ban 已启动"

# ------------------------------------------------------------
log "7/7  完成"

cat <<EOF

============================================================
 ✅ 服务器初始化完成
============================================================

 下一步（按顺序）：

 1) 把源码放到 $SRC_DIR
      · 从 GitHub 拉取：
          git clone $REPO_URL $SRC_DIR
      · 或者从你电脑上用一键脚本上传：
          deploy-aliyun.bat  （Windows 双击）

 2) 安装 Ruby 依赖并首次构建发布：
          cd $SRC_DIR/deploy
          cp config.env.example config.env   # 若还没建
          vi config.env
          bash 02-first-deploy.sh

 3) 申请 HTTPS 证书：
          bash 03-https.sh

 4) 装浏览量定时刷新：
          bash 04-install-views-cron.sh

 5) 一键体检（随时可跑）：
          bash doctor.sh

 ⚠️ 别忘了在「阿里云控制台 → 安全组」放行 22 / 80 / 443 端口，
    并确认域名已完成「备案接入」，否则外网访问不到。

EOF
