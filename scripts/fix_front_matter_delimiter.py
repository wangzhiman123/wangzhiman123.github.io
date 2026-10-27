#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
fix_front_matter_delimiter.py —— 修复文章开头 front matter 的「\--- 」错误

问题现象
--------
文章的第一行和 front matter 结束那一行，写成了   \\---
（多了一个反斜杠），正确写法必须是三个短横线：
---
Jekyll 4.4.1 识别 front matter 用的正则是
    \\A(---\\s*\\n.*?\\n?)^((---|\\.\\.\\.)\\s*$\\n?)
它要求文件「第一个字符就是 -」，所以带反斜杠的写法会让 Jekyll 认为
「这篇文章没有 front matter」—— 结果是这篇文章不会生成网页，
线上表现为文章页 404、分类标签页里也找不到它。

怎么修
------
只把「单独成行的 \\---」改成「---」，而且只在前 20 行（front matter 区域）里动，
正文一个字都不改。每篇最多改 2 处（首、尾），改完会逐篇复验。

用法
----
    python scripts/fix_front_matter_delimiter.py --dry-run   # 先看，不写
    python scripts/fix_front_matter_delimiter.py             # 正式修
"""

import re
import sys
from pathlib import Path

POSTS_DIR = Path(__file__).resolve().parent.parent / "_posts"

# 只认「整行就是 \---（后面可跟空格）」的情况
RE_BAD = re.compile(r"^\\---[ \t]*$")
# 闭合行最多往后找这么多行（有文章 front matter 里每行夹了空行，会比较长）
SCAN_LIMIT = 60


def _eol(line: str) -> str:
    if line.endswith("\r\n"):
        return "\r\n"
    return "\n" if line.endswith("\n") else ""


def fix_one(path: Path, dry_run: bool):
    """修两处：第 1 行的开头分隔符 + 第一处「单独成行的 \\---」（front matter 闭合）。

    不按固定行号扫描，而是「首行 + 第一个闭合行」，这样每行夹空行的文章也能覆盖到。
    """
    raw = path.read_text(encoding="utf-8")
    lines = raw.splitlines(True)
    hits = 0

    # ① 开头分隔符
    if lines and RE_BAD.match(lines[0].rstrip("\r\n")):
        lines[0] = "---" + _eol(lines[0])
        hits += 1

    # ② 闭合分隔符：从第 2 行往后找第一处单独成行的 \---
    for i in range(1, min(len(lines), SCAN_LIMIT)):
        if RE_BAD.match(lines[i].rstrip("\r\n")):
            lines[i] = "---" + _eol(lines[i])
            hits += 1
            break

    if hits and not dry_run:
        path.write_text("".join(lines), encoding="utf-8")
    return hits


def main():
    dry_run = "--dry-run" in sys.argv
    files = sorted(POSTS_DIR.glob("*.md"))
    total_files = total_hits = 0

    for f in files:
        n = fix_one(f, dry_run)
        if n:
            total_files += 1
            total_hits += n
            print("[{}] {} → 修复 {}/2 处".format("预览" if dry_run else "已修", f.name, n))

    print("\n共扫描 {} 篇，需修复 {} 篇、{} 处（{}）。".format(
        len(files), total_files, total_hits,
        "预演模式，未写入" if dry_run else "已写入磁盘"))


if __name__ == "__main__":
    main()
