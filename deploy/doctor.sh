#!/usr/bin/env bash
# ============================================================
#  doctor.sh —— 一键体检：逐项检查部署是否正常，并指出怎么修
#
#  用法（服务器上）：
#      bash doctor.sh
#
#  退出码：0 = 全部通过；1 = 存在必须处理的问题
# ============================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HERE/config.env"

PASS=0; WARN=0; FAIL=0
pass(){ echo -e "  \033[1;32m✅ PASS\033[0m  $*"; PASS=$((PASS+1)); }
warn(){ echo -e "  \033[1;33m⚠️  WARN\033[0m  $*"; WARN=$((WARN+1)); }
fail(){ echo -e "  \033[1;31m❌ FAIL\033[0m  $*"; FAIL=$((FAIL+1)); }
sec(){ echo -e "\n\033[1;34m▶ $*\033[0m"; }

echo "============================================================"
echo " 站点部署体检报告   $(date '+%F %T')"
echo "============================================================"

# ---------- 0. 配置文件 ----------
sec "0. 配置文件"
if [[ -f "$CONF" ]]; then
  # shellcheck disable=SC1090
  source "$CONF"
  pass "找到 config.env（DOMAIN=$DOMAIN）"
else
  fail "找不到 $CONF —— 请先 cp config.env.example config.env 并填写"
  echo
  echo "体检中断：没有配置无法继续。"
  exit 1
fi

# ---------- 1. Nginx ----------
sec "1. Web 服务器（Nginx）"
if command -v nginx >/dev/null 2>&1; then
  pass "Nginx 已安装（$(nginx -v 2>&1)）"
else
  fail "Nginx 未安装 —— 请先跑 01-server-init.sh"
fi

if systemctl is-active --quiet nginx 2>/dev/null; then
  pass "Nginx 正在运行"
else
  fail "Nginx 没有运行 —— 执行 systemctl restart nginx，再看 journalctl -u nginx"
fi

if nginx -t >/tmp/nginx_t 2>&1; then
  pass "Nginx 配置语法正确"
else
  fail "Nginx 配置有语法错误："
  sed 's/^/        /' /tmp/nginx_t
fi

if [[ -f "/etc/nginx/sites-enabled/${DOMAIN}.conf" ]]; then
  pass "站点配置已启用（${DOMAIN}.conf）"
else
  fail "没找到 /etc/nginx/sites-enabled/${DOMAIN}.conf —— 请跑 01-server-init.sh"
fi

# ---------- 2. 发布目录 ----------
sec "2. 网站目录与发布版本"
if [[ -L "$WEB_ROOT" ]]; then
  TARGET="$(readlink -f "$WEB_ROOT")"
  if [[ -d "$TARGET" && -f "$TARGET/index.html" ]]; then
    pass "$WEB_ROOT → $TARGET（index.html 存在）"
  else
    fail "$WEB_ROOT 指向的目录无效或缺少 index.html —— 重新跑 publish.sh"
  fi
else
  fail "$WEB_ROOT 不是软链 —— 重新跑 publish.sh（它会自动处理）"
fi

if [[ -r "$WEB_ROOT/index.html" ]]; then
  pass "Nginx 用户可读取首页文件"
else
  fail "首页文件不可读 —— 检查权限：chmod 2775 $(dirname "$WEB_ROOT") && chown -R root:$WEB_USER $(dirname "$WEB_ROOT")"
fi

if [[ -d "$RELEASES_DIR" ]]; then
  N=$(ls -1d "$RELEASES_DIR"/*/ 2>/dev/null | wc -l)
  pass "版本目录存在，共 $N 个版本（可用于回滚）"
else
  fail "版本目录 $RELEASES_DIR 不存在"
fi

# ---------- 3. 源码与构建环境 ----------
sec "3. 源码与构建环境"
[[ -f "$SRC_DIR/_config.yml" ]] && pass "源码就绪（$SRC_DIR/_config.yml）" || fail "源码缺失：$SRC_DIR 下没有 _config.yml"
[[ -f "$SRC_DIR/Gemfile" ]]    && pass "Gemfile 存在" || fail "缺少 Gemfile"
if [[ -f "$SRC_DIR/Gemfile.lock" ]]; then
  pass "Gemfile.lock 存在（依赖版本已锁定）"
else
  warn "没有 Gemfile.lock —— 建议跑一次 publish.sh 自动生成，避免以后构建失败"
fi
command -v ruby   >/dev/null 2>&1 && pass "ruby $(ruby -v | awk '{print $2}')" || fail "未安装 ruby"
command -v bundle >/dev/null 2>&1 && pass "bundler 已安装" || fail "未安装 bundler（gem install bundler）"
command -v python3 >/dev/null 2>&1 && pass "python3 已安装" || fail "未安装 python3（浏览量脚本需要）"

# ---------- 4. 本站是否真的能打开 ----------
sec "4. 本机自测（绕过 DNS）"
CODE="$(curl -s -o /dev/null -w '%{http_code}' -m 10 -H "Host: ${DOMAIN}" "http://127.0.0.1/" 2>/dev/null || echo 000)"
if [[ "$CODE" == "200" ]]; then
  pass "本机访问 http://127.0.0.1/ (Host:${DOMAIN}) 返回 200"
else
  fail "本机访问返回 $CODE —— Nginx 可能没指对目录，或站点配置未生效"
fi

# ---------- 5. DNS 与公网 ----------
sec "5. 域名解析与公网"
PUB_IP="$(curl -s -m 5 http://100.100.100.200/latest/meta-data/eipv4 2>/dev/null || curl -s -m 8 https://ipinfo.io/ip 2>/dev/null || true)"
DNS_IP="$(python3 - <<PY 2>/dev/null || true
import socket
try: print(socket.gethostbyname("${DOMAIN}"))
except Exception: pass
PY
)"
echo "     服务器公网 IP： ${PUB_IP:-（未取到）}"
echo "     域名当前解析： ${DNS_IP:-（未取到）}"
if [[ -n "$PUB_IP" && -n "$DNS_IP" ]]; then
  if [[ "$PUB_IP" == "$DNS_IP" ]]; then
    pass "域名已正确指向本服务器"
  else
    warn "域名没有指向本服务器（现在指向 $DNS_IP）—— 迁移中属正常，切 DNS 后应一致；若刚切换请等 TTL 过期"
  fi
else
  warn "无法同时取到公网 IP 与解析结果，请手动核对"
fi

# 安全组端口（只能从外部判断，这里做基础连通性提示）
if [[ "$CODE" == "200" ]]; then
  pass "本机 80 端口可访问（安全组是否放行请从外网再验一次）"
fi

# ---------- 6. HTTPS ----------
sec "6. HTTPS 证书"
if [[ -d /etc/letsencrypt/live/$DOMAIN ]]; then
  ENDDATE="$(openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)"
  if [[ -n "$ENDDATE" ]]; then
    END_TS="$(date -d "$ENDDATE" +%s 2>/dev/null || echo 0)"
    NOW_TS="$(date +%s)"
    DAYS=$(( (END_TS - NOW_TS) / 86400 ))
    if [[ "$DAYS" -gt 20 ]]; then
      pass "证书有效，剩余 ${DAYS} 天（$ENDDATE）"
    elif [[ "$DAYS" -gt 0 ]]; then
      warn "证书仅剩 ${DAYS} 天 —— 检查 certbot renew 是否正常"
    else
      fail "证书已过期！立刻执行 certbot renew --force-renewal"
    fi
  fi
  systemctl is-active --quiet certbot.timer 2>/dev/null \
    && pass "自动续期定时器运行中" \
    || warn "certbot.timer 未运行 —— systemctl enable --now certbot.timer"
else
  warn "还没申请证书（跑 03-https.sh）；正式上线前必须配 HTTPS"
fi

# ---------- 7. 定时任务 ----------
sec "7. 浏览量定时刷新"
if crontab -l 2>/dev/null | grep -q "views-refresh.sh"; then
  pass "已安装浏览量刷新定时任务"
  crontab -l 2>/dev/null | grep "views-refresh.sh" | sed 's/^/        /'
else
  warn "未安装（跑 04-install-views-cron.sh）—— 不装的话浏览量不会自动更新"
fi

# ---------- 8. 资源 ----------
sec "8. 服务器资源"
MEM_MB="$(free -m | awk '/^Mem:/{print $2}')"
SWAP_MB="$(free -m | awk '/^Swap:/{print $2}')"
echo "     内存： ${MEM_MB} MB    交换分区： ${SWAP_MB} MB"
if [[ "${MEM_MB:-0}" -lt 1900 && "${SWAP_MB:-0}" -lt 512 ]]; then
  warn "内存不足 2GB 且没有 swap，Ruby 构建可能被系统杀掉（OOM）—— 建议加 1~2GB swap"
else
  pass "内存/交换分区够用"
fi
DISK="$(df -h / | awk 'NR==2{print $5}')"
echo "     根分区使用率： $DISK"

# ---------- 汇总 ----------
echo
echo "============================================================"
echo -e " 结果： \033[1;32m通过 $PASS\033[0m | \033[1;33m警告 $WARN\033[0m | \033[1;31m失败 $FAIL\033[0m"
echo "============================================================"
if [[ "$FAIL" -gt 0 ]]; then
  echo "  ❌ 存在必须处理的问题，请按上面的提示逐条修复。"
  exit 1
elif [[ "$WARN" -gt 0 ]]; then
  echo "  ⚠️  基本可用，但建议处理上面标 WARN 的项。"
  exit 0
else
  echo "  🎉 全部检查通过，部署状态良好。"
  exit 0
fi
