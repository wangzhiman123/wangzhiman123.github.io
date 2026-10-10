# -*- coding: utf-8 -*-
"""
删除「豫章律师事务所」旧名片图片，并清理其全部引用。

背景
----
王志满律师现任职单位为「北京市康达（南昌）律师事务所」，「江西豫章律师事务所」
为原任职单位。仓库中共有 5 张像素级含旧所标识的名片图（字节扫描扫不到，需看图
才发现），全部位于 `assets/post/20261003/`：

    post-024-06   位于 2026-10-03-post-024.md 的「作者简介」区
    post-031-06   位于 2026-10-03-post-031.md 的「作者简介」区（带「图 王志满律师名片」图注）
    post-038-02   位于 2026-10-03-post-038.md 的「作者简介」区
    post-045-02   位于 2026-10-03-post-045.md 的「作者简介」区
    post-046-13   位于 2026-10-03-post-046.md 的「作者简介」区（带「图 王志满律师名片」图注）

本脚本做四件事：
  1) 从文章中去掉引用这些图片的 Markdown 行（其中含 alt 文案）；
  2) 同步删掉因图片被删而变成「孤立图注」的 `图 王志满律师名片` 行；
  3) 删除图片文件本身；
  4) 报告改动前后内容，并做「无残留引用」自检。

用法
----
    python scripts/remove_yuzhang_cards.py              # 预览（默认，不改任何文件）
    python scripts/remove_yuzhang_cards.py --apply      # 实际执行（先自动备份）
    python scripts/remove_yuzhang_cards.py --apply --backup-dir <路径>

说明
----
- 只处理「精确文件名」匹配，绝不误伤其它图片；
- 执行前自动把受影响文章备份到仓库外的 backups/ 目录（默认
  ../backups/posts-yuzhang-<时间戳>/），可随时回滚；
- 脚本可重复运行（幂等）：再次运行应报告 0 处改动。
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POSTS_DIR = os.path.join(REPO_ROOT, "_posts")
ASSETS_DIR = os.path.join(REPO_ROOT, "assets")

# 目标：文章 -> 该文章里要删除的旧名片图片文件名
TARGETS = [
    ("2026-10-03-post-024.md", "2026-10-03-post-024-06.webp"),
    ("2026-10-03-post-031.md", "2026-10-03-post-031-06.webp"),
    ("2026-10-03-post-038.md", "2026-10-03-post-038-02.webp"),
    ("2026-10-03-post-045.md", "2026-10-03-post-045-02.webp"),
    ("2026-10-03-post-046.md", "2026-10-03-post-046-13.webp"),
]

# 因图片删除而失效、需一并删除的孤立图注（去掉首尾空白后精确匹配）
ORPHAN_CAPTIONS = {"图 王志满律师名片"}

IMG_DIR = os.path.join("assets", "post", "20261003")


def read_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read().split("\n")


def write_lines(path, lines):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def collapse_blanks(lines, lo, hi):
    """把 [lo, hi) 区间内连续的空行压成一个，避免出现两个挨着的空行。"""
    out = []
    for idx, ln in enumerate(lines):
        if lo <= idx < hi and ln.strip() == "" and out and out[-1].strip() == "":
            continue
        out.append(ln)
    return out


def process_post(fname, img_name, apply):
    """返回 (changed, changes, removed_file)。changes 为 [(行号, 旧内容/说明)]。"""
    path = os.path.join(POSTS_DIR, fname)
    if not os.path.exists(path):
        return False, [(0, "!! 文章不存在：%s" % fname)], None

    lines = read_lines(path)
    img_idx = None
    for i, ln in enumerate(lines):
        if img_name in ln and "![" in ln:
            img_idx = i
            break
    if img_idx is None:
        return False, [], None  # 已经清理干净（幂等）

    changes = []
    remove = {img_idx}
    changes.append((img_idx + 1, "删除图片行：%s" % lines[img_idx]))

    # 其后（跨过空行）若紧跟孤立图注，一并删除，并吞掉中间的空白行
    j = img_idx + 1
    blanks = []
    while j < len(lines) and lines[j].strip() == "":
        blanks.append(j)
        j += 1
    if j < len(lines) and lines[j].strip() in ORPHAN_CAPTIONS:
        remove.add(j)
        changes.append((j + 1, "删除孤立图注：%s" % lines[j]))
        for b in blanks:
            remove.add(b)

    new_lines = [ln for k, ln in enumerate(lines) if k not in remove]
    new_lines = collapse_blanks(new_lines, max(0, img_idx - 2), min(len(new_lines), img_idx + 6))

    img_path = os.path.join(IMGDIR_ABS, os.path.basename(img_name))
    if apply:
        if new_lines != lines:
            write_lines(path, new_lines)
        if os.path.exists(img_path):
            os.remove(img_path)
    return (new_lines != lines), changes, (img_path if os.path.exists(img_path) or apply else None)


IMGDIR_ABS = os.path.join(REPO_ROOT, IMG_DIR)


def scan_residual():
    """全仓扫描是否仍有对目标图片的引用（排除 _site / assets/lib / .git）。"""
    pat = re.compile(r"(" + "|".join(os.path.basename(t[1]).rsplit(".", 1)[0] for t in TARGETS) + r")")
    hits = []
    skip_dirs = {".git", "_site", "lib"}
    for dirpath, dirnames, filenames in os.walk(REPO_ROOT):
        dirnames[:] = [d for d in dirnames if d not in skip_dirs]
        if os.path.join("assets", "lib") in dirpath.replace("/", os.sep):
            continue
        for fn in filenames:
            if not fn.endswith((".md", ".html", ".htm", ".yml", ".yaml", ".json", ".js", ".css", ".txt", ".xml")):
                continue
            p = os.path.join(dirpath, fn)
            try:
                txt = open(p, encoding="utf-8", errors="ignore").read()
            except Exception:
                continue
            for m in pat.finditer(txt):
                hits.append((os.path.relpath(p, REPO_ROOT), m.group(1)))
    return hits


def main():
    ap = argparse.ArgumentParser(description="删除豫章旧名片图片及其引用")
    ap.add_argument("--apply", action="store_true", help="实际写入（默认仅预览）")
    ap.add_argument("--backup-dir", default=None, help="备份目录（默认仓库外 ../backups/）")
    args = ap.parse_args()

    mode = "【实际执行】" if args.apply else "【预览模式 · 不修改任何文件】"
    print("=" * 74)
    print("删除豫章律师事务所旧名片图片并清理引用  %s" % mode)
    print("=" * 74)
    print()

    # ---------- 备份 ----------
    backup_dir = None
    if args.apply:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        backup_dir = args.backup_dir or os.path.join(os.path.dirname(REPO_ROOT), "backups", "posts-yuzhang-" + stamp)
        os.makedirs(os.path.join(backup_dir, "_posts"), exist_ok=True)
        for fname, _ in TARGETS:
            src = os.path.join(POSTS_DIR, fname)
            if os.path.exists(src):
                shutil.copy2(src, os.path.join(backup_dir, "_posts", fname))
        os.makedirs(os.path.join(backup_dir, IMG_DIR), exist_ok=True)
        for _, img in TARGETS:
            src = os.path.join(REPO_ROOT, IMG_DIR, os.path.basename(img))
            if os.path.exists(src):
                shutil.copy2(src, os.path.join(backup_dir, IMG_DIR, os.path.basename(img)))
        print("已备份到（仓库外，可随时回滚）：")
        print("   " + backup_dir)
        print()

    # ---------- 处理 ----------
    total_changes = 0
    deleted_files = 0
    for fname, img in TARGETS:
        changed, changes, img_path = process_post(fname, img, args.apply)
        print("-" * 74)
        if not changes and not changed:
            print("  %s  →  已清理完毕（无匹配引用）" % fname)
            continue
        print("  %s" % fname)
        for lineno, desc in changes:
            print("      行 %-4d %s" % (lineno, desc))
        total_changes += len(changes)
        # 图片文件删除统计
        absimg = os.path.join(REPO_ROOT, IMG_DIR, os.path.basename(img))
        if args.apply:
            if not os.path.exists(absimg):
                deleted_files += 1
                print("      已删除图片文件：%s/%s" % (IMG_DIR, os.path.basename(img)))
            else:
                print("      !! 图片文件仍存在：%s" % absimg)

    print()
    print("=" * 74)
    print("小结：处理文章 %d 篇，改动 %d 处%s"
          % (len(TARGETS), total_changes, ("，删除图片 %d 个" % deleted_files) if args.apply else "（预览）"))
    print("=" * 74)

    # ---------- 自检 ----------
    print()
    print("【自检】全仓残留引用扫描：")
    residual = scan_residual()
    if not residual:
        print("   ✅ 未发现任何残留引用")
    else:
        for p, k in residual:
            print("   ❌ %s  ->  %s" % (p, k))
        if not args.apply:
            print("   （预览模式：以上为待清理项）")

    print()
    print("【自检】图片文件是否仍存在：")
    leftover = [os.path.join(IMG_DIR, os.path.basename(img)) for _, img in TARGETS
                if os.path.exists(os.path.join(REPO_ROOT, IMG_DIR, os.path.basename(img)))]
    if not leftover:
        print("   ✅ 5 张旧名片文件均已不存在")
    else:
        for p in leftover:
            print("   ⏳ 仍存在：%s" % p)

    if not args.apply:
        print()
        print("如确认无误，请执行：python scripts/remove_yuzhang_cards.py --apply")

    return 0


if __name__ == "__main__":
    sys.exit(main())
