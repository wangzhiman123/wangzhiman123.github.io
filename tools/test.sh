#!/usr/bin/env bash
#
# ============================================================================
# 【本文件是什么？】
# Build and test the site content
# 【中文】构建网站 + 自动体检（检查链接有没有坏的）
#
# ----------------------------------------------------------------------------
# 一句话概括：这是一个"上线前自检工具"。
# 它会先把网站完整编译一遍，然后自动检查所有站内链接、
# 图片引用等有没有问题，有问题就列出来。
#
# 【什么时候该用它？】
#   · 发布前想确认一下"这次改动有没有弄坏什么"；
#   · 改过配置、主题文件之后，想验证网站是否还能正常构建；
#   · 感觉某个页面链接点不开，想批量查一遍。
# 好处：在您自己的电脑上就能发现问题，不必等上线后才被访客撞见。
#
# Requirement: html-proofer, jekyll
# 前置条件：电脑上要能运行 jekyll 和 htmlproofer 这两个工具
# （正常情况下装好项目依赖就有了，不用单独操心）。
#
# Usage: See help information
# 用法：见帮助信息（执行 bash tools/test.sh -h）
# ============================================================================

set -eu
# 脚本安全模式：
#   -e = 任何一步出错就立刻停止；
#   -u = 用到没定义的变量时报错。
# 【注意】这里没有 -o pipefail，和 deploy 里的那些脚本略有不同，
# 属于原作者的习惯差异，不影响使用。

SITE_DIR="_site"
# 编译产物的存放目录。执行完本脚本后，生成的网页就在这个文件夹里。

_config="_config.yml"
# 使用的配置文件。默认是项目根目录的总配置文件。

_baseurl=""
# 网站子路径，先设为空。
# 【它是干什么的？】如果网站放在类似 /blog/ 这样的子目录下，这个值就不为空。
# 本项目放在域名根目录，所以是空的。下面会自动从配置里读出来，不用您手填。

help() {
  # 显示用法说明的小工具。
  echo "Build and test the site content"
  echo
  echo "Usage:"
  echo
  echo "   bash $0 [options]"
  # $0 在这里代表本脚本的路径，所以这句话会显示成"bash tools/test.sh [选项]"。
  echo
  echo "Options:"
  echo '     -c, --config   "<config_a[,config_b[...]]>"    Specify config file(s)'
  echo "     -h, --help               Print this information."
  # 两个选项的含义：
  #   -c, --config "<配置文件>"  指定用哪个配置文件，
  #        支持一次指定多个、用逗号隔开（后面会按顺序读取）；
  #   -h, --help                  显示这份帮助。
}

read_baseurl() {
  # 定义一个"从配置里读取网站子路径"的函数。
  # 【为什么要单独写成函数？】因为下面有两种情况（单配置、多配置）都要用到，
  # 抽出来复用更清晰。
  if [[ $_config == *","* ]]; then
    # 情况一：您指定了多个配置文件（内容里含逗号）。
    # multiple config
    IFS=","
    # 临时把"分隔符"设成逗号。
    # IFS 是 bash 用来切分文字的符号，默认是空格；改成逗号后，
    # 下面那行就能按逗号把配置名切成一个个。
    read -ra config_array <<<"$_config"
    # 把 $_config 按逗号拆开，存成一组（数组）config_array。
    #   -r 表示"原始读取"（不把反斜杠当特殊符号）；
    #   -a 表示"存成数组"。

    # reverse loop the config files
    # 【中文】倒着遍历这些配置文件
    for ((i = ${#config_array[@]} - 1; i >= 0; i--)); do
      # 从最后一个开始，往前一个一个处理。
      # ${#config_array[@]} 是数组长度，减 1 就是最后一项的序号（序号从 0 开始）。
      _tmp_baseurl="$(grep '^baseurl:' "${config_array[i]}" | sed "s/.*: *//;s/['\"]//g;s/#.*//")"
      # 从第 i 个配置文件里把 baseurl 的值抠出来。
      # 这一长串分成两段理解：
      #   ① grep '^baseurl:' 文件
      #        找出以 baseurl: 开头的那一行，例如：baseurl: "/blog"
      #        ^ 表示"行首"，这样就能避免误匹配到注释里提到 baseurl 的文字。
      #   ② sed "..." 做三步清理：
      #        s/.*: *//    把"冒号及它前面的内容"一起去掉，只留下值；
      #        s/['\"]//g   把值两边的引号（单引号或双引号）也去掉；
      #        s/#.*//      把行尾的注释（# 后面的内容）去掉。
      # 最终 "/blog" 就干净地变成了 /blog。

      if [[ -n $_tmp_baseurl ]]; then
        # 如果这次确实读到了非空的值（-n 表示"非空"）。
        _baseurl="$_tmp_baseurl"
        break
        # 【为什么倒着找？】因为后面指定的配置文件优先于前面的，
        # 倒序找到第一个有值的就用它，正好符合"后写的覆盖先写的"这个直觉。
        # 找到就立刻跳出循环，不用再往前找了。
      fi
    done

  else
    # 情况二：只有单个配置文件，直接读即可。
    # single config
    _baseurl="$(grep '^baseurl:' "$_config" | sed "s/.*: *//;s/['\"]//g;s/#.*//")"
    # 处理方式跟上面完全一样，只是少了"遍历多个文件"那一层。
  fi
}

main() {
  # 【主流程】按顺序做三件事：清场 → 读配置 → 构建 → 检查。

  # clean up
  # 【中文】先清场：删掉上次留下的编译产物
  if [[ -d $SITE_DIR ]]; then
    rm -rf "$SITE_DIR"
  fi
  # 【为什么必须先删？】因为上次编译残留的旧文件可能干扰这次检查——
  # 比如某个页面您已经删掉了，但旧文件还在，检查时就可能报出"关于已删除页面的假问题"。
  # 每次从干净状态开始，结果才可靠。
  # 先判断目录存在再删，避免目录不存在时 rm 报错。

  read_baseurl
  # 调用上面的函数，读出网站子路径。

  # build
  # 【中文】构建网站
  JEKYLL_ENV=production bundle exec jekyll b \
    -d "$SITE_DIR$_baseurl" -c "$_config"
  # 编译网站。参数说明：
  #   JEKYLL_ENV=production = 声明正式环境（启用压缩等优化）；
  #   bundle exec           = 用项目锁定的组件版本运行；
  #   jekyll b              = b 是 build（构建）的简写；
  #   -d "$SITE_DIR$_baseurl" = 生成结果放到哪个目录
  #        （如果子路径非空，会拼成 _site/blog 这种形式）；
  #   -c "$_config"         = 使用哪个配置文件。
  # 【注意】这里用正式环境构建，所以检查的是"上线后会是什么样"，
  # 与线上真实情况一致（包括 compress_html 压缩带来的影响）。

  # test
  # 【中文】开始检查
  # 说明：html-proofer 默认 --enforce-https，会拒绝任何 http:// 链接；
  #       下列 ignore-urls 中除本机地址外，lsrz.cs.mfa.gov.cn 为仅支持 http 的政府站点。
  # 【这段话的背景解释，值得一读】
  # html-proofer 这个工具默认只认 https 链接（因为 https 更安全），
  # 遇到 http 链接就会报"不安全"。
  # 但有两类 http 链接是无辜的，必须放过：
  #   ① 本机地址（127.0.0.1、0.0.0.0、localhost）——
  #      它们只在自己电脑上用，根本就没有 https 版本，检查出来也没意义；
  #   ② lsrz.cs.mfa.gov.cn —— 这是一个政府网站，
  #      它本身只支持 http（很多政府站点都这样），不是我们写错了。
  # 所以下面用 ignore-urls 把这几类排除掉，避免无谓的报错干扰。
  bundle exec htmlproofer "$SITE_DIR" \
    --disable-external \
    --ignore-urls "/^http:\/\/127.0.0.1/,/^http:\/\/0.0.0.0/,/^http:\/\/localhost/,/^http:\/\/lsrz\.cs\.mfa\.gov\.cn/"
  # 执行检查。两个参数：
  #   --disable-external = 只检查站内链接，不检查外站链接。
  #        原因：外站偶尔维护打不开很正常，不该因为别人家网站的问题
  #        就说我们自己的网站有毛病；同时也能大幅加快检查速度。
  #   --ignore-urls     = 忽略上面说明的那几类网址。
  #        那串看起来很复杂的写法是"正则表达式"，作用是按规律匹配网址；
  #        里面的 \/ 是为了把斜杠转义（因为斜杠本身在正则里有特殊含义）。
  # 【结果怎么看？】检查通过就没有输出或提示通过；
  # 有问题会列出具体是哪个页面的哪个链接出了什么状况，按提示去修即可。
}

while (($#)); do
  # 循环处理您输入的所有参数（和 run.sh 里的写法一样）。
  opt="$1"
  case $opt in
  -c | --config)
    # 情况一：指定配置文件。
    _config="$2"
    # 取下一个参数作为配置文件名。
    shift
    shift
    # 跳过两个参数（选项本身 + 它的值）。
    # 这里写成两行 shift 和写成 shift 2 效果一样，只是风格不同。
    ;;
  -h | --help)
    # 情况二：查看帮助。
    help
    exit 0
    ;;
  *)
    # 情况三：不认识的参数。
    # unknown option
    help
    exit 1
    # 打印帮助并报错退出。
    ;;
  esac
done

main
# 【最后一行】参数都处理完了，开始执行主流程。
