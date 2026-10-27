#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
import_tags_table.py —— 按表格内容批量回写每篇文章的分类、标签

工作流
------
    ① python scripts/export_tags_table.py     # 导出表格
    ② 用 Excel / WPS 打开 tools\文章分类标签表.csv 改分类和标签，保存
    ③ python scripts/import_tags_table.py     # 按表格回写文章

用法
----
    python scripts/import_tags_table.py                # 正式回写
    python scripts/import_tags_table.py --dry-run      # 只预览，不改文件
    python scripts/import_tags_table.py 表格路径.csv    # 指定别的表格文件

安全性
------
1. 只改每篇文章的 categories、tags 两行，正文和其他字段一字不动。
2. 回写前会自动把 _posts 备份到 _backup/autosave-时间戳/，出问题可整体还原。
3. 内容没变的文章不会被重写（保持文件时间戳不变，避免「更新于」乱跳）。
4. 表格里每一行按「文件名」找文章；找不到、分类填错的行会跳过并单独列出，不影响其他行。
5. 可以重复运行，结果幂等。

表格格式要求
------------
必需列：一级分类 / 二级分类 / 标签 / 文件名
    一级分类  随便填。将来想加「税务」「读书」这种新大类，直接在表里写就行，
              不用改代码，会自动生成对应的分类页，导入时只会提示你一句
    二级分类  随便填，出现新值同样只提示、不拦截
    标签      多个用顿号「、」隔开；中文逗号、英文逗号、分号也都认；留空=不要标签
    文件名    必须和 _posts 里的文件名完全一致，否则跳过
    唯一限制：分类名和标签名里不能出现  ,  :  #  [  ]  这几个符号，
              因为它们会破坏 categories: [a, b] 这种写法（中文的 ， ： 也不行）
其他列（序号、文章标题、发布日期）随便看、随便改，脚本不读。
"""

import csv
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POSTS_DIR = ROOT / "_posts"
DEFAULT_TABLE = ROOT / "tools" / "文章分类标签表.csv"

# 一级分类「已知值」。注意：这只是用来提示「你新增了一个分类」，
# 不做任何拦截。将来想加「税务」「读书」这类新大类，直接在表格里填就行，不用改代码。
LEVEL1_KNOWN = ["工作", "生活", "学习"]

# 二级分类的已知值，同样只用于「这是新分类」的提示，不拦截
LEVEL2_KNOWN = {
    "工作": {"诉讼实务", "案例复盘", "非诉实务", "文书模板", "办案工具", "法律科普", "执业成长"},
    "生活": {"日常随笔", "爱妻日常", "办事指南"},
    "学习": {"建站笔记", "工具教程", "思考随记"},
}

REQUIRED_COLS = ["一级分类", "二级分类", "标签", "文件名"]

# 标签分隔符：顿号、中英文逗号、中英文分号
RE_TAG_SPLIT = re.compile(r"[、,，;；]")

# 分类名里不能出现的字符：会破坏 categories: [a, b] 这种 YAML 写法。
# （英文逗号会被当成两个分类分开，方括号会截断列表，# 和 : 会被当成注释/映射）
RE_BAD_NAME = re.compile(r"[\[\],，:：#]")

RE_CATEGORIES = re.compile(r"^categories\s*:")
RE_TAGS = re.compile(r"^tags\s*:")

# 匹配整行「categories: [...]」或「tags: [...]」，并单独捕获行尾注释（原样保留）
RE_FIELD_LINE = re.compile(r"^(categories|tags)\s*:\s*\[[^\]]*\](\s*#.*)?$")


# ============================================================================
# 一、读表格（自动识别编码和分隔符）
# ============================================================================

def read_table_text(path: Path) -> str:
    """Excel 另存 CSV 常常会变成 GBK，这里逐个编码试，直到能解出来。"""
    raw = path.read_bytes()
    for enc in ("utf-8-sig", "utf-8", "gb18030", "gbk"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    raise SystemExit("表格编码无法识别（试过 utf-8 / gbk）。请在 Excel 里另存为「CSV UTF-8」再试。")


def sniff_delimiter(text: str) -> str:
    """看第一行里哪种分隔符最多，就用哪种。"""
    first_line = text.splitlines()[0] if text.splitlines() else ""
    counts = {",": first_line.count(","), ";": first_line.count(";"), "\t": first_line.count("\t")}
    best = max(counts, key=counts.get)
    return best if counts[best] > 0 else ","


def load_rows(path: Path):
    """读表格，返回 (行字典列表, 错误列表)。列名会自动去掉首尾空格。"""
    text = read_table_text(path)
    delim = sniff_delimiter(text)
    reader = csv.DictReader(text.splitlines(), delimiter=delim)

    if not reader.fieldnames:
        raise SystemExit("表格是空的，或第一行没有列名。")

    # 列名容错：去掉 BOM、首尾空格、全角空格
    cleaned = {}
    for name in reader.fieldnames:
        key = (name or "").replace("\ufeff", "").strip().strip("\u3000")
        cleaned[name] = key

    missing = [c for c in REQUIRED_COLS if c not in cleaned.values()]
    if missing:
        raise SystemExit(
            "表格缺少必需的列：{}\n实际读到的列名：{}\n"
            "（请直接用 export_tags_table.py 导出的表格来改，别自己另建表头）".format(
                "、".join(missing), "、".join(cleaned.values())))

    rows = []
    for raw_row in reader:
        row = {cleaned[k]: (v or "").strip() for k, v in raw_row.items() if k in cleaned}
        # 整行都空就跳过（Excel 末尾常有空行）
        if not any(row.get(c, "") for c in REQUIRED_COLS):
            continue
        rows.append(row)
    return rows


def parse_tags(cell: str):
    """把「一审、原告方」拆成 ["一审", "原告方"]，顺手去重去空。"""
    out = []
    for part in RE_TAG_SPLIT.split(cell or ""):
        t = part.strip()
        if t and t not in out:
            out.append(t)
    return out


def bad_char(val: str):
    """返回名字里第一个会破坏 YAML 的符号，没有则返回 None。"""
    m = RE_BAD_NAME.search(val or "")
    return m.group(0) if m else None


# ============================================================================
# 二、读写文章 front matter
# ============================================================================

def read_current(path: Path):
    """读文章当前的 categories / tags，用于判断是否真的需要改。"""
    text = path.read_text(encoding="utf-8", errors="replace")

    def pick(key):
        m = re.search(r"^" + key + r"\s*:\s*\[(.*?)\]", text, re.M)
        if not m:
            return None
        inner = m.group(1).strip()
        return [x.strip() for x in inner.split(",") if x.strip()] if inner else []

    return pick("categories"), pick("tags")


def detect_eol(text: str) -> str:
    return "\r\n" if "\r\n" in text[:2000] else "\n"


def build_line(key: str, values, comment: str, eol: str) -> str:
    body = "{}: [{}]".format(key, ", ".join(values))
    return body + "  # " + comment + eol


def apply_to_post(path: Path, cats, tags, dry_run: bool) -> str:
    """把新的分类标签写进文章。返回 'changed' / 'same' / 'error:原因'。"""
    text = path.read_text(encoding="utf-8")
    eol = detect_eol(text)
    lines = text.splitlines(True)

    cat_line = build_line("categories", cats, "一级分类, 二级分类（固定两级，从左到右）", eol)
    tag_line = build_line("tags", tags, "标签，英文逗号分隔", eol)

    # 找到 front matter 的区间：第 0 行是 --- ，往后再找一个 --- 结束
    if not lines or lines[0].strip() != "---":
        return "error:开头不是 ---（front matter 缺失）"
    end = None
    for i in range(1, min(len(lines), 200)):
        if lines[i].strip() in ("---", "..."):
            end = i
            break
    if end is None:
        return "error:找不到 front matter 的结束 ---"

    hit_c = hit_t = False
    for i in range(1, end):
        line = lines[i]
        body = line.rstrip("\r\n")
        m = RE_FIELD_LINE.match(body)
        if not m:
            continue
        key, tail = m.group(1), (m.group(2) or "")
        values = cats if key == "categories" else tags
        line_eol = "\r\n" if line.endswith("\r\n") else ("\n" if line.endswith("\n") else eol)
        # 只换方括号里的值，行尾原有的注释一字不动
        lines[i] = "{}: [{}]{}".format(key, ", ".join(values), tail) + line_eol
        if key == "categories":
            hit_c = True
        else:
            hit_t = True

    # 原文里没有这两行的，补在结束分隔符之前
    insert_at = end
    if not hit_c:
        lines.insert(insert_at, cat_line)
        insert_at += 1
        end += 1
    if not hit_t:
        lines.insert(insert_at, tag_line)

    new_text = "".join(lines)
    if new_text == text:
        return "same"
    if not dry_run:
        path.write_text(new_text, encoding="utf-8")
    return "changed"


# ============================================================================
# 三、主流程
# ============================================================================

def main():
    args = [a for a in sys.argv[1:]]
    dry_run = "--dry-run" in args
    if "--allow-new-level1" in args:
        # 旧参数，现在默认就允许任意一级分类，保留只为不让你旧命令报错
        print("提示：--allow-new-level1 已不需要，现在默认允许任意一级分类。")
    positional = [a for a in args if not a.startswith("--")]
    table = Path(positional[0]) if positional else DEFAULT_TABLE

    if not table.exists():
        raise SystemExit(
            "找不到表格：{}\n请先运行：python scripts/export_tags_table.py".format(table))

    rows = load_rows(table)
    print("读取表格：{} 行（{}）".format(len(rows), table.name))

    # ---------- 校验 + 计算变更 ----------
    changes, errors, skipped = [], [], []
    new_level1, new_level2 = set(), set()

    for row in rows:
        name = row.get("文件名", "")
        c1 = row.get("一级分类", "")
        c2 = row.get("二级分类", "")
        tags = parse_tags(row.get("标签", ""))

        if not name:
            errors.append("某一行「文件名」是空的，已跳过")
            continue
        path = POSTS_DIR / name
        if not path.exists():
            errors.append("{}：_posts 里找不到这个文件".format(name))
            continue
        if not c1:
            errors.append("{}：一级分类是空的".format(name))
            continue
        if not c2:
            errors.append("{}：二级分类是空的".format(name))
            continue

        # 分类叫什么都不管，只拦「会破坏 YAML 结构的符号」
        to_check = [("一级分类", c1), ("二级分类", c2)] + [("标签", t) for t in tags]
        bad = next(((lb, v, bad_char(v)) for lb, v in to_check if bad_char(v)), None)
        if bad:
            errors.append("{}：{}「{}」里含有「{}」，写进 YAML 会破坏分类结构，请去掉它".format(
                name, bad[0], bad[1], bad[2]))
            continue

        # 新分类：只提示，不拦截
        if c1 not in LEVEL1_KNOWN:
            new_level1.add(c1)
        elif c1 in LEVEL2_KNOWN and c2 not in LEVEL2_KNOWN[c1]:
            new_level2.add("{}/{}".format(c1, c2))

        if len(tags) > 6:
            errors.append("{}：标签有 {} 个，太长了（建议 2~4 个）".format(name, len(tags)))
            continue

        cats = [c1, c2]
        cur_cats, cur_tags = read_current(path)
        if cur_cats == cats and cur_tags == tags:
            skipped.append(name)
            continue
        changes.append({
            "name": name,
            "old": (cur_cats or [], cur_tags or []),
            "new": (cats, tags),
            "path": path,
        })

    # ---------- 先报错，有问题也照样把没问题的部分写进去 ----------
    if errors:
        print("\n⚠ 以下 {} 行有问题，已跳过（其余行照常处理）：".format(len(errors)))
        for e in errors:
            print("   - " + e)

    if new_level1:
        print("\nℹ 出现 {} 个新的一级分类（会新建对应分类页，这是正常的，不需要改代码）：".format(
            len(new_level1)))
        for x in sorted(new_level1):
            print("   - " + x)

    if new_level2:
        print("\nℹ 出现 {} 个新的二级分类（会新建对应分类页）：".format(len(new_level2)))
        for x in sorted(new_level2):
            print("   - " + x)

    if not changes:
        print("\n没有需要修改的文章（表格内容和文章里的完全一致）。")
        print("已核对 {} 篇，全部无需改动。".format(len(rows)))
        return

    # ---------- 备份 ----------
    backup_dir = None
    if not dry_run:
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_dir = ROOT / "_backup" / ("autosave-" + stamp)
        backup_dir.mkdir(parents=True, exist_ok=True)
        for c in changes:
            shutil.copy2(c["path"], backup_dir / c["name"])
        print("\n已备份 {} 篇到：{}".format(len(changes), backup_dir))

    # ---------- 写入 ----------
    print("\n{}：".format("预览（未写入）" if dry_run else "开始回写"))
    ok = 0
    for c in changes:
        old_cats, old_tags = c["old"]
        new_cats, new_tags = c["new"]
        old_s = "{} / {}".format("/".join(old_cats) or "(空)", "、".join(old_tags) or "(无)")
        new_s = "{} / {}".format("/".join(new_cats) or "(空)", "、".join(new_tags) or "(无)")
        result = apply_to_post(c["path"], new_cats, new_tags, dry_run)
        if result == "changed":
            ok += 1
            print("  ✔ {}".format(c["name"]))
            print("      {} → {}".format(old_s, new_s))
        elif result == "same":
            print("  = {}（内容其实没变）".format(c["name"]))
        else:
            print("  ✘ {}：{}".format(c["name"], result[6:]))

    print("\n共 {} 篇需要修改，实际处理 {} 篇{}。".format(
        len(changes), ok, "（预演，未落盘）" if dry_run else ""))
    if backup_dir:
        print("如需还原，把 {} 里的文件拷回 _posts 即可。".format(backup_dir.name))


if __name__ == "__main__":
    main()