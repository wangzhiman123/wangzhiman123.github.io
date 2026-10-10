#!/usr/bin/env bash
# ============================================================
#  publish.sh —— 核心发布脚本（构建 → 自检 → 原子切换 → 清理旧版本）
#
#  特点：
#    · 「原子切换」：先构建到新版本目录，构建成功才把软链指过去，
#      所以构建期间线上仍是旧版本，不会出现"传一半的网站"。
#    · 「秒级回滚」：旧版本目录都留着，改软链即可回退。
#
#  用法（服务器上）：
#      bash publish.sh
#      bash publish.sh --from-git     # 先 git pull 再发布
# ============================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HERE/config.env"
[[ -f "$CONF" ]] || { echo "❌ 找不到 $CONF，请先 cp config.env.example config.env 并填写"; exit 1; }
# shellcheck disable=SC1090
source "$CONF"

log() { echo -e "\n\033[1;34m▶ $*\033[0m"; }
ok()  { echo -e "\033[1;32m✅ $*\033[0m"; }

FROM_GIT=0
[[ "${1:-}" == "--from-git" ]] && FROM_GIT=1

STAMP="$(date +%Y%m%d-%H%M%S)"
REL="$RELEASES_DIR/$STAMP"

cd "$SRC_DIR"
ok "源码目录：$(pwd)"

# ------------------------------------------------------------
if [[ $FROM_GIT -eq 1 ]]; then
  log "0/5  从 Git 拉取最新代码"
  if [[ -d .git ]]; then
    git fetch --all --prune
    git reset --hard "origin/${REPO_BRANCH}"
    ok "已同步到 origin/${REPO_BRANCH}"
  else
    echo "⚠️  当前目录不是 git 仓库，跳过 git pull（将直接用现有文件构建）"
  fi
fi

# ------------------------------------------------------------
log "1/5  检查构建环境"
command -v bundle >/dev/null 2>&1 || { echo "❌ 没装 bundler，请先：gem install bundler"; exit 1; }
[[ -f Gemfile ]] || { echo "❌ $SRC_DIR 下没有 Gemfile，源码放错位置了？"; exit 1; }

# ------------------------------------------------------------
log "2/5  安装/校验依赖（首次会慢，之后很快）"
if [[ ! -f Gemfile.lock ]]; then
  echo "   未发现 Gemfile.lock，正在生成（用于锁定依赖版本）…"
  bundle install
  git add Gemfile.lock 2>/dev/null || true
  git commit -m "chore: 锁定依赖版本 (Gemfile.lock)" 2>/dev/null || true
else
  bundle install --quiet
fi

# ------------------------------------------------------------
log "3/5  构建站点 → $REL"
mkdir -p "$REL"
JEKYLL_ENV=production bundle exec jekyll build -d "$REL"

[[ -f "$REL/index.html" ]] || { echo "❌ 构建产物里没有 index.html，构建可能失败"; exit 1; }
ok "构建完成，文件数：$(find "$REL" -type f | wc -l)"

# ------------------------------------------------------------
log "4/5  构建后自检（html-proofer）"
bundle exec htmlproofer "$REL" \
  --disable-external \
  --ignore-urls "/^http:\/\/127.0.0.1/,/^http:\/\/0.0.0.0/,/^http:\/\/localhost/,/^http:\/\/lsrz\.cs\.mfa\.gov\.cn/"
ok "自检通过"

# ------------------------------------------------------------
log "5/5  原子切换发布目录"
if [[ -L "$WEB_ROOT" ]]; then
  ln -sfn "$REL" "$WEB_ROOT"
elif [[ -e "$WEB_ROOT" ]]; then
  # 首次：旧的可能是个真实目录，先改名备份再改成软链
  BK="${WEB_ROOT}.bak.$(date +%s)"
  mv "$WEB_ROOT" "$BK"
  ln -sfn "$REL" "$WEB_ROOT"
  echo "   原目录已备份为：$BK"
else
  ln -sfn "$REL" "$WEB_ROOT"
fi

ok "已发布，$WEB_ROOT → $REL"

# 清理旧版本，只保留最近 KEEP_RELEASES 个
if [[ -n "${KEEP_RELEASES:-}" ]] && [[ "$KEEP_RELEASES" =~ ^[0-9]+$ ]]; then
  ls -1dt "$RELEASES_DIR"/*/ 2>/dev/null | tail -n "+$((KEEP_RELEASES + 1))" | xargs -r rm -rf
  echo "   当前保留版本："
  ls -1dt "$RELEASES_DIR"/*/ 2>/dev/null | head -n "$KEEP_RELEASES" | sed 's/^/     /'
fi

echo
ok "发布完成 🎉  打开 https://${DOMAIN}/ 查看"
echo "   回滚命令： ln -sfn $RELEASES_DIR/<上一个版本> $WEB_ROOT"
