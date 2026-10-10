#!/usr/bin/env bash
# ============================================================
#  02-first-deploy.sh —— 首次部署（从 GitHub 拉源码 + 首次构建发布）
#
#  用法（服务器上，root）：
#      cd /opt/site/src/deploy
#      bash 02-first-deploy.sh
#
#  如果源码已经在 $SRC_DIR（例如你用 deploy-aliyun.bat 上传过了），
#  这个脚本会自动跳过 clone，直接进入构建。
# ============================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HERE/config.env"
[[ -f "$CONF" ]] || { echo "❌ 找不到 $CONF，请先 cp config.env.example config.env 并填写"; exit 1; }
# shellcheck disable=SC1090
source "$CONF"

log() { echo -e "\n\033[1;34m▶ $*\033[0m"; }
ok()  { echo -e "\033[1;32m✅ $*\033[0m"; }

# ------------------------------------------------------------
log "1/3  准备源码到 $SRC_DIR"
if [[ -f "$SRC_DIR/Gemfile" ]]; then
  ok "源码已存在，跳过 clone"
elif [[ -d "$SRC_DIR/.git" ]]; then
  ok "已是 git 仓库，执行同步"
  git -C "$SRC_DIR" fetch --all --prune
  git -C "$SRC_DIR" reset --hard "origin/${REPO_BRANCH}"
else
  echo "   正在从 GitHub 克隆（首次约 10~60 秒）…"
  mkdir -p "$(dirname "$SRC_DIR")"
  # 目录可能已被创建为空目录，git clone 要求目标为空
  rmdir "$SRC_DIR" 2>/dev/null || true
  git clone --branch "$REPO_BRANCH" "$REPO_URL" "$SRC_DIR"
  ok "克隆完成"
fi

# ------------------------------------------------------------
log "2/3  检查关键文件"
for f in _config.yml Gemfile _posts; do
  if [[ -e "$SRC_DIR/$f" ]]; then
    echo "   ✅ $f"
  else
    echo "   ❌ 缺少 $f —— 源码可能不完整"
    exit 1
  fi
done

# ------------------------------------------------------------
log "3/3  执行发布（构建 → 自检 → 切换）"
bash "$HERE/publish.sh"

echo
ok "首次部署完成。下一步：bash $HERE/03-https.sh"
