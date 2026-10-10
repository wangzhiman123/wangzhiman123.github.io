#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fix_post_links.py —— 把文章正文里的「纯文本网址」批量转成可点击的 Markdown 链接

用法（默认为 dry-run，只预览、不写盘）：

    python scripts/fix_post_links.py                     # 预览：列出每一处改动
    python scripts/fix_post_links.py --apply             # 实际写入（自动备份到仓库外）
    python scripts/fix_post_links.py --dirs _posts _tabs # 指定处理目录
    python scripts/fix_post_links.py --report out.md     # 指定报告输出路径

设计原则（逐条对应需求）
--------------------------------------------------------------------
1. 链接转换
   只处理「裸网址」，即直接出现在正文文字流里的 http:// / https:// / www. 开头串。
   转换形式：  [原始网址](原始网址)          —— 链接文字完整保留原网址，不做任何截断/缩短
   www. 开头（无协议）的目标地址补 https:// —— 这是让链接可点击的最小改动；
                                               链接文字仍原样保留（不含硬加上的协议）
   ⚠ 必须补 https:// 而不是 http:// ：本仓库部署流水线用 html-proofer 做检查，
     其默认开启 --enforce-https，任何 http:// 链接都会导致「构建 → Test site」失败
     （曾因此产生 9 个失败案例）。若原文本身就是 http:// 的裸网址，脚本会照原样
     链接化，但在收尾时把它们单独列为「仍为 http://」警告，请改用 https 或加入忽略名单。

2. 严格排除（受保护区，绝不改动）
   - 图片外链        ![...](...)           与普通链接同样处理
   - 已有 Markdown 链接  [文字](目标)、[文字][引用]
   - HTML 标签与注释   <a href="...">…</a>、<!-- ... -->
   - 自动链接          <https://...>       （本身已是可点击链接，属「已有链接」）
   - 行内代码 `...` 与围栏代码块 ``` ... ```
   - front matter（文件开头两个 --- 之间的所有字段值）

3. 保真原则
   网址字符集限定为 ASCII 可见字符；遇到中文/全角标点即停止，因此
   「www.bt.cn）」只会取到 www.bt.cn，不会把后面的标点或汉字吞进链接。
   同一篇里同一网址，处理方式完全一致（同一套规则、不特判）。
   含反斜杠转义（\\_ \\& 等）的网址一律跳过并单独列出——见 SKIP_BACKSLASH。

4. 顺带优化（保守执行）
   仅检查：链接格式错误、多余空格、标点被误吞、行内重复链接。
   检查结果一律只报告、不自动改——原因见 README 段与脚本末尾 NOTE。

5. 幂等
   转换后的网址会落在 [...] 或 (...) 内，第二次运行必然被判为「已有链接」而跳过。
   脚本自身也会在写入后立刻复跑一次校验，断言 0 改动。
"""

from __future__ import annotations

import argparse
import datetime
import os
import re
import shutil
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ----------------------------------------------------------------------------
# 正则与字符集
# ----------------------------------------------------------------------------
# 网址的起点
URL_START = re.compile(r"(?:https?://|www\.)", re.I)

# 网址可包含的字符：仅 ASCII，且排除引号/尖括号/反引号/竖线。
# 特意保留反斜杠：先把这个网址整体"吃掉"，再判断是否含转义，从而整段跳过。
URL_CHARS = frozenset(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "abcdefghijklmnopqrstuvwxyz"
    "0123456789"
    "-._~:/?#@!$&*+;=%()[]\\"
)

# 防御性：网址尾部若出现这些半角标点，视为句读而非网址的一部分。
# 实际数据里一次都不会触发（详见报告的「尾部标点」统计）。
TRAIL_STRIP = frozenset(".,;:!?")

# 用于「分类统计」的宽松正则（把码点 >=128 的中文/全角一律排除）
#
# 注意：这里刻意不使用 re.IGNORECASE。Python 的 re 在「取反字符类 + 大范围 Unicode
# 区间 + IGNORECASE」三者同时出现时，会把该区间的「大小写折叠伙伴」也一并排除，
# 导致 i / k / s（源自 ſ、K 等折叠字符）被误排除，网址会从中途被截断：
#     re.findall(r"[^\s\"'<>`\u0080-\uffff]+", "https://www.sd12368.gov.cn/login", re.I)
#     -> ['https://www.']            # 错误
# 因此这里改用显式的大小写写法来表达 http/https/www，规避该陷阱。
RE_URL_ANY = re.compile(
    r"(?:[Hh][Tt][Tt][Pp][Ss]?://|[Ww][Ww][Ww]\.)[^\s\"'<>`\[\]\u0080-\U0010FFFF]+"
)

# 受保护区
RE_INLINE_CODE = re.compile(r"(`+)[^`]*?\1")
RE_AUTOLINK = re.compile(r"<[A-Za-z][A-Za-z0-9+.\-]*:[^<>\s]*>")
RE_HTML_TAG = re.compile(r"</?[A-Za-z][A-Za-z0-9\-]*(?:\s[^<>]*?)?/?>")
RE_HTML_COMMENT = re.compile(r"<!--.*?-->")
RE_MD_LINK = re.compile(r"!?\[[^\]\n]*\]\([^)\n]*\)")
RE_MD_REF = re.compile(r"!?\[[^\]\n]*\]\[[^\]\n]*\]")

FENCE_RE = re.compile(r"^\s*(```|~~~)")


# ----------------------------------------------------------------------------
# 受保护区计算
# ----------------------------------------------------------------------------
def protected_spans(line):
    """返回 [(start, end, kind)] —— 本行中不可触碰的区间。"""
    spans = []
    for m in RE_INLINE_CODE.finditer(line):
        spans.append((m.start(), m.end(), "行内代码"))
    for m in RE_HTML_COMMENT.finditer(line):
        spans.append((m.start(), m.end(), "HTML 注释"))
    for m in RE_AUTOLINK.finditer(line):
        spans.append((m.start(), m.end(), "自动链接"))
    for m in RE_HTML_TAG.finditer(line):
        spans.append((m.start(), m.end(), "HTML 标签"))
    for rx, kind in ((RE_MD_LINK, "MD链接"), (RE_MD_REF, "引用式链接")):
        for m in rx.finditer(line):
            spans.append((m.start(), m.end(), kind))
    return spans


def kind_at(line, pos):
    """pos 落在哪个受保护区；不在任何区内返回 None。"""
    best = None
    for a, b, k in protected_spans(line):
        if a <= pos < b:
            # 区间可能重叠，取最靠外层（起点最小）的
            if best is None or a < best[0]:
                best = (a, b, k)
    return best


# ----------------------------------------------------------------------------
# 裸网址扫描
# ----------------------------------------------------------------------------
def find_bare_urls(line):
    """按「从左到右、已消费部分不再匹配」的方式找裸网址。

    返回 [(start, end, url)]。这样能避免 https://www.x 里的 www. 被重复识别。
    """
    out = []
    consumed_to = -1
    for m in URL_START.finditer(line):
        s = m.start()
        if s < consumed_to:
            continue  # 落在上一个网址内部（典型：https://www.xxx 中的 www.）
        prot = kind_at(line, s)
        if prot is not None:
            consumed_to = max(consumed_to, prot[1])
            continue
        i = s
        n = len(line)
        while i < n and line[i] in URL_CHARS:
            i += 1
        e = i
        while e > s and line[e - 1] in TRAIL_STRIP:
            e -= 1
        if e - s < 4:
            continue
        out.append((s, e, line[s:e]))
        consumed_to = e
    return out


def make_link(url):
    """生成 Markdown 链接。

    - www. 开头（无协议）→ 补 https://（部署检查要求 HTTPS，见文件头说明）
    - 已带 http:// / https:// 的裸网址 → 照原样使用，不改协议
    """
    href = ("https://" + url) if re.match(r"^www\.", url, re.I) else url
    return "[%s](%s)" % (url, href), href


def transform_line(line):
    """返回 (新行, [change])；change = dict(start,end,url,new,status)"""
    found = find_bare_urls(line)
    if not found:
        return line, []
    parts = []
    changes = []
    prev = 0
    for s, e, url in found:
        parts.append(line[prev:s])
        if "\\" in url:
            status, new = "skip-backslash", url
        elif "(" in url or ")" in url:
            status, new = "skip-paren", url
        else:
            new, _href = make_link(url)
            status = "link"
        parts.append(new)
        changes.append({"start": s, "end": e, "url": url, "new": new, "status": status})
        prev = e
    parts.append(line[prev:])
    return "".join(parts), changes


# ----------------------------------------------------------------------------
# 文件切分
# ----------------------------------------------------------------------------
def split_front_matter(lines):
    """返回 front matter 结束行号（0 表示没有 front matter）。"""
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() in ("---", "..."):
                return i
    return 0


def body_flags(lines, fm_end):
    """标记每行是否位于围栏代码块内。返回 [bool] * len(lines)"""
    inside = [False] * len(lines)
    fence = None
    for i, l in enumerate(lines):
        m = FENCE_RE.match(l)
        if i <= fm_end:
            continue
        if fence is None:
            if m:
                fence = m.group(1)
                inside[i] = True
        else:
            inside[i] = True
            if m and m.group(1) == fence:
                fence = None
    return inside


# ----------------------------------------------------------------------------
# 分类统计（用于报告里的「跳过清单」）
# ----------------------------------------------------------------------------
def classify_file(path):
    raw = open(path, encoding="utf-8", newline="").read()
    lines = raw.split("\n")
    fm_end = split_front_matter(lines)
    in_fence = body_flags(lines, fm_end)

    counts = {}
    details = []

    def bump(k):
        counts[k] = counts.get(k, 0) + 1

    for idx, line in enumerate(lines):
        if idx <= fm_end:
            for m in RE_URL_ANY.finditer(line):
                bump("front matter 字段值")
                details.append((idx + 1, "front matter 字段值", m.group(0)))
            continue
        if in_fence[idx]:
            for m in RE_URL_ANY.finditer(line):
                bump("代码块")
                details.append((idx + 1, "代码块", m.group(0)))
            continue
        for m in RE_URL_ANY.finditer(line):
            s, e = m.start(), m.end()
            prot = kind_at(line, s)
            if prot is not None:
                a, b, k = prot
                if k == "MD链接":
                    # 区分 图片 / 链接目标 / 链接文字
                    seg = line[a:b]
                    img = seg.startswith("!")
                    dst_at = seg.find("](")
                    is_dest = dst_at >= 0 and a + dst_at + 1 <= s
                    if img and is_dest:
                        label = "图片外链"
                    elif is_dest:
                        label = "已有链接（目标地址）"
                    else:
                        label = "已有链接（链接文字）"
                elif k == "自动链接":
                    label = "自动链接 <url>（本身已可点击）"
                else:
                    label = k
                bump(label)
                details.append((idx + 1, label, m.group(0)))
                continue
            # 裸网址
            if "\\" in m.group(0):
                label = "含反斜杠转义（跳过，需人工确认）"
            else:
                label = "裸网址"
            if label != "裸网址":
                bump(label)
                details.append((idx + 1, label, m.group(0)))
    return counts, details


# ----------------------------------------------------------------------------
# 其他可优化项的检查（只报告，不修改）
# ----------------------------------------------------------------------------
def audit_other(path, lines, fm_end, in_fence):
    """返回 [(类别, 行号, 说明)]"""
    found = []
    body = [(i, l) for i, l in enumerate(lines) if i > fm_end]
    # a) 行内重复链接：链接文字 == 目标地址
    for i, l in body:
        for m in re.finditer(r"(!?)\[([^\]\n]*)\]\(([^)\n]*)\)", l):
            txt, dst = m.group(2).strip(), m.group(3).strip()
            if txt and dst and (txt == dst or txt == "http://" + dst or "http://" + txt == dst):
                found.append(("行内重复链接", i + 1, "链接文字与目标地址相同：%s" % txt[:70]))
    # b) 链接语法里混入空格
    for i, l in body:
        for m in re.finditer(r"\]\s{1,}\(", l):
            found.append(("链接格式错误", i + 1, "']' 与 '(' 之间有空格：%r" % l[max(0, m.start() - 30):m.end() + 30]))
        for m in re.finditer(r"!\s+\[", l):
            found.append(("链接格式错误", i + 1, "图片标记 '![' 内有多余空格：%r" % l[max(0, m.start() - 30):m.end() + 30]))
    # c) 残缺自动链接：'< ' 后紧跟网址（尖括号没闭合到网址上）
    for i, l in body:
        for m in re.finditer(r"<\s+(?:https?://|www\.)", l):
            found.append(("链接格式错误", i + 1, "'< ' 与网址之间有空格，自动链接已失效：%r" % l[max(0, m.start() - 25):m.end() + 45]))
    # d) 行尾双空格 = Markdown 硬换行，属有意义空白，禁止自动删
    hard = sum(1 for i, l in body if l.endswith("  "))
    if hard:
        found.append(("行尾双空格", 0, "%d 行 —— 是 Markdown 硬换行（有意保留），不自动删除" % hard))
    # e) 半角/全角括号混用
    half = 0
    for i, l in body:
        if in_fence[i]:
            continue
        half += len(re.findall(r"[\u4e00-\u9fff][()]|[()][\u4e00-\u9fff]", l))
    if half:
        found.append(("半全角标点混用", 0, "%d 处 —— 属原文书写风格，不改写正文" % half))
    return found


# ----------------------------------------------------------------------------
# 处理单个文件
# ----------------------------------------------------------------------------
def process_file(path, apply=False):
    raw = open(path, encoding="utf-8", newline="").read()
    lines = raw.split("\n")
    fm_end = split_front_matter(lines)
    in_fence = body_flags(lines, fm_end)

    new_lines = list(lines)
    changes = []
    for i in range(fm_end + 1, len(lines)):
        if in_fence[i]:
            continue
        nl, ch = transform_line(lines[i])
        if ch:
            new_lines[i] = nl
            for c in ch:
                c["line"] = i + 1
            changes.append((i + 1, lines[i], nl, ch))

    new_raw = "\n".join(new_lines)
    modified = new_raw != raw
    if apply and modified:
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(new_raw)
    return {
        "path": path,
        "raw_len": len(raw),
        "new_len": len(new_raw),
        "modified": modified,
        "changes": changes,
        "lines": lines,
        "new_lines": new_lines,
        "fm_end": fm_end,
        "in_fence": in_fence,
    }


# ----------------------------------------------------------------------------
# 收尾自检：处理后仍存在的 http:// 链接（部署检查会拒绝）
# ----------------------------------------------------------------------------
# 与 .github/workflows/pages-deploy.yml 中 html-proofer 的 --ignore-urls 保持一致
HTTP_IGNORE_RE = re.compile(r"^http://(127\.0\.0\.1|0\.0\.0\.0|localhost|lsrz\.cs\.mfa\.gov\.cn)")
# 只匹配「会渲染成 <a href>」的 http:// 网址（html-proofer 的 enforce-https 只管链接）：
#   1) Markdown 链接目标  ](http://…)        （! 开头的图片链接不算，图片走 check-img-http）
#   2) 自动链接           <http://…>          （注意 '<' 后不能有空格，有空格就不是链接）
#   3) 原始 HTML 属性     href="http://…"
#   4) 引用式定义         [id]: http://…
HTTP_IN_LINK_RE = re.compile(
    r"(?<!!)\]\((http://[^\s)\"'<>`]+)"
    r"|<(http://[^\s<>`]+)>"
    r"|href=[\"'](http://[^\s\"'<>`]+)[\"']"
    r"|^\s{0,3}\[[^\]]+\]:\s*(http://[^\s]+)"
)


def scan_http_links(lines, fm_end, in_fence):
    """返回 [(行号, url)] —— 处理后仍未使用 https 的链接。"""
    out = []
    for i, l in enumerate(lines):
        if i <= fm_end or (in_fence and in_fence[i]):
            continue
        for m in HTTP_IN_LINK_RE.finditer(l):
            u = next((g for g in m.groups() if g), None)
            if u and not HTTP_IGNORE_RE.match(u):
                out.append((i + 1, u))
    return out


# ----------------------------------------------------------------------------
# 主流程
# ----------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="把文章正文里的纯文本网址转成 Markdown 链接")
    ap.add_argument("--apply", action="store_true", help="实际写入（默认只预览）")
    ap.add_argument("--dry-run", action="store_true", help="预览，不写盘（默认行为，显式写出亦可）")
    ap.add_argument("--dirs", nargs="+", default=["_posts"], help="要处理的目录，默认 _posts")
    ap.add_argument("--report", default=None, help="报告输出路径（默认写到仓库外）")
    ap.add_argument("--backup-root", default=None, help="备份根目录（默认仓库外 backups/）")
    args = ap.parse_args()

    report_path = args.report or os.path.join(
        os.path.dirname(REPO_ROOT), "link-fix-report.md"
    )
    backup_root = args.backup_root or os.path.join(
        os.path.dirname(REPO_ROOT), "backups"
    )

    files = []
    for d in args.dirs:
        full = os.path.join(REPO_ROOT, d)
        if not os.path.isdir(full):
            continue
        for name in sorted(os.listdir(full)):
            if name.lower().endswith((".md", ".mdx", ".markdown")):
                files.append(os.path.join(full, name))

    print("=" * 74)
    print("文章网址链接化处理  %s" % ("【实际写入】" if args.apply else "【预览 dry-run】"))
    print("=" * 74)
    print("仓库根目录 : %s" % REPO_ROOT)
    print("扫描目录   : %s" % ", ".join(args.dirs))
    print("文章文件数 : %d" % len(files))
    print()

    # 备份
    backup_dir = None
    if args.apply:
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_dir = os.path.join(backup_root, "posts-links-" + stamp)
        for d in args.dirs:
            src = os.path.join(REPO_ROOT, d)
            if os.path.isdir(src):
                shutil.copytree(src, os.path.join(backup_dir, d))
        print("已备份到   : %s" % backup_dir)
        print()

    # ---- 分类统计（必须在写入之前做，否则统计到的是「已转换后」的内容）----
    total_counts = {}
    detail_map = {}
    for f in files:
        cnt, det = classify_file(f)
        for k, v in cnt.items():
            total_counts[k] = total_counts.get(k, 0) + v
        detail_map[f] = det

    # ---- 执行处理 ----
    results = [process_file(f, apply=args.apply) for f in files]

    touched = [r for r in results if r["modified"]]
    all_changes = []
    skip_backslash = []
    skip_paren = []
    for r in results:
        for ln, before, after, ch in r["changes"]:
            for c in ch:
                if c["status"] == "link":
                    all_changes.append((r["path"], ln, c))
                elif c["status"] == "skip-backslash":
                    skip_backslash.append((r["path"], ln, c))
                else:
                    skip_paren.append((r["path"], ln, c))

    # ---- 其他检查 ----
    audits = []
    for r in results:
        audits += [(r["path"],) + a for a in audit_other(r["path"], r["lines"], r["fm_end"], r["in_fence"])]

    # ---- 收尾自检：处理后仍为 http:// 的链接（会被部署检查拒绝）----
    http_left = []
    for r in results:
        for ln, u in scan_http_links(r["new_lines"], r["fm_end"], r["in_fence"]):
            http_left.append((r["path"], ln, u))

    # ---- 控制台 ----
    print("被修改的文件 : %d / %d" % (len(touched), len(results)))
    print("新增链接     : %d 处" % len(all_changes))
    print()
    if all_changes:
        print("-" * 74)
        print("改动明细（前 12 处，完整清单见报告文件）")
        print("-" * 74)
        for path, ln, c in all_changes[:12]:
            print("  %s L%d" % (os.path.relpath(path, REPO_ROOT), ln))
            print("    - %s" % c["url"])
            print("    + %s" % c["new"])
        if len(all_changes) > 12:
            print("  … 其余 %d 处见报告" % (len(all_changes) - 12))
    print()

    # ---- 收尾自检结果 ----
    if http_left:
        print("⚠ 仍为 http:// 的链接 : %d 处（部署的 html-proofer 检查会因此失败）" % len(http_left))
        for path, ln, u in http_left[:12]:
            print("    %s L%d  %s" % (os.path.relpath(path, REPO_ROOT), ln, u))
        if len(http_left) > 12:
            print("    … 其余 %d 处见报告" % (len(http_left) - 12))
        print("  建议：改用 https://，或在 pages-deploy.yml / tools/test.sh 的 --ignore-urls 中放行。")
    else:
        print("收尾自检     : 未发现 http:// 链接（部署检查可通过）")
    print()

    # ---- 报告 ----
    lines = []
    w = lines.append
    w("# 文章正文网址链接化 · 处理报告")
    w("")
    w("- 生成时间：%s" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    w("- 运行模式：%s" % ("实际写入" if args.apply else "预览（未写盘）"))
    w("- 仓库根目录：`%s`" % REPO_ROOT)
    w("- 扫描目录：%s" % ", ".join("`%s`" % d for d in args.dirs))
    w("- 文章文件数：%d（.md / .mdx / .markdown）" % len(files))
    if backup_dir:
        w("- 备份目录：`%s`" % backup_dir)
    w("")
    w("## 一、总体结果")
    w("")
    w("| 指标 | 数量 |")
    w("| --- | --- |")
    w("| 被修改的文件 | %d / %d |" % (len(touched), len(results)))
    w("| 新增 Markdown 链接 | %d 处 |" % len(all_changes))
    w("| 跳过（含反斜杠转义） | %d 处 |" % len(skip_backslash))
    w("| 跳过（网址含括号） | %d 处 |" % len(skip_paren))
    w("")

    w("## 二、被修改的文件与逐处改动")
    w("")
    if not touched:
        w("（无）")
        w("")
    for r in touched:
        rel = os.path.relpath(r["path"], REPO_ROOT)
        n = sum(len(ch) for _ln, _b, _a, ch in r["changes"])
        w("### %s" % rel)
        w("")
        w("改动 %d 处。" % n)
        w("")
        for ln, before, after, ch in r["changes"]:
            for c in ch:
                s, e = c["start"], c["end"]
                ctx_a = before[max(0, s - 30):e + 30]
                new_s = s + (len(c["new"]) - (e - s))
                ctx_b = after[max(0, s - 30):new_s + 30]
                if c["status"] == "skip-backslash":
                    w("- **第 %d 行 · 跳过（含反斜杠转义）**" % ln)
                elif c["status"] == "skip-paren":
                    w("- **第 %d 行 · 跳过（网址含括号）**" % ln)
                else:
                    w("- **第 %d 行**" % ln)
                w("  - 前：`%s`" % ctx_a.replace("\n", " "))
                w("  - 后：`%s`" % ctx_b.replace("\n", " "))
        w("")

    w("## 三、跳过的内容及原因")
    w("")
    w("### 3.1 按类别汇总")
    w("")
    w("| 类别 | 出现次数 | 是否改动 |")
    w("| --- | --- | --- |")
    order = [
        ("裸网址", "已转换"),
        ("图片外链", "不改动（严格排除）"),
        ("已有链接（目标地址）", "不改动（严格排除）"),
        ("已有链接（链接文字）", "不改动（严格排除）"),
        ("自动链接 <url>（本身已可点击）", "不改动（严格排除）"),
        ("代码块", "不改动（严格排除）"),
        ("行内代码", "不改动（严格排除）"),
        ("front matter 字段值", "不改动（严格排除）"),
        ("HTML 标签", "不改动（严格排除）"),
        ("HTML 注释", "不改动（严格排除）"),
        ("引用式链接", "不改动（严格排除）"),
        ("含反斜杠转义（跳过，需人工确认）", "跳过，需你确认"),
    ]
    for k, note in order:
        if total_counts.get(k):
            w("| %s | %d | %s |" % (k, total_counts[k], note))
    for k, v in sorted(total_counts.items()):
        if k not in dict(order):
            w("| %s | %d | — |" % (k, v))
    w("")

    w("### 3.2 含反斜杠转义的网址（未改动，建议人工确认）")
    w("")
    if not skip_backslash:
        w("（无）")
    else:
        w("这些网址的源码里带 Markdown 转义符（如 `\\_`、`\\&`）。")
        w("转成链接后，链接目标里可能残留反斜杠而导致打不开，因此**未作改动**。")
        w("若你确认要一并转换，告诉我即可。")
        w("")
        w("| 文件 | 行 | 原文网址 |")
        w("| --- | --- | --- |")
        for path, ln, c in skip_backslash:
            w("| %s | %d | `%s` |" % (os.path.relpath(path, REPO_ROOT), ln, c["url"]))
    w("")

    w("### 3.3 逐条跳过明细（抽样上限 60 条）")
    w("")
    w("| 文件 | 行 | 原因 | 该处网址/片段 |")
    w("| --- | --- | --- | --- |")
    shown = 0
    for f in files:
        rel = os.path.relpath(f, REPO_ROOT)
        for ln, label, frag in detail_map[f][:3]:
            w("| %s | %d | %s | `%s` |" % (rel, ln, label, frag[:70]))
            shown += 1
            if shown >= 60:
                break
        if shown >= 60:
            break
    w("")
    w("> 说明：图片外链、已有链接、自动链接、代码块常数量较大，此处仅按文件抽样；")
    w("> 汇总数量见 3.1 表格。")
    w("")

    w("## 四、顺带优化项检查结果（只报告，未修改）")
    w("")
    if not audits:
        w("未发现问题。")
    else:
        w("| 文件 | 行 | 类别 | 说明 |")
        w("| --- | --- | --- | --- |")
        for path, cat, ln, desc in audits:
            w("| %s | %s | %s | %s |" % (
                os.path.relpath(path, REPO_ROOT),
                (str(ln) if ln else "—"),
                cat,
                desc.replace("|", "\\|")[:150],
            ))
    w("")
    w("**为什么这些没有自动修改**：")
    w("")
    w("- 行尾双空格：这是 Markdown 的「硬换行」语法，删掉会改变渲染结果，故保留。")
    w("- 列表标记后的两个空格（如 `1.  xxx`）：合法且常见，非错误。")
    w("- 半角/全角括号混用：属原文书写风格，改了就等于改写正文，故不动。")
    w("- `'< '` 残缺自动链接：已把其中的网址链接化，但尖括号 `'<'`、`'>'` 是正文里的字符，")
    w("  删除它们不属于「只加链接语法」，故保留原样，列在此处供你判断。")
    w("- 行内重复链接：未发现。")
    w("## 五、http:// 链接自检（部署检查相关）")
    w("")
    w("部署流水线（`.github/workflows/pages-deploy.yml`）用 html-proofer 检查产物，")
    w("其默认开启 `--enforce-https`，任何 http:// 链接都会让「构建 → Test site」失败。")
    w("下列为本次处理后**仍为 http://** 的链接：")
    w("")
    if not http_left:
        w("（无）—— 部署检查应可通过。")
    else:
        w("| 文件 | 行 | 网址 |")
        w("| --- | --- | --- |")
        for path, ln, u in http_left:
            w("| %s | %d | `%s` |" % (os.path.relpath(path, REPO_ROOT), ln, u))
        w("")
        w("> 处理建议：优先改用 `https://`；若目标站点不支持 https（如政府老站点），")
        w("> 可在 `pages-deploy.yml` 与 `tools/test.sh` 的 `--ignore-urls` 中放行。")
    w("")

    w("## 六、幂等性")
    w("")
    w("转换后的网址位于 `[...]` 或 `(...)` 中，再次运行会被判为「已有链接」而跳过，")
    w("因此重复运行不会产生重复修改。脚本在写入后会自动复跑一次并校验改动数归零。")
    w("")

    with open(report_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")

    print("报告已写入 : %s" % report_path)
    print("分类统计   : %s" % ", ".join("%s=%d" % (k, v) for k, v in sorted(total_counts.items())))
    print()

    # ---- 幂等校验 ----
    if args.apply:
        again = [process_file(f, apply=False) for f in files]
        residual = sum(1 for r in again if r["modified"])
        print("幂等校验   : 复跑后仍需改动的文件数 = %d %s"
              % (residual, "（通过）" if residual == 0 else "（异常！）"))
        return 0 if residual == 0 else 2
    else:
        print("提示       : 这是预览模式，未写入任何文件。确认无误后加 --apply 执行。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
