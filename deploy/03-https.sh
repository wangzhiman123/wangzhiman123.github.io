#!/usr/bin/env bash
# ============================================================
#  03-https.sh —— 申请并配置 HTTPS 证书（Let's Encrypt，免费 + 自动续期）
#
#  前置条件：
#    · 域名的 A 记录已经指向这台服务器
#    · 80 端口能从公网访问（备案接入已通过）
#
#  用法（服务器上，root）：
#      bash 03-https.sh
# ============================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HERE/config.env"
[[ -f "$CONF" ]] || { echo "❌ 找不到 $CONF"; exit 1; }
# shellcheck disable=SC1090
source "$CONF"

log() { echo -e "\n\033[1;34m▶ $*\033[0m"; }
ok()  { echo -e "\033[1;32m✅ $*\033[0m"; }

[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "❌ 请用 root 运行： sudo bash $0"; exit 1; }

log "1/4  安装 certbot"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y certbot python3-certbot-nginx

# 组装域名参数（www 为空就不加）
DOMAIN_ARGS=(-d "$DOMAIN")
if [[ -n "${WWW_DOMAIN:-}" ]]; then
  DOMAIN_ARGS+=(-d "$WWW_DOMAIN")
fi

log "2/4  申请证书并自动配置 HTTPS（含 http→https 跳转）"
certbot --nginx \
  "${DOMAIN_ARGS[@]}" \
  --email "$LE_EMAIL" \
  --agree-tos --no-eff-email \
  --redirect \
  --non-interactive

log "3/4  确认自动续期定时器已开启"
systemctl enable --now certbot.timer >/dev/null 2>&1 || true
systemctl list-timers certbot.timer --no-pager 2>/dev/null | head -3 || true
ok "自动续期已就绪（每天检查两次，到期前自动续）"

log "4/4  演练续期流程"
certbot renew --dry-run

echo
ok "HTTPS 配置完成 🎉"
echo "   访问 https://${DOMAIN}/ 应能看到证书有效，且 http 会自动跳到 https。"
echo "   查看证书到期时间： certbot certificates"
