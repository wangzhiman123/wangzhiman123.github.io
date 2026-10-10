#!/usr/bin/env bash
#
# preflight.sh —— 部署前一键自检（环境准备 → 构建 → 运行 → 结果校验）
# 与 tools/preflight.py 配套；本脚本只是薄封装，方便在 CI / macOS / Linux 上调用。
#
# 用法：
#   bash tools/preflight.sh                 # 自动：有 Ruby 就构建，否则源码等价检查
#   bash tools/preflight.sh --no-build      # 只查链接规则（最快）
#   bash tools/preflight.sh --report out.md # 额外输出报告
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
done

if [ -z "$PY" ]; then
  echo "[ERROR] 未找到 Python 3，请先安装。" >&2
  exit 2
fi

exec "$PY" tools/preflight.py "$@"
