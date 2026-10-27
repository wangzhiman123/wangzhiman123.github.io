#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
gen_tag_report.py —— 根据「分类标签表格」生成一份可读的整理报告

数据来源只有一处：tools\文章分类标签表.csv（也就是你用 Excel 改的那份表）。
所以正确顺序是：改表 → 跑 import_tags_table.py 回写文章 → 再跑本脚本出报告，
三者永远一致。本脚本只读表格，不会改动任何文章。

输出：tools\文章分类标签整理报告.md
（该目录在 _config.yml 的 exclude 里，不会被发布到网站）

用法：python scripts/gen_tag_report.py
"""

import re
from collections import Counter
from pathlib import Path

from import_tags_table import DEFAULT_TABLE, POSTS_DIR, load_rows, parse_tags

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "tools"
OUT_MD = OUT_DIR / "文章分类标签整理报告.md"

RE_TITLE = re.compile(r"^title\s*:\s*(.+?)\s*$", re.M)


def real_title(filename: str, fallback: str) -> str:
    """以文章里的 title 为准，表格里的只作后备。"""
    p = POSTS_DIR / filename
    if not p.exists():
        return fallback
    m = RE_TITLE.search(p.read_text(encoding="utf-8", errors="replace")[:3000])
    return m.group(1).strip().strip('"').strip("'") if m else fallback


def main():
    if not DEFAULT_TABLE.exists():
        raise SystemExit("找不到表格，请先运行：python scripts/export_tags_table.py")

    rows = load_rows(DEFAULT_TABLE)
    items = []
    for r in rows:
        fname = r.get("文件名", "")
        if not fname:
            continue
        items.append({
            "文件": fname,
            "标题": real_title(fname, r.get("文章标题", fname)),
            "一级": r.get("一级分类", "") or "(空)",
            "二级": r.get("二级分类", "") or "(空)",
            "标签": parse_tags(r.get("标签", "")),
            "日期": r.get("发布日期", ""),
        })

    lv1 = Counter(i["一级"] for i in items)
    lv2 = Counter((i["一级"], i["二级"]) for i in items)
    tagc = Counter(t for i in items for t in i["标签"])
    order = ["工作", "生活", "学习"]

    md = []
    md.append("# 文章分类与标签整理报告\n")
    md.append("> 覆盖文章：{} 篇 ｜ 一级分类 {} 个 ｜ 二级分类 {} 个 ｜ 标签 {} 个\n".format(
        len(items), len(lv1), len(lv2), len(tagc)))
    md.append("> 本报告由 `tools/文章分类标签表.csv` 生成。要改分类标签，请改那份表，"
              "再运行 `python scripts/import_tags_table.py`。\n")

    md.append("## 一、分类总览\n")
    md.append("| 一级分类 | 篇数 | 二级分类（篇数） |")
    md.append("| --- | --- | --- |")
    for c1 in order + [k for k in lv1 if k not in order]:
        if c1 not in lv1:
            continue
        subs = ["{}（{}）".format(c2, n) for (a, c2), n in
                sorted(lv2.items(), key=lambda kv: (-kv[1], kv[0])) if a == c1]
        md.append("| **{}** | {} | {} |".format(c1, lv1[c1], "、".join(subs)))
    md.append("")

    md.append("## 二、标签使用频次\n")
    md.append("| 标签 | 篇数 |")
    md.append("| --- | --- |")
    for t, n in tagc.most_common():
        md.append("| {} | {} |".format(t, n))
    md.append("")

    md.append("## 三、逐篇明细\n")
    for c1 in order + [k for k in lv1 if k not in order]:
        if c1 not in lv1:
            continue
        md.append("### {}（{} 篇）\n".format(c1, lv1[c1]))
        subs = [kv for kv in lv2.items() if kv[0][0] == c1]
        for (a, c2), _ in sorted(subs, key=lambda kv: (-kv[1], kv[0])):
            md.append("**{}**（{} 篇）\n".format(c2, lv2[(a, c2)]))
            md.append("| 标题 | 标签 | 文件 |")
            md.append("| --- | --- | --- |")
            for i in items:
                if i["一级"] == c1 and i["二级"] == c2:
                    md.append("| {} | {} | {} |".format(i["标题"], "、".join(i["标签"]), i["文件"]))
            md.append("")

    lonely = sorted([t for t, n in tagc.items() if n == 1])

    md.append("## 四、整理中发现的问题\n")
    md.append("| # | 问题 | 影响 | 状态 / 建议 |")
    md.append("| --- | --- | --- | --- |")
    md.append("| 1 | 全部文章的 front matter 分隔符原为 `\\---`（多一个反斜杠）| Jekyll 认不出 front matter，"
              "文章页会 404、分类页也抓不到 | ✅ 已修复（`scripts/fix_front_matter_delimiter.py`） |")
    md.append("| 2 | `post-007` 与 `post-035` 标题完全相同、正文相似度 97.6% | 同一篇文章重复收录 | "
              "⚠️ 待决定：建议保留日期较新的 `post-035` |")
    md.append("| 3 | 5 篇的 `date` 早于文件名日期（022/023/025/028/029）| 首页按 date 排序，这几篇会沉到后面 | "
              "⚠️ 待决定：想排前面就把 date 改成与文件名一致 |")
    md.append("")

    md.append("## 五、只有 1 篇文章使用的标签\n")
    if lonely:
        md.append("共 {} 个。这类标签在标签页里各占一个页面、内容很少；"
                  "若想让标签页更清爽，可以把它们合并到更常用的标签上。\n".format(len(lonely)))
        md.append("、".join(lonely))
    else:
        md.append("（没有）")
    md.append("")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT_MD.write_text("\n".join(md), encoding="utf-8")

    print("已生成报告：{}".format(OUT_MD))
    print("一级分类：" + "，".join("{} {} 篇".format(k, v) for k, v in lv1.most_common()))
    print("二级分类 {} 个，标签 {} 个（其中仅用 1 次的 {} 个）".format(
        len(lv2), len(tagc), len(lonely)))


if __name__ == "__main__":
    main()
