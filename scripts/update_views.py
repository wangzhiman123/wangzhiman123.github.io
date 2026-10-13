# -*- coding: utf-8 -*-
"""
============================================================================
【本文件是什么？】
抓取每篇文章的真实浏览量，写入 _data/views.json
============================================================================

一句话概括：
  这篇文章是一个「自动数人头的脚本」，每隔几小时由服务器自动运行一次，
  逐篇去问统计服务"这篇文章有多少人看过"，算准之后把数字存进
  _data/views.json 文件。网页在生成时读取这个文件，就把数字直接印在页面上。

整个网站"浏览量"是怎么跑起来的？完整流程：
  ① 访客打开某篇文章 → 网页里的统计小代码向"不蒜子"服务报一次到 → 计数 +1
  ② 定时脚本（本文件）去问不蒜子："各篇文章现在多少浏览量？"
  ③ 脚本把答案做一次修正（原因见下），写进 _data/views.json
  ④ 网站重新构建 → 把 views.json 里的数字静态印到首页卡片和文章页上
  ⑤ 访客看到的就是真实数字，而且打开即可见、不需要等加载、不会转圈

【原理】不蒜子（busuanzi）按 HTTP Referer 区分页面：
  浏览器打开 /posts/post-046/ 时，页面里的 script 请求
  https://busuanzi.ibruce.info/busuanzi?jsonpCallback=xxx
  这个请求的 Referer 就是 /posts/post-046/，不蒜子据此给该页计数。
  服务端（GitHub Actions）可以任意设置 Referer，所以能逐篇查询。
  （Referer 可以理解为"这次访问是从哪个页面来的"，是一个附在请求上的说明。）

【必须处理的坑】读取接口 = 计数接口
  「查询」这个动作本身也会让该页计数 +1（实测：连续查询同一页，
  返回的 page_pv 会 3 → 4 → 5 稳定递增）。
  如果每次定时任务都直接取返回值，浏览量会随着运行次数不断虚增。
  （打个比方：这本账没有单独的"查看"功能，你每翻看一次账本，
   账本自己就多记一笔；所以看一次就得自己心里减掉一次。）

  因此这里额外维护 _data/pv_state.json，记录每篇文章「已被本脚本查询过几次」：

      真实浏览量 = 接口返回值 - 累计查询次数

  这样无论脚本运行多少次，都不会污染数据。同时文章页里浏览器发出的
  真实访问请求不会被记入 pv_state，所以真实访问量会被完整保留。

【输出】
  _data/views.json     { "/posts/post-001/": 3, ... }   ← 页面真正使用的数据
  _data/pv_state.json  { "/posts/post-001/": 2, ... }   ← 内部账本，勿手动改动
  （为什么要两个文件？views.json 是"给读者看的最终数字"，
   pv_state.json 是"防止自己把自己数进去的纠错记录"，两者分开更清晰。）

【key 规则】直接用文章 URL 的路径（含首尾斜杠），例如 /posts/post-046/
  与首页 _layouts/home.html 中的 site.data.views[post.url] 完全一致。
  （key = 编号/索引。这里用文章网址当编号，两边对得上才能取到数字。）
"""

# ---------------------- 第一部分：引入需要用到的工具包 ----------------------
# 这些是 Python 自带的工具箱，不需要额外安装任何东西。

import json                      # 用来读写 .json 文件（一种"键值对"格式的文本文件）
import os                        # 用来处理文件路径、目录、读取环境变量
import re                        # 正则表达式：用来按"规律"从一堆文字里挑出想要的部分
import sys                        # 用来设置脚本的退出状态码
import time                      # 用来做"等待几秒再继续"，避免请求太密集
import urllib.parse              # 用来处理网址的拆分与拼接
import urllib.request            # 用来向外部网站发起网络请求（也就是"去问数据"）


# ---------------------- 第二部分：全局配置（可修改的地方集中在这里） ----------------------

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)
# UA = User-Agent，可以理解为"报给网站的浏览器身份"。
# 【为什么要设置它？】有些网站（包括统计服务）对"看起来不像浏览器的请求"会比较警惕、
# 直接拒绝。所以这里把自己伪装成常见的 Chrome 浏览器，避免被拦下。
# 【可DIY修改】一般不需要改。如果哪天接口开始拒绝，可以换成更新的浏览器版本字符串。

SITE = os.environ.get("SITE_URL", "https://2019527.xyz").rstrip("/")
# 网站地址。
# os.environ.get(...) 的意思是"先去系统环境变量里找 SITE_URL"；
# 找到就用配置的那个，找不到就用后面那个默认值 https://2019527.xyz。
# 这样写的好处：在 GitHub Actions 里可以灵活换域名，不用改代码。
# .rstrip("/") 把结尾多余的斜杠去掉，保证后面拼网址时不会出现两个斜杠。
# 【可DIY修改】换成您的域名时，改这个默认值即可。

POSTS_DIR = "_posts"
# 文章存放的文件夹名。

DATA_DIR = "_data"
# 数据文件存放的文件夹名。

VIEWS_FILE = os.path.join(DATA_DIR, "views.json")
# 最终数据文件的完整路径，实际是 _data/views.json。
# os.path.join 是用来拼路径的，它会自动适配 Windows 和 Mac/Linux 的不同斜杠写法。

STATE_FILE = os.path.join(DATA_DIR, "pv_state.json")
# 内部账本文件的完整路径：_data/pv_state.json。

API = "https://busuanzi.ibruce.info/busuanzi?jsonpCallback=BusuanziCb"
# 要查询的那个统计接口地址。
# jsonpCallback=BusuanziCb 是接口要求的固定写法（告诉服务端"数据请用这种格式返回"）。

MAX_RETRY = 2
# 单篇文章查询失败时，最多再重试几次。
# 【可DIY修改】网络不太稳定可以调到 3；想跑快一点可以调到 0（不重试，失败就沿用旧值）。


# ========================== 第三部分：各个功能函数 ==========================
# 下面每个 def 都是一段"有专门用途的小工具"，主流程里按顺序调用它们。

def read_front_matter(path):
    """读取 YAML front matter 中的简单字段（避免依赖 pyyaml）"""
    # front matter = 文章文件开头那两个 --- 之间的一小段说明，
    # 里面写着标题、日期、网址等基本信息。
    # 之所以不引入 pyyaml 这个现成的解析库，是为了减少依赖——
    # 项目里只需要读几个简单字段，自己写十几行就够了，不用额外装包。

    try:
        with open(path, encoding="utf-8") as f:
            head = f.read(4096)
        # 打开文件，只读开头 4096 个字符。
        # 【为什么只读这么多？】文章正文可能很长，而我们只要开头的说明部分，
        # 只读一小段能让脚本跑得快很多（好几十篇文章，累计能省不少时间）。
    except Exception:
        return {}
    # 万一文件打不开（不存在、没权限等），就返回一个空信息，不让脚本崩掉。

    if not head.startswith("---"):
        return {}
    # 开头不是 --- 说明这篇文章没有写 front matter，返回空的即可。

    end = head.find("---", 3)
    # 从第 4 个字符开始找第二个 ---，它标记着说明部分的结束位置。

    if end == -1:
        return {}
    # 找不到第二个 ---，说明格式不完整，返回空的。

    fm = {}
    # 准备一个空的信息表，用来存解析出来的字段。

    for line in head[3:end].splitlines():
        # 把两个 --- 之间的内容按行拆开，一行一行看。
        m = re.match(r"^\s*([A-Za-z_][\w-]*)\s*:\s*(.+?)\s*$", line)
        # 用一条"规律"去匹配这一行的格式：字段名 : 值。
        # 这条规律的意思大致是：
        #   开头可以有空格 → 字段名（字母或下划线开头）→ 冒号 → 值 → 结尾。
        # re 就是"按规律找文字"的工具。
        if m:
            fm[m.group(1)] = m.group(2).strip().strip("\"'")
            # m.group(1) 是冒号前面的字段名，m.group(2) 是冒号后面的值。
            # strip() 去掉两边空格；strip("\"'") 再去掉两边的引号。
            # 例如读到 permalink: "/posts/hello/" 会存成 permalink → /posts/hello/
    return fm
    # 返回收集到的信息表。


def slug_of(filename):
    """2026-10-03-post-046.md -> post-046"""
    # 这个函数的作用：从文章文件名里提取出"文章代号"。
    # 比如文件叫 2026-10-03-post-046.md，代号就是 post-046。

    base = os.path.basename(filename)
    # 只取文件名部分，去掉前面的文件夹路径。

    for ext in (".md", ".markdown"):
        if base.endswith(ext):
            base = base[: -len(ext)]
            break
    # 把结尾的 .md 或 .markdown 后缀切掉，只留下文件名主干。

    m = re.match(r"^\d{4}-\d{1,2}-\d{1,2}-(.*)$", base)
    # 用规律匹配"4位数字-数字-数字-剩下的内容"这个格式，
    # 也就是把开头的日期部分识别出来。
    return m.group(1) if m else base
    # 如果能识别出日期格式，就只返回日期后面那部分（post-046）；
    # 如果文件名格式不标准，就原样返回，保证不会出错。


def path_of(file_path, slug):
    """返回文章 URL 路径。优先使用 front matter 里的 permalink。"""
    # 这个函数的作用：算出这篇文章在网站上的访问地址。
    # 这个地址非常重要——它同时是浏览量数据的"编号"，
    # 一旦算错，就取不到浏览量数字。

    perm = read_front_matter(file_path).get("permalink")
    # 先看文章开头有没有单独指定 permalink（固定网址）。

    if perm:
        return "/" + perm.strip("/") + "/"
        # 有指定就按指定的来：去掉两端多余的斜杠，再统一在前后各加一个斜杠。
        # 例如填的是 /my-page 或 my-page，最终都会变成 /my-page/。

    # 与 _config.yml 的 permalink: /posts/:title/ 保持一致
    return "/posts/%s/" % slug
    # 没有单独指定，就用总配置里的统一规则：/posts/ + 文章代号 + /
    # 例如 /posts/post-046/
    # 【重要】这里的格式必须和 _config.yml 里的 permalink 设置一模一样，
    # 否则算出来的地址和网页实际地址对不上，数字就显示不出来。


def fetch_page_pv(page_url):
    """请求不蒜子接口，返回该页 page_pv；失败返回 None"""
    # 这个函数的作用：向统计服务询问"这个页面被看了多少次"。
    # 返回 None 表示这次没问成功（不是 0 次，而是"没问到"）。

    last_err = None
    # 用来记住最后一次的错误原因，方便失败时打印出来排查。

    for attempt in range(MAX_RETRY + 1):
        # 最多尝试 MAX_RETRY + 1 次（第一次 + 重试 MAX_RETRY 次）。
        # 【为什么要重试？】网络偶尔抖动很常见，重试一两次通常就成功了，
        # 比整篇抓取失败、显示旧数字要好。
        try:
            req = urllib.request.Request(
                API, headers={"User-Agent": UA, "Referer": page_url}
            )
            # 组装一个网络请求，里面带上两个关键说明：
            #   User-Agent —— 装作浏览器（见前面的 UA 说明）；
            #   Referer    —— 【最关键的一项】声明"这次访问来自哪个页面"。
            #                统计服务正是靠它来区分不同文章的，所以它必须
            #                设成这篇文章自己的地址，不能漏、不能错。
            with urllib.request.urlopen(req, timeout=20) as r:
                # 发出请求。timeout=20 表示最多等 20 秒，超时就放弃，
                # 避免网络卡住时整个脚本一直干等。
                txt = r.read().decode("utf-8", "ignore")
                # 把对方返回的内容读出来，转成文字。
                # errors="ignore" 表示遇到读不懂的字符就忽略掉，不让它报错中断。

            m = re.search(r"\(\s*(\{.*?\})\s*\)", txt, re.S)
            # 返回的内容外面包了一层括号（形如 xxx({...})），
            # 这条规律的作用是把里面那段真正有用的数据（大括号包着的部分）挑出来。
            if not m:
                raise ValueError("无法解析返回: %s" % txt[:80])
                # 挑不出来说明返回格式不对，主动报个错触发重试。
                # txt[:80] 只打印前 80 个字符，避免日志刷屏。
            data = json.loads(m.group(1))
            # 把挑出来的文字转成 Python 能看懂的数据结构。
            pv = data.get("page_pv")
            # 从数据里取出 page_pv 这个字段，也就是"页面浏览量"。
            if isinstance(pv, (int, float)):
                # 确认它确实是个数字（整数或小数）。这一步是防呆检查，
                # 万一对方返回的不是数字，我们就不会被误导。
                return int(pv)
                # 转成整数返回（浏览量不可能是小数）。
            raise ValueError("响应中没有 page_pv: %s" % txt[:80])
            # 没有这个字段也报错、触发重试。
        except Exception as e:  # noqa: BLE001
            last_err = e
            # 记下这次失败的原因。
            if attempt < MAX_RETRY:
                time.sleep(1.5)
                # 如果还有重试机会，就等 1.5 秒再试下一次。
                # 【为什么要等？】连着猛敲同一个接口容易被当成恶意请求而被限制，
                # 稍微缓一下更礼貌、成功率也更高。
    print("      失败: %s" % repr(last_err)[:70])
    # 重试都用完了还是不行，打印一行提示（截断到 70 个字符，避免太长的报错刷屏）。
    return None
    # 返回 None，告诉主流程"这篇没问到"。


def load_json(path):
    """读取 JSON 文件"""
    # 一个小工具：把 .json 文件读进来变成 Python 的数据结构。
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
        # 读出来的东西必须是个"键值对表"才有用；万一是别的东西，就当空表处理。
    except Exception:  # noqa: BLE001
        return {}
    # 文件不存在、内容损坏等各种情况，统一返回空表。
    # 【为什么这么宽容？】第一次运行时这两个文件本来就不存在，
    # 返回空表能让流程顺畅地继续，而不是一上来就报错退出。


def dump_json(path, data):
    """写入 JSON 文件"""
    # 一个小工具：把数据存成 .json 文件。
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # 确保要保存的文件夹存在；不存在就自动创建。
    # exist_ok=True 表示"如果已经存在就别报错"，重复运行也不会出问题。
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
        # 把数据写进文件，三个设置的用处：
        #   ensure_ascii=False —— 中文直接写中文，不转成乱码般的转义符，方便您查看；
        #   indent=2           —— 每层缩进 2 个空格，文件打开后整整齐齐；
        #   sort_keys=True     —— 按编号排序，这样每次生成的文件顺序稳定，
        #                         方便对照前后差异（比如看这周涨了多少浏览）。
        f.write("\n")
        # 在文件末尾补一个换行符，这是文本文件的良好习惯
        # （有些比对工具会因为"最后少一个换行"而显示整份文件都变了）。


def main():
    """主流程"""
    # 整个脚本的"总指挥"，按顺序把上面那些小工具串起来用。

    if not os.path.isdir(POSTS_DIR):
        print("未找到 %s 目录" % POSTS_DIR)
        return 1
    # 检查文章文件夹是否存在。不存在就提示并返回 1（表示出错），
    # 避免后面在错误的目录里空跑。

    files = sorted(
        os.path.join(POSTS_DIR, f)
        for f in os.listdir(POSTS_DIR)
        if f.lower().endswith((".md", ".markdown"))
    )
    # 把文章文件夹里的文件列出来，只保留 .md / .markdown 结尾的（也就是真正的文章），
    # 然后排序。排序是为了让每次运行时处理顺序一致，输出结果看着稳定。
    # （文件夹里可能还有 .placeholder 这类占位文件，这一步会把它们过滤掉。）

    if not files:
        print("%s 目录下没有文章" % POSTS_DIR)
        return 1
    # 一篇文章都没有就提示并退出，防止生成一份空数据把原有浏览量覆盖掉。

    old_state = load_json(STATE_FILE)
    # 读出上一次的"内部账本"，里面记着每篇文章已经被查询过多少次。
    # 这是纠错的关键依据，必须用"旧账本"，不能用新的。

    print("共 %d 篇文章，开始抓取（约需 1~2 分钟）" % len(files))
    # 打印一行进度提示，让看日志的人心里有数。

    views = {}
    # 准备一份新的"给读者看的数字"表。
    state = {}
    # 准备一份新的"内部账本"。
    # 【注意】这里都新建空的，然后一篇篇填进去，
    # 而不是在旧数据上修修补补，这样逻辑更清晰、也不容易出错。

    ok = fail = 0
    # 两个计数器：分别记录成功了几篇、失败了几篇。

    for i, path in enumerate(files, 1):
        # 逐篇处理。enumerate(..., 1) 的意思是"额外给每篇编个号，从 1 开始"，
        # 编号只用来打印进度，不影响别的。
        slug = slug_of(path)
        # 算出文章代号，例如 post-046。
        url_path = path_of(path, slug)
        # 算出这篇文章在网站上的地址路径，例如 /posts/post-046/。
        # 这个路径就是它在数据文件里的"编号"。
        page_url = SITE + url_path
        # 拼出完整网址，例如 https://2019527.xyz/posts/post-046/。
        # 这个完整网址就是待会儿要告诉统计服务的 Referer。

        raw = fetch_page_pv(page_url)
        # 去问统计服务："这个页面多少次浏览量？"
        if raw is None:
            # 抓取失败：沿用上一次的数值，避免页面上出现 0 或消失
            # 【为什么这么做？】网络偶尔出问题很正常，
            # 如果失败就写 0，页面上会突然变成"0 次浏览"，看着像网站坏了；
            # 沿用旧值则最多是数字暂时没涨，体验更好。
            fail += 1
            prev_views = load_json(VIEWS_FILE)
            # 把上一次的数据文件读进来。
            if url_path in prev_views:
                views[url_path] = prev_views[url_path]
                # 旧的浏览量数字原样搬过来。
            if url_path in old_state:
                state[url_path] = old_state[url_path]
                # 旧的账本记录也原样搬过来（保持账目连续）。
            print("  [%2d/%d] %-16s 抓取失败，沿用旧值" % (i, len(files), slug))
            # 打印一行说明：第几篇、哪篇文章、发生了什么。
            # %-16s 的意思是"占 16 个字符宽、左对齐"，让输出对齐好看。
        else:
            # 本次查询会让不蒜子 +1，累计查询次数也要 +1
            # 【这一小段是全文件最核心的两行，务必理解】
            polls = int(old_state.get(url_path, 0)) + 1
            # polls = "累计被本脚本查询过的次数"。
            # 取旧账本里的记录（没有就当作 0），然后 +1 表示"这次又查了一遍"。
            true_pv = raw - polls
            # 【纠错公式】真实浏览量 = 接口现在给的数字 − 累计查询次数。
            # 原理：因为"看一次账本就多记一笔"，所以要把自己看的那几眼减掉，
            # 剩下才是访客真实访问的次数。
            # 举例：接口显示 7，这个脚本前后查过 3 次 → 真实浏览量 7 − 3 = 4。
            if true_pv < 0:
                true_pv = 0
            # 兜底：万一算出来是负数（例如之前账本记录不准、或接口数据被重置），
            # 就让最小值是 0，页面上不会出现"-1 次浏览"这种荒唐数字。
            views[url_path] = true_pv
            # 把算好的真实数字存进"给读者看的表"。
            state[url_path] = polls
            # 把更新后的查询次数存进"内部账本"，供下次运行使用。
            ok += 1
            # 成功计数器 +1。
            print(
                "  [%2d/%d] %-16s 接口=%s  累计查询=%d  →  真实=%d"
                % (i, len(files), slug, raw, polls, true_pv)
            )
            # 打印一行详细记录，把"接口给的原始值""累计查询次数""算出的真实值"
            # 都写出来。这样以后要是数字看着不对，一眼就能看出是哪一步的问题。

        time.sleep(0.4)  # 温和一点，避免被限流
        # 每处理完一篇就歇 0.4 秒。
        # 【为什么要歇？】短时间内密集请求容易被服务方当成攻击而临时封禁，
        # 慢一点更稳妥。50 篇文章大约多花 20 秒，完全值得。
        # 【可DIY修改】想跑快些可改成 0.2；如果发现被抓取方限制了，就调到 0.8 更稳。

    dump_json(VIEWS_FILE, views)
    # 把整理好的浏览量数据写入 _data/views.json —— 这是网页真正要读的文件。
    dump_json(STATE_FILE, state)
    # 把内部账本写入 _data/pv_state.json —— 供下次运行纠错使用。
    # 【重要提醒】这个文件请不要手工修改，否则纠错公式会算错。

    print()
    # 空一行，让最后的汇总信息更容易被看见。
    print("成功 %d 篇，失败 %d 篇，合计 %d 次浏览" % (ok, fail, sum(views.values())))
    # 打印总结：成功几篇、失败几篇、全站总浏览量。
    # sum(views.values()) 是把所有文章的数字加起来。
    print("已写入 %s / %s" % (VIEWS_FILE, STATE_FILE))
    # 告知两个文件都已保存好。
    return 0
    # 返回 0 表示"一切正常"（这是程序界的通用约定：0 = 成功）。


if __name__ == "__main__":
    # 这个判断的意思是："只有当本文件被当作脚本直接运行时，才执行下面的代码"。
    # 【为什么要写它？】万一以后有别的脚本 import 本文件借用里面的函数，
    # 就不会误触发整个抓取流程。
    sys.exit(main())
    # 运行主流程，并把它的结果（0 或 1）作为脚本的退出状态。
    # 这样自动化系统（比如 GitHub Actions）能判断本次任务是否成功。
