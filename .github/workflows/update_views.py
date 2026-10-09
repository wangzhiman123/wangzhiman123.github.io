# -*- coding: utf-8 -*-
"""
从「不蒜子」按篇抓取文章浏览量，写入 _data/views.json

原理：
  不蒜子按 HTTP Referer 区分页面。浏览器里列表页无法伪造 Referer（这也是
  首页卡片拿不到每篇计数的原因），但 GitHub Actions 是服务端环境，可以
  任意设置 Referer，因此能逐篇查询真实计数。

  注意：请求本身会让该篇计数 +1，所以写入时统一减 1，抵消自身贡献。

输出：_data/views.json
  key 规则 = 文章 url 去掉所有斜杠，例如 /posts/post-046/ -> postspost-046
  （与 _layouts/home.html 里的 `post.url | remove: '/'` 保持一致）
"""

import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

SITE = os.environ.get("SITE_URL", "https://2019527.xyz").rstrip("/")
POSTS_DIR = "_posts"
OUT_FILE = os.path.join("_data", "views.json")
API = "https://busuanzi.ibruce.info/busuanzi?jsonpCallback=BusuanziCb"
MAX_RETRY = 2


def read_front_matter(path):
    """读取 YAML front matter（只取需要的简单字段，避免依赖 pyyaml）"""
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


def url_of(path, slug):
    """优先用文章自定义的 permalink，否则按 Chirpy 默认 /posts/<slug>/"""
    fm = read_front_matter(path)
    perm = fm.get("permalink")
    if perm:
        p = perm.strip("/")
        return "%s/%s/" % (SITE, p)
    return "%s/posts/%s/" % (SITE, slug)


def fetch_pv(page_url):
    """请求不蒜子接口，返回该页 page_pv；失败返回 None"""
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
            return int(pv) if isinstance(pv, (int, float)) else None
        except Exception as e:
            if attempt >= MAX_RETRY:
                print("    失败: %s" % repr(e)[:70])
                return None
            time.sleep(1.5)
    return None


def main():
    if not os.path.isdir(POSTS_DIR):
        print("未找到 %s 目录" % POSTS_DIR)
        return 1

    files = sorted(
        os.path.join(POSTS_DIR, f)
        for f in os.listdir(POSTS_DIR)
        if f.lower().endswith((".md", ".markdown"))
    )
    print("共 %d 篇文章，开始抓取（约需 1~2 分钟）" % len(files))

    views = {}
    ok = fail = 0

    for i, path in enumerate(files, 1):
        slug = slug_of(path)
        page_url = url_of(path, slug)
        key = urllib.parse.urlparse(page_url).path.strip("/").replace("/", "")
        # key 也可直接由 url 去掉斜杠得到，这里与页面端 `remove: '/'` 对齐
        key = page_url.replace(SITE, "").replace("/", "")

        pv = fetch_pv(page_url)
        if pv is None:
            fail += 1
            print("  [%2d/%d] %-16s 抓取失败，跳过" % (i, len(files), slug))
        else:
            # 抵消本次请求自身的 +1
            val = pv - 1
            if val < 0:
                val = 0
            views[key] = val
            ok += 1
            print("  [%2d/%d] %-16s %s -> %d" % (i, len(files), slug, pv, val))

        time.sleep(0.4)  # 温和一点，避免被限流

    os.makedirs("_data", exist_ok=True)
    with open(OUT_FILE, "w", encoding="utf-8") as f:
        json.dump(views, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")

    total = sum(views.values())
    print()
    print("成功 %d 篇，失败 %d 篇，合计 %d 次浏览" % (ok, fail, total))
    print("已写入 %s" % OUT_FILE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
