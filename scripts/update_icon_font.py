#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
================================================================================
 图标字体「按需瘦身」脚本（FontAwesome 子集化 + CSS 精简）
--------------------------------------------------------------------------------
 【它干什么】
   1. 扫描整个网站（文章、模板、配置），把"实际用到的图标"全部找出来；
   2. 只从完整字体里抠出这些图标的字形，生成三个小字体文件（solid / regular / brands）；
   3. 把 FontAwesome 的样式表一并瘦身：删掉没用到的图标规则，并把字体地址指向小文件。

 【什么时候要重新运行】
   以后在文章或模板里**新用了一个图标**（例如 fa-user、fa-scale-balanced），
   却发现页面上是个空白方块 —— 说明这个图标没被收进子集。
   这时双击 tools\\4-更新图标字体.bat 重跑一次即可，几秒钟完成。

 【为什么这样能变快】
   原版三个字体文件合计 254 KB，而本站只用了几十个图标；
   抠出来之后合计约 10 KB。样式表也从 90 KB 降到 26 KB（gzip 22.3 KB → 4.5 KB）。

 【重要：本脚本是"可重复运行"的】
   它每次都从 tools/fontawesome-full-backup/ 里的**完整原件**重新生成，
   不会在已经瘦身的文件上再瘦一次。所以放心反复运行。
   如果备份目录不小心删了，可以用 git 恢复（见说明文档）。
================================================================================
"""

import os
import re
import sys
import shutil
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FA_DIR = os.path.join(ROOT, "assets", "self-host", "fontawesome-free")
BAK_DIR = os.path.join(ROOT, "tools", "fontawesome-full-backup")
BAK_CSS = os.path.join(BAK_DIR, "css", "all.min.css")
BAK_WF = os.path.join(BAK_DIR, "webfonts")
OUT_CSS = os.path.join(FA_DIR, "css", "all.min.css")
OUT_WF = os.path.join(FA_DIR, "webfonts")

FONTS = ("fa-solid-900", "fa-regular-400", "fa-brands-400")

# 扫描范围：这些地方出现 fa-xxx 才算"网站在用"
SCAN_DIRS = ("_includes", "_layouts", "_tabs", "_data", "_posts", "assets/css", "docs")
SCAN_FILES = ("index.html",)
SCAN_EXTS = (".html", ".htm", ".md", ".markdown", ".yml", ".yaml", ".liquid", ".js")
SKIP_DIRS = {"tools", "scripts", ".git", ".workbuddy", "_site", "node_modules", "fontawesome-free"}

# ------------------------------------------------------------------------------
# 【基准图标清单】—— 重点，别删
# 下面这些图标是**主题模板**里用到的（返回顶部、搜索框、目录按钮、深浅色切换、
# 文章页的日历/标签/分类等）。它们不在本仓库的文件里，而在主题 gem 包内，
# 本脚本扫描本机源码时看不见它们，所以在这里固定列出，保证永远被保留。
# 这份清单是从线上所有页面实测汇总出来的；想加新图标，加在这里最保险。
# ------------------------------------------------------------------------------
BASELINE_ICONS = [
    "fa-angle-down", "fa-angle-left", "fa-angle-right", "fa-angle-up", "fa-archive",
    "fa-arrow-down", "fa-balance-scale", "fa-bars", "fa-bilibili", "fa-bluesky",
    "fa-book-open", "fa-calendar", "fa-check-circle", "fa-circle", "fa-circle-info",
    "fa-clipboard", "fa-code", "fa-comment-dots", "fa-comments", "fa-copy",
    "fa-display", "fa-envelope", "fa-film", "fa-flask", "fa-folder",
    "fa-folder-open", "fa-github", "fa-handshake", "fa-home", "fa-images",
    "fa-info-circle", "fa-link", "fa-linkedin", "fa-list-ul", "fa-magnifying-glass",
    "fa-mastodon", "fa-moon", "fa-paper-plane", "fa-pen-nib", "fa-qq",
    "fa-reddit", "fa-rotate-left", "fa-rss", "fa-search", "fa-shield-halved",
    "fa-square-reddit", "fa-square-threads", "fa-stack-overflow", "fa-star", "fa-stream",
    "fa-sun", "fa-tag", "fa-tags", "fa-threads", "fa-thumbtack",
    "fa-triangle-exclamation", "fa-user-shield", "fa-weibo", "fa-weixin", "fa-zhihu",
    "fa-xmark",  # 搜索框/弹窗的关闭按钮，主题 JS 里动态插入
    "fa-hashtag",  # 文章标题旁的「#」锚点图标，主题构建时自动加，源码里搜不到
]

# 扫描时排除的"假图标名"（例如字体文件名 fa-solid-900-subset 也长得像图标名）
FAKE_PATTERN = re.compile(r"^fa-[a-z0-9-]*-\d{3}(-subset)?$|^fa-[a-z]+-subset$")


def log(msg=""):
    print(msg)


def collect_source_files():
    files = []
    for d in SCAN_DIRS:
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [x for x in dirnames if x not in SKIP_DIRS]
            for fn in filenames:
                if fn.lower().endswith(SCAN_EXTS):
                    files.append(os.path.join(dirpath, fn))
    for fn in SCAN_FILES:
        p = os.path.join(ROOT, fn)
        if os.path.isfile(p):
            files.append(p)
    return files


def scan_used_icons():
    tokens = set()
    for p in collect_source_files():
        try:
            with open(p, encoding="utf-8", errors="ignore") as f:
                tokens.update(re.findall(r"fa-[a-z0-9-]+", f.read()))
        except OSError:
            pass
    tokens = {t for t in tokens if not FAKE_PATTERN.match(t)}
    return tokens | set(BASELINE_ICONS)


def parse_codepoints(css):
    """从完整样式表里解析「类名 -> 图标码点」

    FontAwesome 的写法有两种，都要认：
      ① 十六进制转义：.fa-user{--fa:"\\f007"}          -> 码点 f007
      ② 字面字符转义：.fa-hashtag{--fa:"\\#"}          -> 码点 0023（就是 # 的 ASCII）
                      .fa-5{--fa:"\\35 "}              -> 码点 0035（数字 5，后面那个空格是分隔符）
    ②这种容易被漏掉，漏掉的后果是：该图标规则被当成"没用的"删掉，
    文章标题旁那个 # 锚点图标就会消失。所以这里必须两种都解析。
    """
    mapping = {}
    rule = re.compile(r'([^{}]+)\{--fa:"\\([^"]*)"')
    for m in rule.finditer(css):
        sels, raw = m.group(1), m.group(2)
        raw = raw.strip()
        if not raw:
            continue
        if re.fullmatch(r"[0-9a-fA-F]{1,6}", raw):
            cp = int(raw, 16)
        elif len(raw) == 1:
            cp = ord(raw)
        elif re.fullmatch(r"[0-9a-fA-F]{1,6} ", raw):
            cp = int(raw.strip(), 16)
        else:
            continue
        for cls in re.findall(r"\.(fa-[a-z0-9-]+)", sels):
            mapping[cls] = "%04x" % cp
    return mapping


def trim_css(css, used):
    """删掉「用不到的图标」的 --fa 声明，其余原样保留"""
    leaf = re.compile(r"([^{}]+)\{([^{}]*)\}")
    out, last, removed, kept = [], 0, 0, 0
    for m in leaf.finditer(css):
        sel, body = m.group(1), m.group(2)
        if '--fa:"\\' not in body:
            continue
        sels = [s.strip() for s in sel.split(",")]
        icon_sels = [s for s in sels if re.fullmatch(r"\.fa-[a-z0-9-]+", s)]
        if not icon_sels or len(icon_sels) != len(sels):
            continue          # 混合选择器 / 非图标规则：一律不动，宁可留多
        if any(s[1:] in used for s in icon_sels):
            kept += 1
            continue
        out.append(css[last:m.start()])
        last = m.end()
        removed += 1
    out.append(css[last:])
    return "".join(out), kept, removed


def build_subset(font_name, unicodes):
    src = os.path.join(BAK_WF, font_name + ".woff2")
    dst = os.path.join(OUT_WF, font_name + "-subset.woff2")
    if not os.path.exists(src):
        log("  [跳过] 找不到原版字体：%s" % src)
        return None
    cmd = [sys.executable, "-m", "fontTools.subset", src,
           "--output-file=" + dst, "--flavor=woff2",
           "--unicodes=" + unicodes,
           "--layout-features=", "--no-hinting", "--desubroutinize",
           "--drop-tables+=DSIG"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        log("  [失败] %s\n%s" % (font_name, r.stderr[-600:]))
        return None
    return os.path.getsize(src), os.path.getsize(dst)


def main():
    log("=" * 66)
    log(" 图标字体瘦身：扫描 -> 抠字形 -> 精简样式表")
    log("=" * 66)

    if not os.path.exists(BAK_CSS):
        log("找不到完整版样式表：%s" % BAK_CSS)
        log("请先用 git 恢复：git checkout -- assets/self-host/fontawesome-free")
        log("（恢复后把 css/all.min.css 与 webfonts/ 里的原版三个字体复制进 tools/fontawesome-full-backup/）")
        return 1

    full_css = open(BAK_CSS, encoding="utf-8").read()
    mapping = parse_codepoints(full_css)
    used = scan_used_icons()

    resolved = {u: mapping[u] for u in used if u in mapping}
    unknown = sorted(u for u in used if u not in mapping)
    log("")
    log("① 扫描：源码里出现 %d 个 fa- 开头的类名，其中 %d 个是真实图标"
        % (len(used), len(resolved)))

    cps = sorted(set(resolved.values()))
    unicodes = ",".join("U+" + c for c in cps)
    log("   需要保留的字形码点：%d 个" % len(cps))

    log("")
    log("② 生成字体子集：")
    total_old = total_new = 0
    os.makedirs(OUT_WF, exist_ok=True)
    for f in FONTS:
        r = build_subset(f, unicodes)
        if r:
            total_old += r[0]
            total_new += r[1]
            log("   %-16s %7d B  ->  %6d B  (省 %d%%)"
                % (f, r[0], r[1], round(100 * (r[0] - r[1]) / r[0])))
    if total_old:
        log("   ------------------------------------------------")
        log("   %-16s %7d B  ->  %6d B  (省 %d%%)"
            % ("合计", total_old, total_new, round(100 * (total_old - total_new) / total_old)))

    log("")
    log("③ 精简样式表：")
    new_css, kept, removed = trim_css(full_css, used)
    for f in FONTS:
        new_css = new_css.replace("../webfonts/%s.woff2" % f, "../webfonts/%s-subset.woff2" % f)
    new_css = new_css.replace("font-display:block", "font-display:swap")
    os.makedirs(os.path.dirname(OUT_CSS), exist_ok=True)
    with open(OUT_CSS, "w", encoding="utf-8", newline="") as f:
        f.write(new_css)
    log("   保留在用图标规则 %d 条，删除闲置规则 %d 条" % (kept, removed))
    log("   all.min.css %d B -> %d B" % (len(full_css), len(new_css)))

    if unknown:
        log("")
        log("④ 提示：下面这些类名在样式表中找不到对应图标（可能是排版样式类，")
        log("   也可能是写错了的图标名，写错的话页面上会是空白方块）：")
        line = "   "
        for u in unknown:
            if len(line) + len(u) > 70:
                log(line)
                line = "   "
            line += u + " "
        log(line)

    log("")
    log("完成。接下来：提交并推送，等 GitHub Actions 构建完成即可生效。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
