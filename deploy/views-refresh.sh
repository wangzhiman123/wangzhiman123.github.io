#!/usr/bin/env bash
# ============================================================
#  views-refresh.sh —— 抓取最新浏览量 → 重新构建发布
#
#  这个脚本替代原来 GitHub Actions 里的 update-views.yml：
#    · 运行 scripts/update_views.py，把真实浏览量写入 _data/views.json
#    · 若为 git 仓库，顺手提交这两个数据文件（避免下次 git pull 冲突）
#    · 然后重新构建发布，让页面上的浏览量更新
#
#  一般不用手动跑，由 04-install-views-cron.sh 装成定时任务。
# ============================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HERE/config.env"
[[ -f "$CONF" ]] || { echo "❌ 找不到 $CONF"; exit 1; }
# shellcheck disable=SC1090
source "$CONF"

cd "$SRC_DIR"

echo "[$(date '+%F %T')] 开始刷新浏览量"
SITE_URL="https://${DOMAIN}" python3 scripts/update_views.py

# git 仓库则提交数据变更，避免和后续 git pull 打架
if [[ -d .git ]]; then
  git add _data/views.json _data/pv_state.json 2>/dev/null || true
  git -c user.name="cron" -c user.email="cron@localhost" \
      commit -m "chore(data): update post views" >/dev/null 2>&1 \
    && echo "   数据已提交" || echo "   数据无变化，跳过提交"
fi

echo "   正在重新构建发布…"
bash "$HERE/publish.sh"
echo "[$(date '+%F %T')] 完成"
