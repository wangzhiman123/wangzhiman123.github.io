#!/usr/bin/env bash
# ============================================================
#  update-from-git.sh —— 从 Git 拉取最新代码并发布
#  （等价于 publish.sh --from-git，保留这个别名方便记忆）
#
#  用法：bash update-from-git.sh
# ============================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$HERE/publish.sh" --from-git
