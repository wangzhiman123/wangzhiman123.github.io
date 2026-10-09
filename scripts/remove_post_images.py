# -*- coding: utf-8 -*-
"""
批量移除所有文章 front matter 中的 image 字段
====================================================================

【作用】去掉每篇文章的「封面图」：
  - 首页文章卡片左侧的缩略图
  - 点进文章后顶部的大图
  - 社交分享时的预览图（会退回主题默认图）

  Chirpy 的卡片模板里有 `{% if post.image %}` 判断：
  没有 image 字段时，卡片正文自动占满整行（col-md-12），
  所以本脚本不需要改动任何模板文件，只删 front matter 里的一行。

【不会做的事】
  - 不删除任何图片文件（图片仍在 assets/ 或原图床上，只是不再引用）
  - 不动正文里的配图（![...](...) 全部保留）
  - 不改动 front matter 中的其它字段

【用法】
    python scripts/remove_post_images.py            # 预览（默认，不修改任何文件）
    python scripts/remove_post_images.py --apply    # 实际执行
"""

import argparse
import glob
import os
import re
import sys

POSTS_DIR = "_posts"

# 只在 front matter 内、且位于行首的 image 字段才删除
IMAGE_LINE = re.compile(r"^image\s*:")


def split_front_matter(text):
    """返回 (起始行, 结束行) 的索引，找不到返回 None"""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, lines
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return i, lines
    return None, lines


def process(files, apply_changes):
    hits = []
    skipped = []
    problems = []

    for path in files:
        with open(path, encoding="utf-8", newline="") as fh:
            text = fh.read()

        end, lines = split_front_matter(text)
        if end is None:
            problems.append((path, "front matter 结构异常，已跳过"))
            continue

        removed = []
        kept = []
        for i, ln in enumerate(lines):
            if 1 <= i < end and IMAGE_LINE.match(ln):
                removed.append(ln.split(":", 1)[1].strip())
                continue
            kept.append(ln)

        if not removed:
            skipped.append(path)
            continue

        new_text = "\n".join(kept)
        hits.append((path, removed))

        if apply_changes:
            with open(path, "w", encoding="utf-8", newline="") as fh:
                fh.write(new_text)

    return hits, skipped, problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="实际修改文件（默认只预览）")
    args = ap.parse_args()

    if not os.path.isdir(POSTS_DIR):
        print("未找到 %s 目录" % POSTS_DIR)
        return 1

    files = sorted(glob.glob(os.path.join(POSTS_DIR, "*.md")))
    if not files:
        print("%s 下没有文章" % POSTS_DIR)
        return 1

    mode = "执行模式：将修改文件" if args.apply else "预览模式：不会修改任何文件"
    print("=" * 60)
    print(" 移除文章封面图（front matter 的 image 字段）")
    print(" %s" % mode)
    print("=" * 60)
    print()

    hits, skipped, problems = process(files, args.apply)

    for path, removed in hits:
        name = os.path.basename(path)
        for v in removed:
            print("  %s" % name)
            print("      删掉 image -> %s" % v[:90])

    print()
    print("-" * 60)
    print("共 %d 篇文章" % len(files))
    print("  有 image 字段并已处理 : %d 篇" % len(hits))
    print("  本来就没有 image 字段 : %d 篇" % len(skipped))
    if skipped:
        print("      %s" % ", ".join(os.path.basename(p) for p in skipped))
    if problems:
        print("  异常未处理 : %d 篇" % len(problems))
        for p, why in problems:
            print("      %s -> %s" % (os.path.basename(p), why))
    print("-" * 60)

    if not args.apply and hits:
        print()
        print("以上为预览。加 --apply 参数才会真正写入。")
    elif args.apply and hits:
        print()
        print("已完成。图片文件本身没有删除，仍保留在仓库中。")

    return 0


if __name__ == "__main__":
    sys.exit(main())
