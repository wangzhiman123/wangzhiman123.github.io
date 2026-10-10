#!/usr/bin/env bash
# ============================================================
#  04-install-views-cron.sh —— 安装「浏览量定时刷新」任务
#
#  替代原 GitHub Actions 的 update-views.yml：
#  按 config.env 里的 VIEWS_CRON 定时执行 views-refresh.sh。
#
#  用法（服务器上，root）：
#      bash 04-install-views-cron.sh          # 安装/更新
#      bash 04-install-views-cron.sh --remove # 卸载
# ============================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HERE/config.env"
[[ -f "$CONF" ]] || { echo "❌ 找不到 $CONF"; exit 1; }
# shellcheck disable=SC1090
source "$CONF"

ok()  { echo -e "\033[1;32m✅ $*\033[0m"; }

chmod +x "$HERE/views-refresh.sh" "$HERE/publish.sh" 2>/dev/null || true

CRON_LINE="${VIEWS_CRON} /bin/bash $HERE/views-refresh.sh >> /var/log/site-views.log 2>&1"
MARKER="# 王志满律师网-浏览量刷新"

if [[ "${1:-}" == "--remove" ]]; then
  crontab -l 2>/dev/null | grep -v "$MARKER" | grep -v "views-refresh.sh" | crontab - || true
  ok "已卸载浏览量定时任务"
  crontab -l 2>/dev/null | sed 's/^/   /' || true
  exit 0
fi

touch /var/log/site-views.log

# 先删旧的同类条目，再写入新条目（实现幂等）
TMP="$(mktemp)"
crontab -l 2>/dev/null | grep -v "$MARKER" | grep -v "views-refresh.sh" > "$TMP" || true
{
  echo "$MARKER"
  echo "$CRON_LINE"
} >> "$TMP"
crontab "$TMP"
rm -f "$TMP"

ok "已安装定时任务："
echo "   $CRON_LINE"
echo
echo "   当前 crontab："
crontab -l 2>/dev/null | sed 's/^/     /'
echo
echo "   日志文件： /var/log/site-views.log"
echo "   想立刻验证一次：  bash $HERE/views-refresh.sh"
