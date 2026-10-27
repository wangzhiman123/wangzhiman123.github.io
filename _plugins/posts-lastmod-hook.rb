#!/usr/bin/env ruby
#
# ============================================================================
# 【本文件是什么？】
# Check for changed posts（检查文章是否被修改过）
# ----------------------------------------------------------------------------
# 这是一个 Ruby 语言写的「小插件」，Jekyll（网站生成程序）在构建网站时会自动
# 加载并执行它。
#
# 它的作用只有一件事：自动算出每篇文章的「最后修改时间」。
# 效果是：文章页上除了"发布于 2026-10-03"之外，如果这篇内容后来改过，
# 还会自动多显示一行"更新于 2026-10-10"，让读者知道内容有更新。
#
# 为什么用 Git 自动算、不手动写？
#   手动写容易忘、也容易写错。而每次提交修改时，Git（版本管理工具，
#   可以理解为"给文件拍快照的记事本"）都会记录下时间，
#   这里就是去问 Git ——"这个文件被改过几次？最后一次是什么时候？"
#
# 只在"确实改过"时才显示更新时间：
#   刚创建的文章只提交过 1 次，不算修改，不显示"更新于"，页面更干净。
#
# ----------------------------------------------------------------------------
# 【2026-10-27 性能改造 —— 为什么改】
# 老写法是在 :posts / :post_init 钩子里，对每篇文章分别执行 1~2 条 git 命令：
#     git rev-list --count HEAD "文章路径"      ← 每篇 1 次
#     git log -1 --pretty=... "文章路径"        ← 改过的文章再 1 次
# 本站有 51 篇文章，于是一次构建要 fork 出 51~102 个 git 子进程。
# 每个子进程在 Windows 上要 50~100 毫秒，光这一项就让构建多花 5~10 秒；
# 更麻烦的是：在没有 .git 的目录（比如本地解压一份源码来试）里，
# 这 51 条命令全部失败，终端会刷满 51 行
#     fatal: not a git repository (or any of the parent directories): .git
# 看起来像网站坏了，实际只是"没有 Git 历史可查"。
#
# 新写法只做两件事：
#   ① 整个仓库只跑【一次】git log，一次拿回"所有文章的修改次数 + 最后修改时间"；
#   ② 先判断是不是 Git 仓库，不是就安静跳过（不报错、不刷屏）。
# 结果：子进程从 51~102 个降到 1 个，构建快了几秒，日志也干净了。
# 「更新于」的显示逻辑和判定条件（改过 ≥1 次才显示）与老版本完全一致。
# ============================================================================

require 'open3'

# :site / :post_read 表示"等所有文章都读完、还没开始渲染页面时"执行一次。
# 之所以用这个时机，是因为这时才能一次看到全部文章、只跑一条 git 命令。
Jekyll::Hooks.register :site, :post_read do |site|
  # 取出本站全部文章（_posts 目录下的每一篇）
  posts = site.posts.docs
  next if posts.empty?

  # 先在文章路径和 Git 记录的路径之间建立一张对照表。
  # Git 输出的路径形如 "_posts/2026-09-29-post-001.md"，
  # 正常情况下和 post.path 完全一样；万一站点根目录不是仓库根目录，
  # 就退回用文件名匹配，两种都能对上。
  by_path = {}
  by_name = {}
  posts.each do |post|
    by_path[post.path] = post
    by_name[File.basename(post.path)] = post
  end

  # 一次拿到整个历史里"每个 commit 改了哪些文章、这个 commit 是什么时间"。
  #   %x01          —— 每条记录开头打一个不可见的分隔符，方便下面切分
  #   %ad --date=iso —— 提交的作者日期，国际标准格式（与老版本一致）
  #   --name-only    —— 顺便列出这次提交涉及的文件名
  #   -- _posts      —— 只看 _posts 目录，避免翻其它文件、拖慢速度
  cmd = ['git', '-C', site.source, 'log',
         '--format=%x01%ad', '--date=iso', '--name-only', '--', '_posts']

  out = nil
  begin
    out, err, status = Open3.capture3(*cmd)
    # 不是 Git 仓库、或者电脑上根本没装 Git —— 安静跳过。
    # 效果：文章不显示"更新于"，其余功能一切正常，终端不再刷屏。
    next unless status.success?
  rescue StandardError
    # 连 git 命令都起不来（极少见），同样安静跳过
    next
  end
  next if out.nil? || out.empty?

  # 切分并统计。Git 的日志是"从新到旧"排的，
  # 所以第一次遇到某个文件时的那个日期，就是它最后一次被修改的时间。
  commits = Hash.new(0)   # 文件名 => 被改过多少次
  last_at = {}            # 文件名 => 最后一次修改时间

  out.split("\x01").each do |block|
    lines = block.split("\n").map(&:strip).reject(&:empty?)
    next if lines.empty?

    date = lines.shift                       # 第一行是这个 commit 的时间
    lines.each do |path|
      commits[path] += 1
      last_at[path] ||= date                 # 只记第一条（最新的一条）
    end
  end

  # 把结果写回每篇文章
  commits.each do |path, num|
    # 改过 1 次 = 只有创建时那一次提交，不算"修改过"，跳过
    next if num <= 1

    post = by_path[path] || by_name[File.basename(path)]
    next unless post

    # 页面模板（_layouts/post.html）读取这个字段来显示"更新于 xxx"
    post.data['last_modified_at'] = last_at[path]
  end
end
