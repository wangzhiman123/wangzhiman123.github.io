#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
preflight.py —— 部署前「一键」自检：环境准备 → 构建 → 运行 → 结果校验

背景
--------------------------------------------------------------------
本仓库的部署流水线 `.github/workflows/pages-deploy.yml` 在「构建」作业里会执行：

    bundle exec jekyll b -d _site
    bundle exec htmlproofer _site --disable-external \
        --ignore-urls "/^http:\\/\\/127.0.0.1/,/^http:\\/\\/0.0.0.0/,/^http:\\/\\/localhost/,/^http:\\/\\/lsrz\\.cs\\.mfa\\.gov\\.cn/"

html-proofer 默认开启 `--enforce-https`：只要产物里出现 http:// 链接，就会报
「不是HTTPS链接」并使构建失败（曾因此出现 9 个失败案例）。

本脚本把这条规则在本地复现成「一键命令」，无需安装 Ruby 也能先跑一遍，
从而在 push 之前就发现问题，避免再次触发流水线失败。

它做什么（四步）
--------------------------------------------------------------------
  [1/4] 环境准备 —— 检测 python / ruby / bundler / jekyll 是否就绪
  [2/4] 构建     —— 有 Ruby 就真正执行 jekyll 构建；没有就用「源码等价模式」
  [3/4] 运行     —— 按与 html-proofer 等价的规则扫描 http:// 链接
  [4/4] 结果校验 —— 汇总、给出退出码（0=通过，1=不通过）

用法
--------------------------------------------------------------------
    python tools/preflight.py                 # 自动：有 Ruby 就构建，否则源码模式
    python tools/preflight.py --no-build      # 强制源码模式（最快，只查链接规则）
    python tools/preflight.py --site _site    # 扫描已构建好的目录
    python tools/preflight.py --report out.md # 同时输出 markdown 报告
    python tools/preflight.py --json          # 机器可读输出

退出码：0 = 通过；1 = 发现不合规链接；2 = 环境/参数错误。
"""

from __future__ import annotations

import argparse
import datetime
import html
import json
import os
import re
import shutil
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 与 pages-deploy.yml / tools/test.sh 的 --ignore-urls 保持一致
IGNORE_RE = re.compile(
    r"^http://(127\.0\.0\.1|0\.0\.0\.0|localhost|lsrz\.cs\.mfa\.gov\.cn)([:/]|$)"
)

# 源码（Markdown）里「会渲染成 <a href>」的 http:// 网址：
#   1) 链接目标 ](http://…)（! 开头的图片不算）
#   2) 自动链接 <http://…>（'<' 后不能有空格）
#   3) 原始 HTML 属性 href="http://…"
#   4) 引用式定义 [id]: http://…
MD_LINK_HTTP_RE = re.compile(
    r"(?<!!)\]\((http://[^\s)\"'<>`]+)"
    r"|<(http://[^\s<>`]+)>"
    r"|href=[\"'](http://[^\s\"'<>`]+)[\"']"
    r"|^\s{0,3}\[[^\]]+\]:\s*(http://[^\s]+)",
    re.M,
)

# 产物（HTML）里 html-proofer 会检查的属性
HTML_HREF_RE = re.compile(r"""\b(?:href|src)\s*=\s*["'](http://[^"'<>`\s]+)["']""", re.I)

FENCE_RE = re.compile(r"^\s*(```|~~~)")
SOURCE_DIRS = ["_posts", "_tabs", "_includes", "_layouts"]
SOURCE_EXTS = (".md", ".markdown", ".html", ".htm")


# ---------------------------------------------------------------------------
# 小工具
# ---------------------------------------------------------------------------
def which(name):
    return shutil.which(name)


def run(cmd, cwd=REPO_ROOT, timeout=1800):
    try:
        p = subprocess.run(
            cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", errors="replace", timeout=timeout,
        )
        return p.returncode, p.stdout or ""
    except FileNotFoundError:
        return 127, "%s: command not found" % cmd[0]
    except subprocess.TimeoutExpired:
        return 124, "命令超时：%s" % " ".join(cmd)


# ---------------------------------------------------------------------------
# [3/4] 检查规则
# ---------------------------------------------------------------------------
def scan_markdown(path):
    """扫描 md 文件（跳过 front matter 与围栏代码块），返回 [(行号, url, 原文行)]。"""
    hits = []
    try:
        lines = open(path, encoding="utf-8", errors="ignore").read().split("\n")
    except OSError:
        return hits
    fm_end = 0
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() in ("---", "..."):
                fm_end = i
                break
    fence = False
    fchar = None
    for i, l in enumerate(lines):
        if i <= fm_end:
            continue
        m = FENCE_RE.match(l)
        if fence:
            if m and m.group(1) == fchar:
                fence = False
            continue
        if m:
            fence = True
            fchar = m.group(1)
            continue
        for mm in MD_LINK_HTTP_RE.finditer(l):
            u = next((g for g in mm.groups() if g), None)
            if u and not IGNORE_RE.match(u):
                hits.append((i + 1, u, l.strip()))
    return hits


def scan_html(path):
    """扫描已构建/模板 HTML，返回 [(行号, url, 原文行)]。"""
    hits = []
    try:
        lines = open(path, encoding="utf-8", errors="ignore").read().split("\n")
    except OSError:
        return hits
    for i, l in enumerate(lines):
        for mm in HTML_HREF_RE.finditer(l):
            u = mm.group(1)
            if not IGNORE_RE.match(u):
                hits.append((i + 1, u, l.strip()[:200]))
    return hits


def collect_files(mode):
    files = []
    if mode == "site":
        root = os.path.join(REPO_ROOT, "_site")
        for dp, _dn, fn in os.walk(root):
            for f in fn:
                if f.lower().endswith((".html", ".htm")):
                    files.append(os.path.join(dp, f))
    else:
        for d in SOURCE_DIRS:
            full = os.path.join(REPO_ROOT, d)
            if not os.path.isdir(full):
                continue
            for dp, _dn, fn in os.walk(full):
                for f in fn:
                    if f.lower().endswith(SOURCE_EXTS):
                        files.append(os.path.join(dp, f))
        idx = os.path.join(REPO_ROOT, "index.html")
        if os.path.isfile(idx):
            files.append(idx)
    return sorted(files)


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="部署前一键自检（HTTP/HTTPS 链接规则）")
    ap.add_argument("--no-build", action="store_true", help="跳过 jekyll 构建，直接用源码检查")
    ap.add_argument("--site", default=None, help="指定已构建目录（默认 _site）")
    ap.add_argument("--report", default=None, help="输出 markdown 报告路径")
    ap.add_argument("--json", action="store_true", help="输出 JSON")
    args = ap.parse_args()

    log = []          # 控制台/报告文本
    def say(s=""):
        log.append(s)
        if not args.json:
            print(s)

    say("=" * 74)
    say("部署前一键自检   %s" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    say("=" * 74)
    say("仓库根目录 : %s" % REPO_ROOT)
    say("")

    # ---------------- [1/4] 环境准备 ----------------
    say("[1/4] 环境准备")
    py_ok = sys.version_info >= (3, 6)
    ruby = which("ruby")
    bundle = which("bundle")
    jekyll = which("jekyll")
    say("  - python  : %s %s" % (sys.version.split()[0], "OK" if py_ok else "版本过低"))
    say("  - ruby    : %s" % (ruby or "未安装"))
    say("  - bundler : %s" % (bundle or "未安装"))
    say("  - jekyll  : %s" % (jekyll or "未安装（随 bundle exec 提供）"))
    can_build = bool(ruby) and (bool(bundle) or bool(jekyll))
    say("  - 构建能力: %s" % ("可用（将执行真实 Jekyll 构建）" if can_build else
                             "不可用（改用源码等价模式，规则一致）"))
    say("")

    # ---------------- [2/4] 构建 ----------------
    say("[2/4] 构建")
    site_dir = os.path.join(REPO_ROOT, args.site or "_site")
    built = False
    mode = "source"
    if not args.no_build and can_build:
        if bundle:
            rc, out = run([bundle, "exec", "jekyll", "b", "-d", "_site"], timeout=2400)
        else:
            rc, out = run([jekyll, "b", "-d", "_site"], timeout=2400)
        if rc == 0 and os.path.isdir(site_dir):
            say("  - jekyll 构建成功 → _site/（%d 个 HTML）" %
                sum(1 for dp, _dn, fn in os.walk(site_dir) for f in fn if f.endswith(".html")))
            built = True
            mode = "site"
        else:
            say("  - jekyll 构建失败（退出码 %d），改用源码等价模式" % rc)
            for line in (out or "").splitlines()[-15:]:
                say("      %s" % line)
    elif args.site and os.path.isdir(site_dir):
        say("  - 使用已存在的构建目录：%s" % site_dir)
        built = True
        mode = "site"
    else:
        say("  - 跳过构建（未安装 Ruby 或指定了 --no-build）→ 源码等价模式")
        say("    说明：源码模式应用的是与 html-proofer 完全相同的「禁 http:// 链接」规则，")
        say("          只差没有真正渲染 HTML，足以拦截本次这类报错。")
    say("")

    # ---------------- [3/4] 运行 ----------------
    say("[3/4] 运行检查")
    files = collect_files(mode)
    say("  - 检查模式: %s" % ("_site 产物 HTML" if mode == "site" else "源码 Markdown/HTML"))
    say("  - 文件数量: %d" % len(files))
    failures = []
    for f in files:
        hits = scan_html(f) if (mode == "site" or f.lower().endswith((".html", ".htm")) and mode == "source") else scan_markdown(f)
        for ln, url, ctx in hits:
            failures.append({"file": os.path.relpath(f, REPO_ROOT), "line": ln, "url": url, "context": ctx})
    say("  - 不合规链接（非 https 且不在忽略名单）: %d 处" % len(failures))
    say("")

    # ---------------- [4/4] 结果校验 ----------------
    say("[4/4] 结果校验")
    ok = len(failures) == 0
    if ok:
        say("  ✅ 通过：未发现 http:// 链接，部署流水线的「Test site」应可通过。")
    else:
        say("  ❌ 未通过：以下链接会被 html-proofer 判为「不是HTTPS链接」：")
        for x in failures[:40]:
            say("      %s:%d  %s" % (x["file"], x["line"], x["url"]))
        if len(failures) > 40:
            say("      … 其余 %d 处" % (len(failures) - 40))
        say("  修复建议：改用 https://；确不支持 https 的站点，请加入")
        say("            .github/workflows/pages-deploy.yml 与 tools/test.sh 的 --ignore-urls。")
    say("")
    say("=" * 74)
    say("结论：%s" % ("PASS" if ok else "FAIL"))
    say("=" * 74)

    if args.report:
        with open(args.report, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("# 部署前一键自检报告\n\n```\n" + "\n".join(log) + "\n```\n\n")
            if failures:
                fh.write("## 不合规链接\n\n| 文件 | 行 | 网址 |\n| --- | --- | --- |\n")
                for x in failures:
                    fh.write("| %s | %d | `%s` |\n" % (x["file"], x["line"], x["url"]))
        if not args.json:
            print("报告已写入 : %s" % args.report)

    if args.json:
        print(json.dumps({"ok": ok, "mode": mode, "files": len(files),
                          "failures": failures}, ensure_ascii=False, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
