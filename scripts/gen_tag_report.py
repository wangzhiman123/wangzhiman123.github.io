#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_tag_report.py —— 依据 batch_retag_posts.py 的对照表，生成两份核对材料

输出（都放在 tools/ 目录，该目录已在 _config.yml 的 exclude 里，不会被发布上线）
----
    tools/文章分类标签对照表.csv   ← Excel 可直接打开（UTF-8 带 BOM，不乱码）
    tools/文章分类标签整理报告.md  ← 分类清单 + 统计 + 待办提醒

用法：python scripts/gen_tag_report.py
"""

import re
from collections import Counter
from pathlib import Path

from batch_retag_posts import MAP, POSTS_DIR

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "tools"

RE_TITLE = re.compile(r"^title\s*:\s*(.+?)\s*$", re.M)
RE_DATE = re.compile(r"^date\s*:\s*(.+?)\s*$", re.M)


def read_meta(path: Path):
    """从 front matter 里读标题和日期（去引号、去行尾多余空格）。"""
    raw = path.read_text(encoding="utf-8")
    head = raw[:3000]
    title = RE_TITLE.search(head)
    date = RE_DATE.search(head)
    t = title.group(1).strip().strip('"').strip("'") if title else path.stem
    d = date.group(1).strip() if date else ""
    return t, d


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    rows = []
    for name in sorted(MAP, key=lambda n: (MAP[n][0][0], MAP[n][0][1], n)):
        cats, tags = MAP[name]
        title, date = read_meta(POSTS_DIR / name)
        rows.append({
            "文件": name,
            "标题": title,
            "一级分类": cats[0],
            "二级分类": cats[1],
            "标签": "、".join(tags),
            "发布日期": date,
        })

    # ---------------- CSV ----------------
    csv_path = OUT_DIR / "文章分类标签对照表.csv"
    header = ["序号", "一级分类", "二级分类", "标题", "标签", "发布日期", "文件名"]
    lines = [",".join(header)]
    for i, r in enumerate(rows, 1):
        cells = [str(i), r["一级分类"], r["二级分类"], r["标题"],
                 r["标签"], r["发布日期"], r["文件"]]
        safe = ['"' + c.replace('"', '""') + '"' for c in cells]
        lines.append(",".join(safe))
    csv_path.write_text("\ufeff" + "\r\n".join(lines) + "\r\n", encoding="utf-8")

    # ---------------- 统计 ----------------
    lv1 = Counter(r["一级分类"] for r in rows)
    lv2 = Counter((r["一级分类"], r["二级分类"]) for r in rows)
    tagc = Counter(t for r in rows for t in r["标签"].split("、"))

    # ---------------- Markdown 报告 ----------------
    md = []
    md.append("# 文章分类与标签整理报告\n")
    md.append("> 生成时间：自动生成 ｜ 覆盖文章：{} 篇 ｜ 分类体系：3 个一级、{} 个二级\n"
              .format(len(rows), len(lv2)))
    md.append("## 一、分类总览\n")
    md.append("| 一级分类 | 篇数 | 二级分类（篇数） |")
    md.append("| --- | --- | --- |")
    for c1 in ["工作", "生活", "学习"]:
        subs = ["{}（{}）".format(c2, n) for (a, c2), n in lv2.items() if a == c1]
        subs.sort(key=lambda s: -int(s.split("（")[1].rstrip("）")))
        md.append("| **{}** | {} | {} |".format(c1, lv1.get(c1, 0), "、".join(subs)))
    md.append("")

    md.append("## 二、标签使用频次\n")
    md.append("| 标签 | 篇数 |")
    md.append("| --- | --- |")
    for t, n in tagc.most_common():
        md.append("| {} | {} |".format(t, n))
    md.append("")

    md.append("## 三、逐篇明细\n")
    for c1 in ["工作", "生活", "学习"]:
        md.append("### {}（{} 篇）\n".format(c1, lv1.get(c1, 0)))
        for (a, c2), _ in sorted([kv for kv in lv2.items() if kv[0][0] == c1],
                                 key=lambda kv: -kv[1]):
            md.append("**{}**（{} 篇）\n".format(c2, lv2[(a, c2)]))
            md.append("| 标题 | 标签 | 文件 |")
            md.append("| --- | --- | --- |")
            for r in rows:
                if r["一级分类"] == c1 and r["二级分类"] == c2:
                    md.append("| {} | {} | {} |".format(r["标题"], r["标签"], r["文件"]))
            md.append("")

    md.append("## 四、整理中发现的问题（建议处理）\n")
    md.append("以下是批量整理时顺带查出来的，**不属于分类标签的范畴**，但会影响网站效果，列出来供你决定：\n")
    md.append("| # | 问题 | 影响 | 状态 / 建议 |")
    md.append("| --- | --- | --- | --- |")
    md.append("| 1 | 全部 51 篇的 front matter 分隔符原为 `\\---`（多一个反斜杠）| Jekyll 认不出 front matter，"
              "推送后这 51 篇文章页会 404、分类标签页也抓不到 | ✅ 已修复（`scripts/fix_front_matter_delimiter.py`） |")
    md.append("| 2 | `post-007` 与 `post-035` 标题完全相同、正文相似度 97.6% | 同一篇文章被重复收录，"
              "列表里出现两次、浏览量被摊薄 | ⚠️ 待你决定：建议保留日期较新的 `post-035`，删除 `post-007` |")
    md.append("| 3 | 5 篇的 `date` 早于文件名日期（022→2025-08-06、023→2025-04-01、025→2022-03-21、"
              "028→2022-04-09、029→2022-04-14）| 首页按 date 排序，这几篇会沉到列表后面 | "
              "⚠️ 待你决定：想排在前面就把 `date` 改成与文件名一致；想保留真实写作时间则不用动 |")
    md.append("")
    md.append("")

    md_path = OUT_DIR / "文章分类标签整理报告.md"
    md_path.write_text("\n".join(md), encoding="utf-8")

    print("已生成：")
    print("  " + str(csv_path))
    print("  " + str(md_path))
    print("\n一级分类分布：" + "，".join("{}{}篇".format(k, v) for k, v in lv1.most_common()))


if __name__ == "__main__":
    main()
