# -*- coding: utf-8 -*-
"""
============================================================
 文章图片压缩工具（可反复使用）
============================================================

【它是干什么的】
  把文章里引用的大图，改成「缩略版」地址，让读者少下载 9 成流量。

【原理】
  文章里的图片大多托管在搜狐图床（q0~q9.itc.cn），它的底层是阿里云 OSS，
  支持在网址后面加参数，让服务器当场缩图 + 转 WebP：
      xxx.jpeg?x-oss-process=image/resize,w_1000/format,webp
  原图不用重新上传、不用换图床，改一行地址就行。
  全站实测：28.74 MB → 11.90 MB（w_1000）；最重的文章 3.19 MB → 0.32 MB。

【怎么用】
  ★ 最省事：双击 tools\3-压缩文章图片.bat，按菜单操作。
  ★ 命令行：
      python scripts/optimize_remote_images.py                 # 预览，不改任何文件
      python scripts/optimize_remote_images.py --apply         # 真正写入（自动备份）
      python scripts/optimize_remote_images.py --verify 10     # 抽查 10 条新链接是否可用
      python scripts/optimize_remote_images.py --restore       # 回滚最近一次压缩
      python scripts/optimize_remote_images.py --apply --width 720 --top 12

【为什么可以放心重复跑】
  · 已经加过参数的地址会自动跳过，不会重复叠加。
  · 内容没变化的文件不会被重写（不会搅乱 git 记录 / 页面更新时间）。
  · 每次写入前自动备份到 _backup/image-opt-时间戳/，并留一份改动清单 manifest.csv。
  · 全程只动 markdown 里的图片地址，不碰正文、不碰 front matter 其它字段。

【零依赖】只用 Python 标准库，不需要装任何东西。
"""

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
import sys
import time
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

# 输出被重定向（管道、写日志）时，Windows 默认用 GBK 编码，
# 遇到 ✅ ❌ 这类 GBK 里没有的字符会直接抛异常把程序打断 —— 这里改成替换，不中断。
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(errors="replace")
    except Exception:
        pass

# ---------------------------------------------------------------- 配置

DEFAULT_WIDTH = 1000     # 缩放目标宽度。正文栏约 730px，1000 兼顾清晰度与流量；
                         # 想更省流量改 800，想更清晰改 1200。
DEFAULT_SAMPLE = 12      # 预览时抽样多少张，用来估算"能省多少"
TIMEOUT = 12             # 单个网络请求超时（秒）
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36"

# 图片地址（图床域名 + 以图片后缀结尾），后面可能已经带了 ?x-oss-process=...
# 用非贪婪 + 反向排除，避免把后面的中文标点、引号、右括号一起吃进来
IMG_RE = re.compile(
    r'(https://q\d\.itc\.cn/[^\s)"\'\]]*?\.(?:jpe?g|png|webp))'
    r'(\?x-oss-process=[^\s)"\']*)?'
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 要扫描的 markdown 位置（相对项目根目录）
SCAN_DIRS = ["_posts", "_tabs"]
SCAN_ROOT_MD = True

# 不参与扫描的目录名
SKIP_DIRS = {"_backup", ".git", ".workbuddy", "node_modules", "_site", "vendor"}


# ---------------------------------------------------------------- 小工具

def hr(char="=", n=66):
    print(char * n)


def human(n):
    """字节数转成人话"""
    if n < 0:
        return "未知"
    if n < 1024:
        return "%d B" % n
    if n < 1024 * 1024:
        return "%.0f KB" % (n / 1024)
    return "%.2f MB" % (n / 1048576)


def build_param(width):
    return "?x-oss-process=image/resize,w_%d/format,webp" % width


def head_size(url, timeout=TIMEOUT):
    """只发 HEAD 拿文件大小；失败返回 -1"""
    try:
        req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return int(r.headers.get("Content-Length") or 0)
    except Exception:
        return -1


def head_probe(url, timeout=TIMEOUT):
    """返回 (状态码, 大小, content-type)"""
    try:
        req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return (r.status, int(r.headers.get("Content-Length") or 0),
                    (r.headers.get("Content-Type") or "").split(";")[0])
    except urllib.error.HTTPError as e:
        return (e.code, -1, "")
    except Exception:
        return (-1, -1, "")


def read_text(path):
    """读文件，记住是否带 BOM（Windows 记事本存过的文件常有）"""
    with open(path, "rb") as f:
        raw = f.read()
    has_bom = raw.startswith(b"\xef\xbb\xbf")
    return raw.decode("utf-8-sig", errors="replace"), has_bom


def write_text(path, text, has_bom):
    """写回文件，保持原来的 BOM 与换行符不变"""
    data = text.encode("utf-8")
    if has_bom:
        data = b"\xef\xbb\xbf" + data
    with open(path, "wb") as f:
        f.write(data)


def file_digest(path):
    with open(path, "rb") as f:
        return hashlib.md5(f.read()).hexdigest()


# ---------------------------------------------------------------- 扫描

def collect_files(root):
    """返回需要扫描的 markdown 文件完整路径列表"""
    files = []
    for d in SCAN_DIRS:
        p = os.path.join(root, d)
        if not os.path.isdir(p):
            continue
        for name in sorted(os.listdir(p)):
            if name.lower().endswith((".md", ".markdown")):
                files.append(os.path.join(p, name))
    if SCAN_ROOT_MD:
        # 根目录散落的 md 只处理「带 front matter、会被发布成网页」的那些，
        # 纯说明文档（部署教程、操作手册之类）不碰。
        for name in sorted(os.listdir(root)):
            if not name.lower().endswith((".md", ".markdown")):
                continue
            p = os.path.join(root, name)
            try:
                with open(p, "rb") as f:
                    head = f.read(8).lstrip(b"\xef\xbb\xbf")
                if head.startswith(b"---"):
                    files.append(p)
            except Exception:
                pass
    return files


def analyze(text, width, upgrade=False):
    """
    分析一段文字，返回:
      new_text     —— 改写后的文字
      todo         —— 本次会被改写的地址列表 [(原地址, 新地址), ...]
      already      —— 已经改过、本次跳过的地址数
    """
    param = build_param(width)
    todo, already = [], []

    def repl(m):
        url, exist = m.group(1), m.group(2)
        if exist:
            if upgrade and exist != param:
                new = url + param
                todo.append((url + exist, new))
                return new
            already.append(url)
            return m.group(0)
        new = url + param
        todo.append((url, new))
        return new

    new_text = IMG_RE.sub(repl, text)
    return new_text, todo, already


def scan(root, width, upgrade=False, top=0):
    """扫描全部文件，返回 [(path, new_text, todo, already, has_bom), ...]"""
    rows = []
    for path in collect_files(root):
        text, bom = read_text(path)
        new_text, todo, already = analyze(text, width, upgrade)
        if todo:
            rows.append({"path": path, "text": text, "new_text": new_text,
                         "todo": todo, "already": already, "bom": bom})
    rows.sort(key=lambda r: (-len(r["todo"]), os.path.basename(r["path"])))
    if top:
        rows = rows[:top]
    return rows


# ---------------------------------------------------------------- 体积测算

def load_cache(root):
    """图片体积缓存：第二次跑就不用再测一遍，秒出结果"""
    p = os.path.join(root, "_backup", ".img-size-cache.json")
    try:
        with open(p, "r", encoding="utf-8") as f:
            return json.load(f), p
    except Exception:
        return {}, p


def save_cache(p, cache):
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as f:
            json.dump(cache, f, ensure_ascii=False)
    except Exception:
        pass


def _bulk_measure(urls, cache, cpath, label):
    """并发测一批地址的体积，结果写进缓存。返回 {url: size}"""
    pending = [u for u in urls if u not in cache]
    if pending:
        print("\n正在测%s（需联网测 %d 张，已缓存 %d 张）..."
              % (label, len(pending), len(urls) - len(pending)))
        done = 0
        with ThreadPoolExecutor(max_workers=16) as ex:
            futs = {ex.submit(head_size, u): u for u in pending}
            for fu in as_completed(futs):
                u = futs[fu]
                try:
                    s = fu.result()
                except Exception:
                    s = -1
                if s > 0:
                    cache[u] = s
                done += 1
                if done % 50 == 0:
                    print("  已测 %d / %d" % (done, len(pending)))
        save_cache(cpath, cache)
    return {u: cache[u] for u in urls if cache.get(u, 0) > 0}


def measure(rows, width=DEFAULT_WIDTH, sample=0, root=ROOT):
    """
    精确测算：原图全部测一遍，压缩后的地址也全部测一遍，给出真实对比。
    体积会缓存到 _backup/.img-size-cache.json，重复运行不再联网。
    """
    urls = []
    for r in rows:
        for old, _new in r["todo"]:
            if old not in urls:
                urls.append(old)
    if not urls:
        return None

    cache, cpath = load_cache(root)
    before = _bulk_measure(urls, cache, cpath, "原图体积")
    if not before:
        print("  网络不通或图床拒绝访问，跳过体积测算。")
        return None

    param = build_param(width)
    new_urls = [u + param if "?" not in u else u for u in before]
    after = _bulk_measure(new_urls, cache, cpath, "压缩后体积")

    pairs = []
    for u in before:
        n = after.get(u + param if "?" not in u else u)
        if n:
            pairs.append((before[u], n))

    total_before = sum(before.values())
    total_after = sum(after.values()) if len(after) == len(before) else None
    return {"unique": len(urls), "measured": len(before), "pairs": len(pairs),
            "total": total_before, "after": total_after}


def print_measure(m):
    if not m:
        return
    print()
    hr("-")
    print("原图总体积：%s（%d 张）" % (human(m["total"]), m["measured"]))
    if m["after"]:
        saved = m["total"] - m["after"]
        pct = saved * 100.0 / m["total"] if m["total"] else 0
        print("压缩后体积：%s" % human(m["after"]))
        print("节省：%s（降 %.0f%%）" % (human(saved), pct))
    elif m["pairs"]:
        ratio = sum(n for _, n in m["pairs"]) / sum(o for o, _ in m["pairs"])
        print("实测降幅约 %.0f%%，压缩后约 %s"
              % ((1 - ratio) * 100, human(int(m["total"] * ratio))))
    hr("-")


# ---------------------------------------------------------------- 写入

def make_backup_dir(root):
    stamp = time.strftime("%Y%m%d-%H%M%S")
    d = os.path.join(root, "_backup", "image-opt-%s" % stamp)
    n = 1
    base = d
    while os.path.exists(d):
        n += 1
        d = "%s-%d" % (base, n)
    os.makedirs(d)
    return d


def apply_changes(root, rows):
    """真正写入：备份 → 改写 → 记录清单"""
    backup = make_backup_dir(root)
    manifest = []
    changed = 0
    for r in rows:
        if r["new_text"] == r["text"]:
            continue
        dst = os.path.join(backup, os.path.basename(r["path"]))
        # 同名文件（如 _posts 与根目录下重名）加序号避免覆盖
        i = 1
        while os.path.exists(dst):
            i += 1
            base, ext = os.path.splitext(os.path.basename(r["path"]))
            dst = os.path.join(backup, "%s-%d%s" % (base, i, ext))
        shutil.copy2(r["path"], dst)
        write_text(r["path"], r["new_text"], r["bom"])
        changed += 1
        for old, new in r["todo"]:
            manifest.append([os.path.basename(r["path"]), os.path.basename(dst), old, new])

    with open(os.path.join(backup, "manifest.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["文章文件", "备份文件", "改动前地址", "改动后地址"])
        w.writerows(manifest)
    return backup, changed, len(manifest)


def restore(root, which=None):
    """从备份回滚。which 为空则用最近一次备份。"""
    bdir = os.path.join(root, "_backup")
    if not os.path.isdir(bdir):
        print("没有找到 _backup 目录，无法回滚。")
        return False
    cands = sorted([d for d in os.listdir(bdir) if d.startswith("image-opt-")])
    if not cands:
        print("没有找到任何 image-opt-* 备份目录。")
        return False
    if which:
        cands = [d for d in cands if which in d] or [cands[-1]]
    target = os.path.join(bdir, cands[-1])
    files = [f for f in os.listdir(target) if f.lower().endswith((".md", ".markdown"))]
    if not files:
        print("备份目录里没有可回滚的文件：%s" % target)
        return False

    # 备份文件名 → 原始路径：_posts 优先，其次 _tabs，最后根目录
    restored = 0
    for name in files:
        for sub in ("_posts", "_tabs", ""):
            src_dir = os.path.join(root, sub) if sub else root
            orig = os.path.join(src_dir, name)
            if os.path.isfile(orig):
                shutil.copy2(os.path.join(target, name), orig)
                restored += 1
                break
        else:
            print("  跳过（找不到原文）：%s" % name)

    print("已从 %s 回滚 %d 个文件。" % (os.path.basename(target), restored))
    return restored > 0


# ---------------------------------------------------------------- 校验

def verify(rows, limit=10):
    """抽查：改后的地址能不能打开、是不是真的变小了"""
    pairs = []
    for r in rows:
        for old, new in r["todo"]:
            pairs.append((old, new))
    if not pairs:
        return
    step = max(1, len(pairs) // limit)
    picks = pairs[::step][:limit]
    print("\n抽查 %d 条链接：" % len(picks))
    bad = 0
    with ThreadPoolExecutor(max_workers=8) as ex:
        results = list(ex.map(lambda p: (p, head_probe(p[1])), picks))
    for (old, new), (code, size, ctype) in results:
        ok = code == 200 and size > 0
        if ok:
            print("  ✅ %-22s %s" % (ctype or "?", human(size)))
        else:
            bad += 1
            print("  ❌ 状态码 %s —— %s" % (code, new))
    if bad:
        print("\n有 %d 条打不开。若全是失败，说明图床参数策略变了，"
              "请立即用「回滚」还原（菜单 4 或 --restore）。" % bad)
    else:
        print("\n全部正常。")


# ---------------------------------------------------------------- 本地图片体检

def image_dimensions(path):
    """不装 Pillow 也能读出 JPEG / PNG 的像素尺寸"""
    try:
        with open(path, "rb") as f:
            head = f.read(32)
            if head[:2] == b"\xff\xd8":                      # JPEG
                f.seek(2)
                while True:
                    b = f.read(1)
                    if not b:
                        return None
                    if b != b"\xff":
                        continue
                    marker = f.read(1)
                    if not marker:
                        return None
                    m = marker[0]
                    if m in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                             0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                        f.read(3)
                        h, w = int.from_bytes(f.read(2), "big"), int.from_bytes(f.read(2), "big")
                        return (w, h)
                    if m in (0xD8, 0xD9) or 0xD0 <= m <= 0xD7:
                        continue
                    seg = int.from_bytes(f.read(2), "big")
                    f.seek(seg - 2, 1)
            elif head[:8] == b"\x89PNG\r\n\x1a\n":           # PNG
                f.seek(16)
                w = int.from_bytes(f.read(4), "big")
                h = int.from_bytes(f.read(4), "big")
                return (w, h)
    except Exception:
        return None
    return None


def check_local(root):
    """体检本地图片：体积大但显示尺寸很小的，列出来提醒"""
    assets = os.path.join(root, "assets")
    if not os.path.isdir(assets):
        return
    tips = []
    for dirpath, dirnames, filenames in os.walk(assets):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if not name.lower().endswith((".jpg", ".jpeg", ".png", ".webp", ".gif")):
                continue
            p = os.path.join(dirpath, name)
            size = os.path.getsize(p)
            if size < 60 * 1024:          # 60 KB 以下不值得折腾
                continue
            dim = image_dimensions(p)
            rel = os.path.relpath(p, root).replace("\\", "/")
            if dim and dim[0] >= 1000:
                tips.append((size, rel, dim))
            elif size > 200 * 1024:
                tips.append((size, rel, dim))

    if not tips:
        print("\n本地图片体检：都很正常，没有需要压缩的大图。")
        return
    print("\n本地图片体检（体积偏大，建议手动压缩）：")
    for size, rel, dim in sorted(tips, reverse=True):
        d = "%d×%d" % dim if dim else "尺寸未知"
        print("  %-46s %-8s %s" % (rel, human(size), d))
    print("  提示：用 https://squoosh.app 或「格式工厂」把长边缩到实际显示尺寸的 2~3 倍即可。")


# ---------------------------------------------------------------- 交互菜单

def do_preview(root, width, top, measure_it=True):
    rows = scan(root, width, top=top)
    if not rows:
        print("\n没有发现需要压缩的图片 —— 全部都已经处理过了。")
        return rows
    print("\n有 %d 篇文章含未压缩图片：" % len(rows))
    for r in rows:
        print("  %3d 处   %s" % (len(r["todo"]), os.path.basename(r["path"])))
    print("\n合计 %d 处引用" % sum(len(r["todo"]) for r in rows))
    if measure_it:
        print_measure(measure(rows, width, root=root))
    return rows


def do_apply(root, width, top, verify_after=True):
    rows = scan(root, width, top=top)
    if not rows:
        print("\n没有需要处理的图片，什么都没改。")
        return
    total = sum(len(r["todo"]) for r in rows)
    print("\n即将修改 %d 篇文章、%d 处图片地址。" % (len(rows), total))
    backup, changed, n = apply_changes(root, rows)
    print("完成：改写 %d 个文件、%d 处地址。" % (changed, n))
    print("备份目录：%s" % backup)
    if verify_after:
        verify(rows, limit=8)
    print("\n下一步：重新部署网站（deploy.bat），然后打开一篇图片多的文章看看速度。")


def menu(root):
    width = DEFAULT_WIDTH
    while True:
        print()
        hr()
        print(" 文章图片压缩工具        当前宽度：w_%d" % width)
        hr()
        print("  1. 预览   —— 看看哪些文章图片没压缩（不改任何文件）")
        print("  2. 压缩   —— 改写文章里的图片地址（自动备份 + 抽查）")
        print("  3. 校验   —— 抽查已压缩的链接能不能打开")
        print("  4. 回滚   —— 撤销最近一次压缩")
        print("  5. 体检   —— 检查本地图片（头像等）是否过大")
        print("  6. 设置   —— 修改压缩宽度（当前 w_%d）" % width)
        print("  0. 退出")
        print()
        try:
            choice = input("请输入序号后回车：").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return

        if choice == "0":
            return
        elif choice == "1":
            do_preview(root, width, top=0)
        elif choice == "2":
            rows = do_preview(root, width, top=0, measure_it=False)
            if not rows:
                continue
            try:
                go = input("\n确认写入吗？输入 Y 回车确认，其它键取消：").strip()
            except (EOFError, KeyboardInterrupt):
                go = ""
            if go.lower() != "y":
                print("已取消，文章没有任何改动。")
                continue
            do_apply(root, width, top=0)
        elif choice == "3":
            rows = scan(root, width, top=0)
            if rows:
                print("\n还有 %d 处没压缩；先校验这些将被改成的地址是否可用：" % len(rows))
                verify(rows, limit=8)
            else:
                print("\n全部已压缩。可以打开网站随便点几篇文章看图是否正常显示。")
        elif choice == "4":
            restore(root)
        elif choice == "5":
            check_local(root)
        elif choice == "6":
            try:
                w = input("请输入宽度（建议 720~1000，直接回车保持 %d）：" % width).strip()
                if w:
                    wi = int(w)
                    if 200 <= wi <= 2000:
                        width = wi
                        print("已设为 w_%d。注意：已改过的图片不会被自动改小，"
                              "需要 --upgrade 才会重写。" % width)
                    else:
                        print("宽度要在 200~2000 之间。")
            except (ValueError, EOFError):
                print("输入无效，保持不变。")
        else:
            print("没有这个选项。")


# ---------------------------------------------------------------- 入口

def main():
    ap = argparse.ArgumentParser(
        description="把文章里的大图换成缩略版地址（可重复运行，自动跳过已处理的）",
        add_help=True)
    ap.add_argument("--apply", action="store_true", help="真正写入（默认只预览）")
    ap.add_argument("--width", type=int, default=DEFAULT_WIDTH, help="缩放宽度，默认 800")
    ap.add_argument("--top", type=int, default=0, help="只处理图片最多的前 N 篇")
    ap.add_argument("--upgrade", action="store_true", help="把已有参数改成本次设定的宽度")
    ap.add_argument("--verify", type=int, nargs="?", const=10, default=0,
                    help="抽查 N 条链接（默认 10）")
    ap.add_argument("--restore", nargs="?", const="", default=None,
                    help="回滚最近一次压缩，可跟备份目录名片段")
    ap.add_argument("--local", action="store_true", help="体检本地图片")
    ap.add_argument("--no-measure", action="store_true", help="预览时跳过体积测算（更快）")
    ap.add_argument("--yes", action="store_true", help="跳过确认（适合放进自动化）")
    ap.add_argument("--root", default=ROOT, help="项目根目录（测试用）")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    if not os.path.isdir(os.path.join(root, "_posts")):
        print("错误：%s 下找不到 _posts 目录，确认是不是项目根目录。" % root)
        return 2

    # 无参数 → 进菜单
    if len(sys.argv) == 1:
        try:
            print()
            print("=" * 66)
            print(" 文章图片压缩工具 —— 双击就能用，随时可停，随时可回滚")
            print("=" * 66)
        except Exception:
            pass
        menu(root)
        return 0

    if args.restore is not None:
        ok = restore(root, args.restore or None)
        return 0 if ok else 1

    if args.local:
        check_local(root)
        return 0

    rows = scan(root, args.width, upgrade=args.upgrade, top=args.top)
    if not rows:
        print("没有需要处理的图片 —— 全部都已经压缩过了。")
        return 0

    total = sum(len(r["todo"]) for r in rows)
    print("发现 %d 篇文章、%d 处未压缩图片。" % (len(rows), total))
    for r in rows[:20]:
        print("  %3d 处   %s" % (len(r["todo"]), os.path.basename(r["path"])))
    if len(rows) > 20:
        print("  ... 另外 %d 篇" % (len(rows) - 20))

    if not args.apply:
        if not args.no_measure:
            print_measure(measure(rows, args.width, sample=args.verify or DEFAULT_SAMPLE, root=root))
        print("\n以上为预览，没有改动任何文件。加 --apply 才会写入。")
        if args.verify:
            verify(rows, limit=args.verify)
        return 0

    if not args.yes:
        try:
            ans = input("\n确认写入吗？输入 Y 回车确认：").strip()
        except (EOFError, KeyboardInterrupt):
            ans = ""
        if ans.lower() != "y":
            print("已取消。")
            return 0

    backup, changed, n = apply_changes(root, rows)
    print("完成：改写 %d 个文件、%d 处地址。" % (changed, n))
    print("备份：%s" % backup)
    if args.verify:
        verify(rows, limit=args.verify)
    return 0


if __name__ == "__main__":
    sys.exit(main())
