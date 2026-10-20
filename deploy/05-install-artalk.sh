#!/usr/bin/env bash
# ============================================================
# 【本文件是什么？】
#  05-install-artalk.sh —— 一键部署「自托管评论系统 Artalk」
#
#  一句话概括：这个脚本把评论服务装到你自己服务器上，
#  装完访客就能在文章底部用昵称直接留言（不需要 GitHub 账号）。
#
#  【它替你做了哪几件事】
#    ① 装 Docker（已经装过就跳过）
#    ② 建目录 /opt/artalk，生成配置文件 artalk.yml（自动生成随机密钥）
#    ③ 启动 Artalk 容器（只监听本机 127.0.0.1，外网碰不到）
#    ④ 创建管理员账号（交互式输入用户名/邮箱/密码）
#    ⑤ 配 Nginx 反向代理（把 https://artalk.你的域名 转发到 23366 端口）
#    ⑥ 用 certbot 申请子域名 HTTPS 证书（装了 certbot 才有这一步）
#    ⑦ 自检：容器在跑吗？本机接口通吗？外网能打开吗？
#
#  【前提条件】（缺一个都会失败）
#    ① 域名已加子域名解析：artalk.你的域名 → 服务器公网 IP
#       （在域名服务商的「DNS 解析」里加一条 A 记录，主机记录填 artalk）
#    ② 服务器在中国大陆时，子域名需在主域名备案范围内（一般自动覆盖）
#    ③ 安全组已放行 22 / 80 / 443（不需要放行 23366）
#    ④ 已跑过 01-server-init.sh（Nginx 已装好）
#
#  【用法】（服务器上，root）
#     cd /opt/site/src && git pull            # 先拉到最新代码（含本脚本）
#     bash /opt/site/src/deploy/05-install-artalk.sh
#
#     bash 05-install-artalk.sh --check        # 只体检，不改任何东西
#     bash 05-install-artalk.sh --no-cert      # 先不申请证书（只开 http 调试）
#     bash 05-install-artalk.sh --no-admin     # 跳过创建管理员（稍后手动建）
#     bash 05-install-artalk.sh --reset-config # 重新生成 artalk.yml（旧文件已备份）
#     bash 05-install-artalk.sh --remove       # 卸载（评论数据保留，需手动删）
#
#  【为什么可以反复运行】
#    脚本每一步都先判断"是不是已经做过了"，做过的就跳过（幂等）。
#    所以改完 config.env 想重来一遍，直接再跑一次即可，不会搞坏已有数据。
#
#  【数据在哪（备份就备份这个目录）】
#     /opt/artalk/data/artalk.db    所有评论都在这一个文件里
#     /opt/artalk/artalk.yml        服务端配置
# ============================================================
set -euo pipefail
# 脚本安全模式：出错立即停（不会带着错误往下跑）、变量必须已定义、
# 管道中任一环节出错也算失败。这样能避免"错了一半还在继续"的尴尬局面。

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 本脚本所在文件夹的绝对路径（不是相对路径，避免"在别的目录执行就找不到文件"）。

CONF="$HERE/config.env"
# 配置文件路径：和本脚本放在同一目录。

case " ${*:-} " in
  *" --help "*|*" -h "*)
    sed -n '2,45p' "$0"
    exit 0 ;;
esac
# 先处理「看帮助」：放在读配置之前，这样即使 config.env 还没建，也能看用法。

log()  { echo -e "\n\033[1;36m▶ $*\033[0m"; }
# 打印「步骤标题」：青色。$* 表示把所有参数拼起来输出。
ok()   { echo -e "\033[1;32m  ✅ $*\033[0m"; }
# 打印「成功」：绿色。
info() { echo -e "     $*"; }
# 打印「普通说明」：前面缩进 5 个空格，视觉上从属于上面的步骤标题。
warn() { echo -e "\033[1;33m  ⚠️  $*\033[0m"; }
# 打印「警告」：黄色。表示"能继续，但你最好看一眼"。
die()  { echo -e "\n\033[1;31m  ❌ $*\033[0m" >&2; exit 1; }
# 打印「错误并退出」：红色，写到标准错误。

# ------------------------------------------------------------
# 0. 读取配置
# ------------------------------------------------------------
[[ -f "$CONF" ]] || die "找不到配置文件 $CONF
   请先执行： cd $HERE && cp config.env.example config.env && vi config.env"
# 没有配置就没什么可干的，直接告诉他怎么建。

# shellcheck disable=SC1090
source "$CONF"
# 把配置读进来（DOMAIN / WWW_DOMAIN / LE_EMAIL 等）。

: "${DOMAIN:?config.env 里的 DOMAIN 没填}"
# : "${X:?提示}" 的意思是：X 必须有值，否则打印提示并退出。
# 域名是整个部署的根，没填就别往下走了。

ARTALK_DOMAIN="${ARTALK_DOMAIN:-artalk.$DOMAIN}"
# 评论服务的域名。默认「artalk + 主域名」，例如 artalk.2019527.xyz。
# 想用 comment.2019527.xyz 这种名字，就在 config.env 里加一行 ARTALK_DOMAIN="comment.2019527.xyz"。
# 注意：换名字要去域名后台同步加解析，否则证书申请会失败。

ARTALK_DIR="${ARTALK_DIR:-/opt/artalk}"
# Artalk 的工作目录（配置 + 数据都在这）。

ARTALK_PORT="${ARTALK_PORT:-23366}"
# Artalk 服务端监听端口。官方默认 23366，不用改。
# 这个端口只在服务器内部用，安全组不需要放行。

ARTALK_SITE="${ARTALK_SITE:-王志满律师}"
# 站点名称。必须和网站项目 _config.yml 里 comments.artalk.site 完全一致（一个字都不能差），
# 否则会出现"读者能留言、你在后台一条都看不到"的怪现象。

ARTALK_IMAGE="${ARTALK_IMAGE:-artalk/artalk-go}"
# 容器镜像。想固定版本不自动升级，就写成 artalk/artalk-go:v2.10.0。

ARTALK_DATA="$ARTALK_DIR/data"
ARTALK_CONF="$ARTALK_DIR/artalk.yml"
# 两个最关键的路径，后面反复用。

MODE="install"
# 默认动作：安装/更新。下面按参数改成别的。

for arg in "$@"; do
  case "$arg" in
    --check)        MODE="check" ;;
    --no-cert)      MODE="install"; NO_CERT=1 ;;
    --no-admin)     NO_ADMIN=1 ;;
    --reset-config) RESET_CONFIG=1 ;;
    --remove)       MODE="remove" ;;
    -h|--help)      sed -n '2,45p' "$0"; exit 0 ;;
    *)              die "不认识的参数：$arg （可用：--check --no-cert --no-admin --reset-config --remove）" ;;
  esac
done
# 逐个检查命令行参数。这里没用 getopts，因为只需要几个开关，手写更直观。
NO_CERT="${NO_CERT:-0}"
NO_ADMIN="${NO_ADMIN:-0}"
RESET_CONFIG="${RESET_CONFIG:-0}"
# 把"没传过"的变量补成 0，避免 set -u 报"变量未定义"。

# ------------------------------------------------------------
# 1. 基础检查
# ------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "请用 root 运行： sudo bash $0"
# EUID 是当前用户编号，root 是 0。改系统目录、装软件都需要 root。

command -v nginx >/dev/null 2>&1 || die "没装 Nginx。请先跑： bash $HERE/01-server-init.sh"
# command -v 用来查"这个命令存不存在"。没有 Nginx 就没法做反向代理。

echo "============================================================"
echo "  Artalk 自托管评论 —— 一键部署"
echo "  评论域名 : https://$ARTALK_DOMAIN"
echo "  工作目录 : $ARTALK_DIR"
echo "  站点名称 : $ARTALK_SITE"
echo "  主域名   : $DOMAIN"
echo "============================================================"
# 开头先把关键信息亮出来，让用户在动手前能发现"域名填错了"这种低级问题。

# ------------------------------------------------------------
# 2. --check：只体检，不改动
# ------------------------------------------------------------
if [[ "$MODE" == "check" ]]; then
  log "体检模式（不会改动任何文件）"

  if command -v docker >/dev/null 2>&1; then
    ok "Docker 已安装：$(docker --version 2>/dev/null || echo '版本读取失败')"
  else
    warn "Docker 未安装（正式部署时会自动装）"
  fi

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx artalk; then
    ok "artalk 容器在运行"
  else
    warn "artalk 容器没在运行"
  fi

  if [[ -f "$ARTALK_CONF" ]]; then
    ok "配置文件存在：$ARTALK_CONF"
  else
    warn "配置文件还没生成：$ARTALK_CONF"
  fi

  if [[ -f "$ARTALK_DATA/artalk.db" ]]; then
    info "数据库大小：$(du -h "$ARTALK_DATA/artalk.db" | cut -f1)"
  else
    info "数据库还没产生（首次启动后才有）"
  fi

  if curl -fsS -o /dev/null --max-time 3 "http://127.0.0.1:$ARTALK_PORT" 2>/dev/null; then
    ok "本机接口可访问：http://127.0.0.1:$ARTALK_PORT"
  else
    warn "本机接口访问不到（服务没起或端口不是 $ARTALK_PORT）"
  fi

  IPS="$(getent hosts "$ARTALK_DOMAIN" 2>/dev/null | awk '{print $1}' | paste -sd, - || true)"
  if [[ -n "$IPS" ]]; then
    ok "域名解析：$ARTALK_DOMAIN → $IPS"
  else
    warn "域名 $ARTALK_DOMAIN 解析不到。请去域名后台加 A 记录（主机记录：artalk）"
  fi

  if curl -fsS -o /dev/null --max-time 5 "https://$ARTALK_DOMAIN" 2>/dev/null; then
    ok "外网 HTTPS 可访问：https://$ARTALK_DOMAIN"
  else
    warn "外网 HTTPS 访问失败（证书没装 / 解析未生效 / 安全组未放行 443）"
  fi

  if command -v certbot >/dev/null 2>&1; then
    ok "certbot 已安装"
  else
    warn "certbot 未安装（无法自动申请证书，见 03-https.sh）"
  fi

  NGX="/etc/nginx/sites-available/$ARTALK_DOMAIN.conf"
  if [[ -f "$NGX" ]]; then
    ok "Nginx 配置存在：$NGX"
  else
    warn "Nginx 配置还没有：$NGX"
  fi

  if curl -fsS -o /dev/null --max-time 5 "https://$DOMAIN" 2>/dev/null; then
    ok "主站正常：https://$DOMAIN"
  else
    warn "主站访问异常，先修主站再装评论"
  fi

  echo
  info "体检结束。"
  exit 0
fi

# ------------------------------------------------------------
# 3. --remove：卸载
# ------------------------------------------------------------
if [[ "$MODE" == "remove" ]]; then
  log "卸载 Artalk 服务（评论数据会保留）"

  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx artalk; then
    docker stop artalk >/dev/null 2>&1 || true
    docker rm artalk >/dev/null 2>&1 || true
    ok "容器已删除"
  else
    info "本来就没有 artalk 容器"
  fi

  for f in "/etc/nginx/sites-enabled/$ARTALK_DOMAIN.conf" "/etc/nginx/sites-available/$ARTALK_DOMAIN.conf"; do
    if [[ -e "$f" || -L "$f" ]]; then
      rm -f "$f"
      ok "已删除 Nginx 配置：$f"
    fi
  done
  # -e 判断"文件存在"，-L 判断"这是个软链"。两者都要判，因为软链可能指向已删除的目标。

  if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx || true
    ok "Nginx 已重载"
  else
    warn "Nginx 配置有问题，请手动 nginx -t 检查"
  fi

  echo
  warn "评论数据仍保留在：$ARTALK_DATA"
  info "确认备份好之后，再手动删除（不可逆）："
  info "  tar -czf /root/artalk-final-backup.tar.gz -C $ARTALK_DIR data"
  info "  rm -rf $ARTALK_DIR"
  info "如需删除证书： certbot delete --cert-name $ARTALK_DOMAIN"
  exit 0
fi

# ------------------------------------------------------------
# 4. 检查子域名解析（只警告，不阻断）
# ------------------------------------------------------------
log "检查子域名解析"
RESOLVED="$(getent hosts "$ARTALK_DOMAIN" 2>/dev/null | awk '{print $1}' | paste -sd, - || true)"
# getent hosts 即"查这个域名的 IP"。awk 取第一列（IP），paste -sd, 把多行拼成逗号分隔。
if [[ -n "$RESOLVED" ]]; then
  ok "$ARTALK_DOMAIN → $RESOLVED"
else
  warn "解析不到 $ARTALK_DOMAIN"
  info "去域名服务商后台加一条 A 记录：主机记录 artalk，记录值 = 本服务器公网 IP"
  info "加完等 1~10 分钟，用 nslookup $ARTALK_DOMAIN 验证。"
  info "如果暂时没解析，可以先加 --no-cert 跳过证书那一步，之后再来申请。"
  # 这里不退出：有可能用户用的是 hosts 或稍后生效，先让他把服务端跑起来也行。
fi

# ------------------------------------------------------------
# 5. 安装 Docker
# ------------------------------------------------------------
log "检查 Docker"
if command -v docker >/dev/null 2>&1; then
  ok "已安装：$(docker --version 2>/dev/null || echo docker)"
else
  info "未安装，开始安装（官方脚本 + 阿里云镜像，约 2~5 分钟）..."
  curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun \
    || die "Docker 安装失败。可重试一次；若持续失败，检查服务器能否访问外网。"
  # curl 下载官方安装脚本，管道交给 bash 执行；--mirror Aliyun 指定国内镜像加速下载。
  ok "Docker 安装完成"
fi

systemctl enable --now docker >/dev/null 2>&1 || true
# 设为开机自启并立即启动。已启动时这条不会有副作用。
ok "Docker 服务已就绪"

# 5.1 镜像加速（只在还没配过的时候写，避免覆盖用户已有配置）
if [[ ! -f /etc/docker/daemon.json ]]; then
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json <<'JSON'
{
  "registry-mirrors": [
    "https://docker.1panel.live",
    "https://hub.rat.dev",
    "https://docker.m.daocloud.io"
  ]
}
JSON
  # 这里是单引号 'JSON'，表示"原样写入，不解析变量"——JSON 里没有变量，且必须避免 $ 被吃掉。
  systemctl daemon-reload
  systemctl restart docker
  ok "已写入 Docker 国内镜像加速"
elif grep -q "registry-mirrors" /etc/docker/daemon.json 2>/dev/null; then
  info "已有镜像加速配置，保持不动"
else
  warn "/etc/docker/daemon.json 已存在但没有 registry-mirrors"
  info "如需加速，请手动在里面加 registry-mirrors 后重启 docker。"
fi

# ------------------------------------------------------------
# 6. 建目录 + 生成 artalk.yml
# ------------------------------------------------------------
log "准备目录 $ARTALK_DIR"
mkdir -p "$ARTALK_DATA"
ok "数据目录就绪：$ARTALK_DATA"

if [[ -f "$ARTALK_CONF" && "$RESET_CONFIG" -ne 1 ]]; then
  # 已有配置就绝不覆盖：里面存着 app_key，换了会导致已登录的后台全部掉线，
  # 更糟的是跟旧数据不匹配时可能读不出历史评论。
  ok "配置文件已存在，保留不动：$ARTALK_CONF"
  info "想让脚本重新生成（旧文件会先备份），加参数 --reset-config"
else
  if [[ -f "$ARTALK_CONF" ]]; then
    BAK="$ARTALK_CONF.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "$ARTALK_CONF" "$BAK"
    ok "旧配置已备份：$BAK"
  fi

  APP_KEY="$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  # 用 OpenSSL 生成 64 位随机十六进制串。
  # 万一服务器没装 openssl，退回用 /dev/urandom 生成，效果一样。
  # 这个密钥用于加密登录凭证，必须是随机值——用示例值等于"门锁钥匙挂在门上"。

  # trusted_domains：必须填"你的网站地址"，不是评论服务自己的地址。
  # 访客是从 https://你的域名 的页面去请求评论接口的，对 Artalk 来说属于跨域，
  # 不在白名单里就会被浏览器拦掉（表现：评论区一直"加载中"）。
  TRUST_LINES="  - https://$DOMAIN"
  if [[ -n "${WWW_DOMAIN:-}" ]]; then
    TRUST_LINES="$TRUST_LINES
  - https://${WWW_DOMAIN}"
  fi

  umask 077
  # 临时把"新建文件的默认权限"收紧成"只有本人可读写"，写完再恢复。
  # 因为文件里有密钥，不该让其他用户读到。
  cat > "$ARTALK_CONF" <<YAML
# ============================================================
#  Artalk 服务端配置（由 deploy/05-install-artalk.sh 生成）
#  改完必须重启才生效： docker restart artalk
#  ⚠️ YAML 只能用空格缩进，绝对不能用 Tab
# ============================================================

# 加密密钥（自动生成，别泄露、别改）
app_key: $APP_KEY

# 监听地址与端口
# host 写 0.0.0.0 是"容器内监听所有网卡"，
# 但容器对外只映射了 127.0.0.1，所以外网仍然碰不到，必须经过 Nginx。
host: 0.0.0.0
port: $ARTALK_PORT

locale: zh-CN
timezone: Asia/Shanghai

# 数据库：SQLite 单文件，最适合个人博客
db:
  type: sqlite
  file: /data/artalk.db
  # 容器里的 /data 已挂载到服务器的 $ARTALK_DATA
  # 所以真实文件是 $ARTALK_DATA/artalk.db

# 默认站点名称：必须和网站项目 _config.yml 的 comments.artalk.site 完全一致
site_default: $ARTALK_SITE

# 跨域白名单：填"你的网站地址"（不是评论服务地址）
trusted_domains:
$TRUST_LINES

# 从 Nginx 转发头里取访客真实 IP（否则后台看到的全是 127.0.0.1）
http:
  proxy_header: X-Forwarded-For

log:
  enabled: true
  filename: /data/artalk.log

# 个人博客评论量不大，缓存先关着；将来评论多了可改 true
cache:
  enabled: false

# 后台登录有效期（秒）：259200 秒 = 3 天
login_timeout: 259200
YAML
  umask 022
  chmod 600 "$ARTALK_CONF"
  ok "配置文件已生成：$ARTALK_CONF"
fi

# ------------------------------------------------------------
# 7. 启动容器
# ------------------------------------------------------------
log "启动 Artalk 容器"
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx artalk; then
  info "发现旧容器，先删掉再按当前配置重建（数据在挂载目录里，不会丢）"
  docker rm -f artalk >/dev/null 2>&1 || true
fi

docker pull "$ARTALK_IMAGE" >/dev/null 2>&1 || warn "镜像拉取较慢或失败，下面会再试一次"
# 先单独 pull 一次，好处是网络问题能在这一步暴露，日志更清楚。
# 拉不动也不算致命，docker run 时还会再尝试。

docker run -d \
  --name artalk \
  --restart unless-stopped \
  -p "127.0.0.1:$ARTALK_PORT:$ARTALK_PORT" \
  -v "$ARTALK_DATA:/data" \
  -v "$ARTALK_CONF:/opt/artalk/artalk.yml" \
  -e "TZ=Asia/Shanghai" \
  -w /opt/artalk \
  "$ARTALK_IMAGE" >/dev/null \
  || die "容器启动失败。看原因： docker logs artalk"
# 注意：这里故意不给镜像追加 server -c 参数——镜像自带的默认启动命令就是
#   server -c /opt/artalk/artalk.yml
# 再手动传一遍反而可能变成 "server -c ... server -c ..." 而启动失败。
# 参数逐个说明：
#   -d                        后台运行
#   --name artalk             容器名（以后 docker restart artalk 靠它）
#   --restart unless-stopped  开机自启；手动 stop 后不会自己爬起来
#   -p 127.0.0.1:23366:23366  只映射到本机！写成 -p 23366:23366 就等于把接口暴露到公网了
#   -v .../data:/data         评论数据存到服务器硬盘（删容器不丢数据）
#   -v .../artalk.yml:...     配置文件挂进去（改配置不用进容器）
#   -e TZ=Asia/Shanghai       容器时区设为北京时间
#   -w /opt/artalk            工作目录
#   server -c ...             以服务端模式启动并指定配置文件

ok "容器已启动"

# 7.1 等它就绪（最多约 20 秒）
READY=0
for i in $(seq 1 20); do
  if curl -fsS -o /dev/null --max-time 2 "http://127.0.0.1:$ARTALK_PORT" 2>/dev/null; then
    READY=1
    break
  fi
  sleep 1
done
# 循环 20 次，每次等 1 秒。容器启动 + 建库需要一两秒，太早探测会误判失败。

if [[ "$READY" -eq 1 ]]; then
  ok "本机接口已可访问：http://127.0.0.1:$ARTALK_PORT"
else
  warn "20 秒内没等到服务就绪"
  info "下面这些日志通常能直接指出原因（配置缩进、密钥、端口占用）："
  docker logs --tail 30 artalk 2>&1 | sed 's/^/       /' || true
fi

# 7.2 兼容旧容器：检查管理员是否已存在
ADMIN_COUNT="$(docker exec artalk artalk admin --list 2>/dev/null | grep -c '@' || true)"
# --list 会输出账号列表，靠"有没有邮箱里的 @"粗略计数。
# 2>/dev/null 是因为老版本没有 --list 时会报错，这属于可接受情况。
ADMIN_COUNT="${ADMIN_COUNT:-0}"

# ------------------------------------------------------------
# 8. 创建管理员
# ------------------------------------------------------------
log "管理员账号"
if [[ "$ADMIN_COUNT" -gt 0 ]]; then
  ok "已有 $ADMIN_COUNT 个管理员账号，跳过创建"
elif [[ "$NO_ADMIN" -eq 1 ]]; then
  warn "按参数要求跳过。稍后手动创建： docker exec -it artalk artalk admin"
elif [[ -t 0 ]]; then
  info "接下来按提示输入：用户名（可填 admin）、邮箱（找回密码用）、密码（设强密码）"
  docker exec -it artalk artalk admin || warn "创建过程被中断或失败，可稍后重跑： docker exec -it artalk artalk admin"
else
  # 非交互环境（例如被 CI 或脚本批量调用）不能进入问答模式，只给提示。
  warn "当前不是交互终端，无法在这里创建管理员"
  info "请手动执行： docker exec -it artalk artalk admin"
fi

# ------------------------------------------------------------
# 9. 配置 Nginx 反向代理
# ------------------------------------------------------------
log "配置 Nginx 反向代理"
NGX_AVAIL="/etc/nginx/sites-available/$ARTALK_DOMAIN.conf"
NGX_ENABLED="/etc/nginx/sites-enabled/$ARTALK_DOMAIN.conf"

if [[ -f "$NGX_AVAIL" ]] && grep -q "ssl_certificate" "$NGX_AVAIL" 2>/dev/null; then
  # 关键细节：certbot 会把证书配置"写进"这个文件。
  # 如果没有这个判断，重跑脚本会用纯 80 端口的模板覆盖它，HTTPS 立刻挂掉。
  ok "已有配置且含 HTTPS 证书，保留不动：$NGX_AVAIL"
else
  cat > "$NGX_AVAIL" <<NGINX
# Artalk 评论服务反向代理（由 deploy/05-install-artalk.sh 生成）
server {
    listen 80;
    listen [::]:80;
    server_name $ARTALK_DOMAIN;

    # 允许上传较大的头像
    client_max_body_size 10m;

    location / {
        proxy_pass http://127.0.0.1:$ARTALK_PORT;
        # 结尾不要带 /，否则请求路径会被改写，接口会 404

        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        # 这四行把访客真实信息传给 Artalk：
        # 少了 X-Forwarded-For，后台看到的访客 IP 会全是 127.0.0.1

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        # 这三行支持 WebSocket（实时推送新评论）
    }
}
NGINX
  # 这里用不带引号的 heredoc，但把 \$host 之类转义成 \$，
  # 目的：让变量在"Nginx 运行时"展开，而不是被本脚本提前替换掉。
  ok "已写入：$NGX_AVAIL"
fi

ln -sfn "$NGX_AVAIL" "$NGX_ENABLED"
# 软链：sites-available 存真身，sites-enabled 放快捷方式。
# -sfn 的含义：s 建软链、f 覆盖已存在的、n 把软链当普通文件（不要跟进去）。
ok "已启用：$NGX_ENABLED"

if nginx -t >/dev/null 2>&1; then
  systemctl reload nginx
  ok "Nginx 配置校验通过并已重载"
else
  nginx -t || true
  die "Nginx 配置有问题，上面是报错详情。修好后再跑一次本脚本。"
fi

# ------------------------------------------------------------
# 10. 申请子域名证书
# ------------------------------------------------------------
log "HTTPS 证书"
if [[ "$NO_CERT" -eq 1 ]]; then
  warn "按参数要求跳过证书申请（此时只有 http，https 网站会拦评论请求）"
  info "稍后单独执行： certbot --nginx -d $ARTALK_DOMAIN --redirect"
elif ! command -v certbot >/dev/null 2>&1; then
  warn "没装 certbot，跳过。先跑 03-https.sh，再回来执行："
  info "  certbot --nginx -d $ARTALK_DOMAIN --redirect"
elif [[ -z "$RESOLVED" ]]; then
  warn "域名还没解析到服务器，现在申请证书一定失败，跳过"
  info "解析生效后执行： certbot --nginx -d $ARTALK_DOMAIN --redirect -m $LE_EMAIL --agree-tos -n"
elif [[ -f "/etc/letsencrypt/live/$ARTALK_DOMAIN/fullchain.pem" ]]; then
  ok "证书已存在，跳过申请（certbot 会自动续期）"
else
  info "正在申请 Let's Encrypt 免费证书..."
  if certbot --nginx -d "$ARTALK_DOMAIN" --redirect \
       -m "$LE_EMAIL" --agree-tos -n --keep-until-expiring; then
    ok "证书申请成功：https://$ARTALK_DOMAIN"
  else
    warn "证书申请失败。最常见原因："
    info "  ① 子域名解析没生效（nslookup $ARTALK_DOMAIN）"
    info "  ② 安全组没放行 80 端口"
    info "  ③ 大陆服务器子域名未在备案范围内"
    info "修好后重跑： certbot --nginx -d $ARTALK_DOMAIN --redirect"
  fi
fi
# -n 表示非交互（不弹问答），--agree-tos 自动同意条款，-m 指定提醒邮箱，
# --keep-until-expiring 表示"证书还早就不重签"，避免反复申请触发频率限制。

# ------------------------------------------------------------
# 11. 自检
# ------------------------------------------------------------
log "自检结果"
if docker ps --format '{{.Names}}' | grep -qx artalk; then
  ok "容器运行中：$(docker ps --filter name=artalk --format '{{.Status}}')"
else
  warn "容器没在运行，看日志： docker logs --tail 50 artalk"
fi

if curl -fsS -o /dev/null --max-time 3 "http://127.0.0.1:$ARTALK_PORT" 2>/dev/null; then
  ok "本机接口正常：http://127.0.0.1:$ARTALK_PORT"
else
  warn "本机接口不通"
fi

if curl -fsS -o /dev/null --max-time 5 "http://$ARTALK_DOMAIN" 2>/dev/null; then
  ok "HTTP 可访问：http://$ARTALK_DOMAIN"
else
  warn "HTTP 访问失败（解析 / 安全组 / Nginx 三选一排查）"
fi

if curl -fsS -o /dev/null --max-time 5 "https://$ARTALK_DOMAIN" 2>/dev/null; then
  ok "HTTPS 可访问：https://$ARTALK_DOMAIN"
else
  warn "HTTPS 还没通（证书未申请成功时会这样）"
fi

if [[ -f "$ARTALK_DATA/artalk.db" ]]; then
  ok "数据库已生成：$ARTALK_DATA/artalk.db（$(du -h "$ARTALK_DATA/artalk.db" | cut -f1)）"
else
  info "数据库还没生成（首次有评论或完成初始化后才有）"
fi

# ------------------------------------------------------------
# 12. 收尾提示
# ------------------------------------------------------------
cat <<TIP

============================================================
  ✅ 服务端部署完成
============================================================

  1) 后台地址： https://$ARTALK_DOMAIN
     用第 8 步创建的账号登录，可审核/删除评论、改设置。

  2) 还要改网站项目一处（在你自己电脑上）：
     打开 _config.yml，找到 comments.provider，改成：

         provider: artalk

     再找到 comments.artalk.server，填：

         server: https://$ARTALK_DOMAIN

     然后重新发布网站（双击 deploy-aliyun.bat，或服务器上跑
     bash $HERE/publish.sh）。

  3) 站点名称必须一致（否则后台看不到评论）：
         _config.yml  comments.artalk.site : $ARTALK_SITE
         $ARTALK_CONF  site_default        : $ARTALK_SITE

  4) 评论区没出来时，按这个顺序查（90% 是前两条）：
     · 浏览器 F12 → Console，看红色报错
     · trusted_domains 里有没有 https://$DOMAIN
     · server 结尾有没有多写 /
     · 改完 artalk.yml 有没有 docker restart artalk

  5) 备份（建议做成习惯，评论就在这一个目录里）：
         tar -czf /root/artalk-backup-\$(date +%Y%m%d).tar.gz -C $ARTALK_DIR data

  6) 随时体检（只读，不改任何东西）：
         bash $HERE/05-install-artalk.sh --check

  不想要评论了：
         bash $HERE/05-install-artalk.sh --remove     # 数据保留
         再把 _config.yml 的 provider 改回 giscus

============================================================
TIP
