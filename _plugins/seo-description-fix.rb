# frozen_string_literal: true

# ============================================================================
# 本文件是什么？
# ----------------------------------------------------------------------------
# 修复「分享卡片只有标题和图片、没有描述文字」的问题。
#
# 【问题根源】
#   jekyll-seo-tag 从 2.9 版起，把 OG 的描述标签和 Twitter 的描述标签
#   合并写进了同一个 <meta>：
#       <meta name="twitter:description" property="og:description" content="…" />
#   而 og:title、og:image 仍然是各自独立的标签。
#
#   微信、QQ 这类抓取器在解析时按 name 建索引，看到 name="twitter:description"
#   就当成 Twitter 的字段处理，于是 og:description 相当于"不存在"。
#   表现出来的现象正好是：分享出去有标题、有图，唯独没有那行描述文字。
#   （页面里的 <meta name="description"> 虽然还在，但它不参与分享卡片的渲染。）
#
# 【本文件做什么】
#   在页面 HTML 全部渲染完成之后、写入磁盘之前，把这个合并标签拆成两个
#   独立的、属性顺序符合 OG 规范的标准标签：
#       <meta property="og:description" content="…" />
#       <meta name="twitter:description" content="…" />
#
# 【为什么用插件，而不是改模板】
#   这一行是 jekyll-seo-tag 在 gem 内部生成的，项目里没有对应的模板文件可改。
#   在 _includes/metadata-hook.html 里补一个 og:description 也不行——
#   那是在原标签之后"再追加一个"，同一页面会出现两个描述标签，
#   抓取器取哪一个反而更不确定。用 Hook 直接替换，页面里始终只有一套规范标签。
#
# 【生效条件】
#   需要 Jekyll 正常加载 _plugins 目录。本项目用 GitHub Actions 自己执行
#   `bundle exec jekyll b`，插件会生效（项目里已有的 posts-lastmod-hook.rb
#   就是这么工作的）。
#   ⚠️ 如果将来改回 "GitHub Pages 默认构建"，自定义插件会被禁用，本修复随之失效。
#
# 【怎么停用】
#   删掉本文件，或在文件名前加下划线以外的方式移出 _plugins 目录即可，
#   站点其余功能不受影响（只是分享卡片又会变回没有描述）。
# ============================================================================

Jekyll::Hooks.register :site, :post_render do |site|
  # 匹配合并标签。用命名分组把描述正文单独取出来。
  # 属性之间允许任意空白，兼容不同版本可能出现的换行/缩进差异。
  merged_tag = %r{
    <meta\s+
    name="twitter:description"\s+
    property="og:description"\s+
    content="(?<desc>.*?)"\s*/?>
  }mx

  # 页面（index.html、about 等 tab 页）与文档（_posts 里的文章）都要处理
  targets = site.pages.dup
  targets.concat(site.documents) if site.respond_to?(:documents)

  targets.each do |doc|
    next unless doc.respond_to?(:output) && doc.output.is_a?(String)
    # 快速跳过：没有这个标签的页面（如 sitemap.xml、feed.xml）直接不放正则
    next unless doc.output.include?('name="twitter:description"')

    doc.output = doc.output.gsub(merged_tag) do
      desc = Regexp.last_match[:desc]
      # 拆成两个标签：og 在前（多数抓取器按顺序取第一个匹配项）
      %(<meta property="og:description" content="#{desc}" />) +
        %(<meta name="twitter:description" content="#{desc}" />)
    end
  end
end
