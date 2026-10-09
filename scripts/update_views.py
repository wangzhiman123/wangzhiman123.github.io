# -*- coding: utf-8 -*-
"""
抓取每篇文章的真实浏览量，写入 _data/views.json
====================================================================

【原理】不蒜子（busuanzi）按 HTTP Referer 区分页面：
  浏览器打开 /posts/post-046/ 时，页面里的 script 请求
  https://busuanzi.ibruce.info/busuanzi?jsonpCallback=xxx
  这个请求的 Referer 就是 /posts/post-046/，不蒜子据此给该页计数。
  服务端（GitHub Actions）可以任意设置 Referer，所以能逐篇查询。

【必须处理的坑】读取接口 = 计数接口
  「查询」这个动作本身也会让该页计数 +1（实测：连续查询同一页，
  返回的 page_pv 会 3 → 4 → 5 稳定递增）。
  如果每次定时任务都直接取返回值，浏览量会随着运行次数不断虚增。

  因此这里额外维护 _data/pv_state.json，记录每篇文章「已被本脚本查询过几次」：

      真实浏览量 = 接口返回值 - 累计查询次数

  这样无论脚本运行多少次，都不会污染数据。同时文章页里浏览器发出的
  真实访问请求不会被记入 pv_state，所以真实访问量会被完整保留。

【输出】
  _data/views.json     { "/posts/post-001/": 3, ... }   ← 页面真正使用的数据
  _data/pv_state.json  { "/posts/post-001/": 2, ... }   ← 内部账本，勿手动改动

【key 规则】直接用文章 URL 的路径（含首尾斜杠），例如 /posts/post-046/
  与首页 _layouts/home.html 中的 site.data.views[post.url] 完全一致。
"""

import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)

SITE = os.environ.get("SITE_URL", "https://2019527.xyz").rstrip("/")
POSTS_DIR = "_posts"
DATA_DIR = "_data"
VIEWS_FILE = os.path.join(DATA_DIR, "views.json")
STATE_FILE = os.path.join(DATA_DIR, "pv_state.json")
API = "https://busuanzi.ibruce.info/busuanzi?jsonpCallback=BusuanziCb"
MAX_RETRY = 2


def read_front_matter(path):
    """读取 YAML front matter 中的简单字段（避免依赖 pyyaml）"""
    try:
        with open(path, encoding="utf-8") as f:
            head = f.read(4096)
    except Exception:
        return {}
    if not head.startswith("---"):
        return {}
    end = head.find("---", 3)
    if end == -1:
        return {}
    fm = {}
    for line in head[3:end].splitlines():
        m = re.match(r"^\s*([A-Za-z_][\w-]*)\s*:\s*(.+?)\s*$", line)
        if m:
            fm[m.group(1)] = m.group(2).strip().strip("\"'")
    return fm


def slug_of(filename):
    """2026-10-03-post-046.md -> post-046"""
    base = os.path.basename(filename)
    for ext in (".md", ".markdown"):
        if base.endswith(ext):
            base = base[: -len(ext)]
            break
    m = re.match(r"^\d{4}-\d{1,2}-\d{1,2}-(.*)$", base)
    return m.group(1) if m else base


def path_of(file_path, slug):
    """返回文章 URL 路径。优先使用 front matter 里的 permalink。"""
    perm = read_front_matter(file_path).get("permalink")
    if perm:
        return "/" + perm.strip("/") + "/"
    # 与 _config.yml 的 permalink: /posts/:title/ 保持一致
    return "/posts/%s/" % slug


def fetch_page_pv(page_url):
    """请求不蒜子接口，返回该页 page_pv；失败返回 None"""
    last_err = None
    for attempt in range(MAX_RETRY + 1):
        try:
            req = urllib.request.Request(
                API, headers={"User-Agent": UA, "Referer": page_url}
            )
            with urllib.request.urlopen(req, timeout=20) as r:
                txt = r.read().decode("utf-8", "ignore")
            m = re.search(r"\(\s*(\{.*?\})\s*\)", txt, re.S)
            if not m:
                raise ValueError("无法解析返回: %s" % txt[:80])
            data = json.loads(m.group(1))
            pv = data.get("page_pv")
            if isinstance(pv, (int, float)):
                return int(pv)
            raise ValueError("响应中没有 page_pv: %s" % txt[:80])
        except Exception as e:  # noqa: BLE001
            last_err = e
            if attempt < MAX_RETRY:
                time.sleep(1.5)
    print("      失败: %s" % repr(last_err)[:70])
    return None


def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:  # noqa: BLE001
        return {}


def dump_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")


def main():
    if not os.path.isdir(POSTS_DIR):
        print("未找到 %s 目录" % POSTS_DIR)
        return 1

    files = sorted(
        os.path.join(POSTS_DIR, f)
        for f in os.listdir(POSTS_DIR)
        if f.lower().endswith((".md", ".markdown"))
    )
    if not files:
        print("%s 目录下没有文章" % POSTS_DIR)
        return 1

    old_state = load_json(STATE_FILE)
    print("共 %d 篇文章，开始抓取（约需 1~2 分钟）" % len(files))

    views = {}
    state = {}
    ok = fail = 0

    for i, path in enumerate(files, 1):
        slug = slug_of(path)
        url_path = path_of(path, slug)
        page_url = SITE + url_path

        raw = fetch_page_pv(page_url)
        if raw is None:
            # 抓取失败：沿用上一次的数值，避免页面上出现 0 或消失
            fail += 1
            prev_views = load_json(VIEWS_FILE)
            if url_path in prev_views:
                views[url_path] = prev_views[url_path]
            if url_path in old_state:
                state[url_path] = old_state[url_path]
            print("  [%2d/%d] %-16s 抓取失败，沿用旧值" % (i, len(files), slug))
        else:
            # 本次查询会让不蒜子 +1，累计查询次数也要 +1
            polls = int(old_state.get(url_path, 0)) + 1
            true_pv = raw - polls
            if true_pv < 0:
                true_pv = 0
            views[url_path] = true_pv
            state[url_path] = polls
            ok += 1
            print(
                "  [%2d/%d] %-16s 接口=%s  累计查询=%d  →  真实=%d"
                % (i, len(files), slug, raw, polls, true_pv)
            )

        time.sleep(0.4)  # 温和一点，避免被限流

    dump_json(VIEWS_FILE, views)
    dump_json(STATE_FILE, state)

    print()
    print("成功 %d 篇，失败 %d 篇，合计 %d 次浏览" % (ok, fail, sum(views.values())))
    print("已写入 %s / %s" % (VIEWS_FILE, STATE_FILE))
    return 0


if __name__ == "__main__":
    sys.exit(main())
