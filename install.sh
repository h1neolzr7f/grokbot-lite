#!/usr/bin/env bash
# grokbot-lite 一键安装器 / one-click installer
#
#   curl -fsSL https://raw.githubusercontent.com/<you>/grokbot-lite/main/install.sh | sudo bash
#   curl -fsSL .../install.sh | sudo bash -s -- --yes            # 全自动（默认安全选项）
#   curl -fsSL .../install.sh | sudo bash -s -- --switch-account # 换账号
#   curl -fsSL .../install.sh | sudo bash -s -- --uninstall      # 卸载
#
# 在 1–2 GB 内存的云服务器 / 小主机上，把官方 Grok Bot 远程执行后台跑成一个
# 低占用（约 200 MB）的 systemd 服务：专用非 root 用户、ask 策略、开机自启。
#
# SPDX-License-Identifier: MIT
#
# The whole script is wrapped in functions and main() runs on the LAST line, so a
# truncated download can never execute half a script.
set -euo pipefail

INSTALLER_VERSION="0.2.0"

# ---------------------------------------------------------------- settings
: "${GBL_REPO_RAW:=https://raw.githubusercontent.com/YOUR-GITHUB/grokbot-lite/main}"   # placeholder
: "${GBL_SERVICE_USER:=grokbot}"
: "${GBL_NODE_DIR:=/opt/node22}"
: "${GBL_NODE_MAJOR:=22}"
: "${GBL_NODE_MIRRORS:=https://nodejs.org/dist https://npmmirror.com/mirrors/node}"
: "${GBL_SUPERVISOR_REF:=1e3e666cef9799627ed00cad6e08f540d916fd56}"   # andreanjos/grokbot-headless 0.2.2
: "${GBL_SUPERVISOR_TARBALL:=https://codeload.github.com/andreanjos/grokbot-headless/tar.gz/$GBL_SUPERVISOR_REF}"
: "${GBL_APT_KEY_URL:=https://downloads.cursor.com/keys/anysphere.asc}"
: "${GBL_APT_KEYRING:=/usr/share/keyrings/grok-bot.gpg}"
: "${GBL_APT_SOURCES:=/etc/apt/sources.list.d/grok-bot.sources}"
: "${GBL_APT_URI:=https://downloads.cursor.com/aptrepo}"
: "${GBL_BINARY:=/opt/Grok Bot/grok-bot}"
: "${GBL_CONF:=/etc/grokbot-lite.conf}"
: "${GBL_BACKUP_DIR:=/var/lib/grokbot-lite/backup}"
: "${GBL_CLI_PATH:=/usr/local/bin/grokbot-lite}"
: "${GBL_LOG:=/var/log/grokbot-lite-install.log}"
: "${GBL_LOGIN_WINDOW_SEC:=1440}"   # one-time link is valid ~24 min
: "${GBL_MIN_DISK_MB:=1200}"
: "${GBL_RUNUSER:=runuser}"
: "${GBL_TTY:=/dev/tty}"

YES=0 MODE=install DO_LOGIN=1 DRY_RUN=0

# ---------------------------------------------------------------- UI
setup_colors() {
  if [[ -t 2 && -z ${NO_COLOR:-} ]]; then
    R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' B=$'\e[34m' C=$'\e[36m' W=$'\e[1m' D=$'\e[2m' N=$'\e[0m'
  else
    R="" G="" Y="" B="" C="" W="" D="" N=""
  fi
}
STEP=0
step()  { STEP=$((STEP + 1)); printf '\n%s[%d] %s%s\n' "$B$W" "$STEP" "$*" "$N" >&2; }
ok()    { printf '  %s✔%s %s\n' "$G" "$N" "$*" >&2; }
note()  { printf '  %s•%s %s\n' "$D" "$N" "$*" >&2; }
warn()  { printf '  %s⚠ %s%s\n' "$Y" "$*" "$N" >&2; }
# fail MESSAGE FIX : friendly error with a suggested fix, then exit
fail() {
  printf '\n%s✘ 出错了：%s%s\n' "$R$W" "$1" "$N" >&2
  [[ -n ${2:-} ]] && printf '%s  怎么办：%s%s\n' "$Y" "$2" "$N" >&2
  printf '%s  完整日志：%s%s\n\n' "$D" "$GBL_LOG" "$N" >&2
  exit 1
}

# ask QUESTION DEFAULT(y|n) : y/n question read from the terminal (works with curl | bash)
ask() {
  local q=$1 def=$2 hint reply
  if [[ $def == y ]]; then hint="[Y/n]"; else hint="[y/N]"; fi
  if [[ $YES -eq 1 ]]; then note "$q $hint -> $def（--yes）"; [[ $def == y ]]; return; fi
  if ! { : <"$GBL_TTY"; } 2>/dev/null; then note "$q $hint -> $def（无终端，用默认值）"; [[ $def == y ]]; return; fi
  printf '  %s?%s %s %s ' "$C" "$N" "$q" "$hint" >&2
  read -r reply <"$GBL_TTY" || reply=""
  reply=${reply:-$def}
  [[ $reply == [yY]* ]]
}

run() { # log + run (or just print with --dry-run)
  printf '+ %s\n' "$*" >>"$GBL_LOG" 2>/dev/null || true
  if [[ $DRY_RUN -eq 1 ]]; then printf '  %s[dry-run]%s %s\n' "$D" "$N" "$*" >&2; return 0; fi
  "$@"
}

as_user() { # run as the service user with a working systemd --user environment
  local uid home
  uid=$(id -u "$GBL_SERVICE_USER") home=$(getent passwd "$GBL_SERVICE_USER" | cut -d: -f6)
  run "$GBL_RUNUSER" -u "$GBL_SERVICE_USER" -- env HOME="$home" USER="$GBL_SERVICE_USER" LOGNAME="$GBL_SERVICE_USER" \
    XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    PATH="$GBL_NODE_DIR/bin:/usr/local/bin:/usr/bin:/bin" GBL_BACKUP_DIR="$GBL_BACKUP_DIR" "$@"
}

banner() {
  printf '%s' "$C$W" >&2
  cat >&2 <<'EOF'
   ____           _    ____        _     _ _ _
  / ___|_ __ ___ | | _| __ )  ___ | |_  | (_) |_ ___
 | |  _| '__/ _ \| |/ /  _ \ / _ \| __| | | | __/ _ \
 | |_| | | | (_) |   <| |_) | (_) | |_  | | | ||  __/
  \____|_|  \___/|_|\_\____/ \___/ \__| |_|_|\__\___|
EOF
  printf '%s  低配服务器上的 Grok Bot 远程执行后台 · 约 200 MB 内存 · v%s%s\n' "$N$D" "$INSTALLER_VERSION" "$N" >&2
  printf '%s  日志：%s%s\n' "$D" "$GBL_LOG" "$N" >&2
}

is_root() { [[ $EUID -eq 0 || ${GBL_TEST_AS_ROOT:-} == 1 ]]; }

# ---------------------------------------------------------------- detection
detect_arch() { # uname -m -> deb arch, or fail with a friendly message
  case ${1:-$(uname -m)} in
    x86_64 | amd64) echo amd64 ;;
    aarch64 | arm64) echo arm64 ;;
    armv7l | armv6l | armhf) fail "不支持 32 位 ARM（$1）" "官方只提供 amd64 和 arm64。树莓派请刷 64 位系统（Raspberry Pi OS 64-bit / Ubuntu arm64）。" ;;
    i386 | i686) fail "不支持 32 位 x86（$1）" "请换 64 位系统。" ;;
    *) fail "未知 CPU 架构：$1" "目前只支持 x86_64 和 aarch64。" ;;
  esac
}

node_major() { # path-to-node -> major version number (0 if unusable)
  local v
  v=$("$1" --version 2>/dev/null) || { echo 0; return; }
  v=${v#v}; echo "${v%%.*}"
}

mem_total_mb() { awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo; }
mem_avail_mb() { awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo; }
swap_total_mb() { awk '/^SwapTotal:/ {print int($2/1024)}' /proc/meminfo; }
disk_free_mb() { df -Pm "$1" 2>/dev/null | awk 'NR==2 {print $4}'; }

preflight() {
  step "检查环境"
  is_root || fail "需要 root 权限" "用 sudo 运行：curl -fsSL <地址>/install.sh | sudo bash"
  [[ -r /etc/os-release ]] || fail "无法识别系统" "需要 Ubuntu 22.04+/Debian 12+。"
  local id ver pretty
  # shellcheck disable=SC1091
  id=$(. /etc/os-release && echo "${ID:-}") ver=$(. /etc/os-release && echo "${VERSION_ID:-}") pretty=$(. /etc/os-release && echo "${PRETTY_NAME:-$ID}")
  command -v apt-get >/dev/null || fail "没有 apt（当前：$pretty）" "目前只支持 Debian / Ubuntu 系列。CentOS/Alibaba Cloud Linux 请重装为 Ubuntu 24.04。"
  ok "系统：$pretty"
  [[ -d ${GBL_SYSTEMD_RUNDIR:-/run/systemd/system} ]] || fail "systemd 没有在运行" "OpenVZ/LXC 容器或 WSL1 不支持。请用 KVM 虚拟机（阿里云/腾讯云轻量都是 KVM），WSL2 需在 /etc/wsl.conf 打开 systemd=true。"
  ok "systemd 正在运行"
  ARCH=$(detect_arch "$(uname -m)")
  ok "架构：$(uname -m)（$ARCH）"
  local mem avail swap disk
  mem=$(mem_total_mb) avail=$(mem_avail_mb) swap=$(swap_total_mb)
  ok "内存：${mem} MB（可用 ${avail} MB），swap：${swap} MB"
  if ((mem < 900)); then warn "内存不足 1 GB：能跑，但请务必开 swap。"; fi
  if ((avail < 300)); then fail "可用内存只有 ${avail} MB" "先停掉一些服务，或开 swap 后重试（脚本会询问是否创建 swap）。"; fi
  disk=$(disk_free_mb /opt); [[ -n $disk ]] || disk=$(disk_free_mb /)
  ok "磁盘可用：${disk} MB"
  ((disk >= GBL_MIN_DISK_MB)) || fail "磁盘空间不足（可用 ${disk} MB，至少需要 ${GBL_MIN_DISK_MB} MB）" "清理：sudo apt-get clean && sudo journalctl --vacuum-size=100M，或扩容系统盘。官方包安装后约 350 MB，备份再占 ~200 MB。"
  if [[ $id == ubuntu && ${ver%%.*} -lt 22 ]] || [[ $id == debian && ${ver%%.*} -lt 12 ]]; then
    warn "$pretty 较旧，未测试。推荐 Ubuntu 24.04。"
  fi
}

maybe_swap() {
  local mem swap
  mem=$(mem_total_mb) swap=$(swap_total_mb)
  ((mem < 2500 && swap == 0)) || return 0
  step "创建 swap（小内存机器强烈建议）"
  if ask "检测到没有 swap，创建 2 GB 的 /swapfile？" y; then
    [[ -e /swapfile ]] && fail "/swapfile 已存在但未启用" "手动检查：sudo swapon --show"
    run fallocate -l 2G /swapfile || run dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    run chmod 600 /swapfile
    run mkswap /swapfile >/dev/null
    run swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab || [[ $DRY_RUN -eq 1 ]] || echo '/swapfile none swap sw 0 0' >>/etc/fstab
    ok "swap 已启用（2 GB）"
  else
    note "跳过 swap"
  fi
}

# ---------------------------------------------------------------- steps
apt_quiet() { # needrestart in list-only mode: never restart docker or other services behind your back
  run env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l NEEDRESTART_SUSPEND=1 apt-get "$@" >>"$GBL_LOG" 2>&1
}

install_grok_bot() {
  step "安装官方 grok-bot 包"
  if dpkg-query -W -f='${Status}' grok-bot 2>/dev/null | grep -q 'install ok installed'; then
    ok "已安装：grok-bot $(dpkg-query -W -f='${Version}' grok-bot)（跳过）"; return 0
  fi
  local need=()
  command -v curl >/dev/null || need+=(curl)
  command -v gpg >/dev/null || need+=(gnupg)
  [[ -e /etc/ssl/certs/ca-certificates.crt ]] || need+=(ca-certificates)
  if ((${#need[@]})); then note "安装依赖：${need[*]}"; apt_quiet update; apt_quiet install -y --no-install-recommends "${need[@]}"; fi
  if [[ ! -s $GBL_APT_KEYRING ]]; then
    note "导入官方软件源签名密钥"
    if [[ $DRY_RUN -eq 0 ]]; then
      curl -fsSL "$GBL_APT_KEY_URL" | gpg --dearmor -o "$GBL_APT_KEYRING" ||
        fail "下载签名密钥失败（$GBL_APT_KEY_URL）" "检查网络/DNS：curl -I $GBL_APT_KEY_URL"
      chmod 644 "$GBL_APT_KEYRING"
    fi
  fi
  if [[ ! -f $GBL_APT_SOURCES ]]; then
    [[ $DRY_RUN -eq 1 ]] || cat >"$GBL_APT_SOURCES" <<EOF
Types: deb
URIs: $GBL_APT_URI
Suites: grok-bot
Components: main
Signed-By: $GBL_APT_KEYRING
EOF
  fi
  note "apt-get update && apt-get install --no-install-recommends grok-bot（约 350 MB，请稍候）"
  apt_quiet update || fail "apt-get update 失败" "看日志最后几行：tail -n 30 $GBL_LOG"
  apt_quiet install -y --no-install-recommends grok-bot || fail "安装 grok-bot 失败" "看日志：tail -n 30 $GBL_LOG；磁盘满了就先清理。"
  ok "grok-bot $(dpkg-query -W -f='${Version}' grok-bot 2>/dev/null || echo '?') 已安装"
}

NODE_BIN=""
ensure_node() {
  step "准备 Node.js（需要 ≥ 20）"
  local sys=0
  command -v node >/dev/null && sys=$(node_major "$(command -v node)")
  if [[ -x $GBL_NODE_DIR/bin/node && $(node_major "$GBL_NODE_DIR/bin/node") -ge 20 ]]; then
    NODE_BIN=$GBL_NODE_DIR/bin/node; ok "使用 $NODE_BIN（$("$NODE_BIN" --version)）"; return 0
  fi
  if ((sys >= 20)); then
    NODE_BIN=$(command -v node); ok "系统 Node $(node --version) 可用"; return 0
  fi
  ((sys > 0)) && note "系统 Node 是 v$sys，太旧（监督进程需要 ≥ 20）。不动系统 Node，另装到 $GBL_NODE_DIR"
  local arch=x64 m sums file tmp
  [[ $ARCH == arm64 ]] && arch=arm64
  for m in $GBL_NODE_MIRRORS; do
    note "从 $m 获取 Node $GBL_NODE_MAJOR"
    sums=$(curl -fsSL --max-time 30 "$m/latest-v$GBL_NODE_MAJOR.x/SHASUMS256.txt" 2>>"$GBL_LOG") || continue
    file=$(printf '%s\n' "$sums" | awk -v a="linux-$arch.tar.xz" '$2 ~ a"$" {print $2; exit}')
    [[ -n $file ]] || continue
    if [[ $DRY_RUN -eq 1 ]]; then run tar -xJf "$file" -C "$GBL_NODE_DIR"; NODE_BIN=$GBL_NODE_DIR/bin/node; return 0; fi
    tmp=$(mktemp -d)
    if curl -fsSL --max-time 600 -o "$tmp/$file" "$m/latest-v$GBL_NODE_MAJOR.x/$file" 2>>"$GBL_LOG" &&
      (cd "$tmp" && printf '%s\n' "$sums" | grep " $file\$" | sha256sum -c - >>"$GBL_LOG" 2>&1); then
      mkdir -p "$GBL_NODE_DIR"
      tar -xJf "$tmp/$file" -C "$GBL_NODE_DIR" --strip-components=1
      touch "$GBL_NODE_DIR/.installed-by-grokbot-lite"
      rm -rf "$tmp"
      NODE_BIN=$GBL_NODE_DIR/bin/node
      ok "Node $("$NODE_BIN" --version) 已装到 $GBL_NODE_DIR（sha256 已校验）"
      return 0
    fi
    rm -rf "$tmp"; warn "$m 下载或校验失败，换下一个镜像"
  done
  fail "无法下载 Node.js $GBL_NODE_MAJOR" "网络受限时可指定镜像：GBL_NODE_MIRRORS=https://npmmirror.com/mirrors/node，或手动把 Node 22 解压到 $GBL_NODE_DIR。"
}

ensure_user() {
  step "创建专用用户 $GBL_SERVICE_USER（非 root、无 sudo）"
  if id "$GBL_SERVICE_USER" >/dev/null 2>&1; then
    ok "用户已存在（跳过）"
  else
    run useradd --create-home --shell /bin/bash "$GBL_SERVICE_USER"
    run passwd -l "$GBL_SERVICE_USER" >/dev/null 2>&1 || true
    ok "已创建 $GBL_SERVICE_USER（密码已锁定，只能由 root 切换进入）"
  fi
  if id -nG "$GBL_SERVICE_USER" 2>/dev/null | tr ' ' '\n' | grep -qxE 'sudo|wheel|admin'; then
    warn "$GBL_SERVICE_USER 在 sudo 组里！远端命令可能拿到 root。建议：sudo deluser $GBL_SERVICE_USER sudo"
  fi
  if [[ $(loginctl show-user "$GBL_SERVICE_USER" -p Linger --value 2>/dev/null) != yes ]]; then
    run loginctl enable-linger "$GBL_SERVICE_USER"
  fi
  local uid i
  uid=$(id -u "$GBL_SERVICE_USER" 2>/dev/null || echo 0)
  for ((i = 0; i < 20 && DRY_RUN == 0; i++)); do [[ -S /run/user/$uid/bus || -d /run/user/$uid/systemd ]] && break; sleep 0.5; done
  ok "linger 已开启（开机无需登录就会启动服务）"
}

fetch() { # URL DEST
  curl -fsSL --max-time 120 -o "$2" "$1" 2>>"$GBL_LOG"
}

install_cli() {
  step "安装 grokbot-lite 命令"
  local here=""
  [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]] && here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  if [[ -n $here && -f $here/bin/grokbot-lite ]]; then
    run install -m 0755 "$here/bin/grokbot-lite" "$GBL_CLI_PATH"
  elif [[ $DRY_RUN -eq 0 ]]; then
    local tmp; tmp=$(mktemp)
    fetch "$GBL_REPO_RAW/bin/grokbot-lite" "$tmp" || fail "下载 grokbot-lite 失败" "检查 GBL_REPO_RAW=$GBL_REPO_RAW 是否可访问"
    bash -n "$tmp" || fail "下载的 grokbot-lite 不完整" "重试一次"
    install -m 0755 "$tmp" "$GBL_CLI_PATH"; rm -f "$tmp"
  fi
  if [[ $DRY_RUN -eq 0 ]]; then
    install -d -m 0755 "$(dirname "$GBL_BACKUP_DIR")" "$GBL_BACKUP_DIR"
    printf 'GBL_SERVICE_USER=%s\nGBL_BACKUP_DIR=%s\n' "$GBL_SERVICE_USER" "$GBL_BACKUP_DIR" >"$GBL_CONF"
  fi
  ok "$GBL_CLI_PATH（配置：$GBL_CONF）"
}

flip_fuse() {
  step "备份官方二进制并只打开 RunAsNode 开关"
  [[ -f $GBL_BINARY || $DRY_RUN -eq 1 ]] || fail "找不到 $GBL_BINARY" "grok-bot 包好像没装好：sudo apt-get install --reinstall grok-bot"
  local state
  state=$(GBL_CONF=$GBL_CONF "$GBL_CLI_PATH" read-fuse "$GBL_BINARY" 2>/dev/null | awk '$1 == "RunAsNode" {print $2}') || state=""
  if [[ $state == enabled ]]; then ok "RunAsNode 已经是打开状态（跳过）"; return 0; fi
  [[ $state == removed ]] && fail "这个版本的 grok-bot 把 RunAsNode 编译掉了" "本方法暂不支持该版本，请到项目 issue 反馈版本号。"
  run env GBL_CONF="$GBL_CONF" "$GBL_CLI_PATH" --yes fix >>"$GBL_LOG" 2>&1 || fail "修改 fuse 失败" "看日志：tail -n 30 $GBL_LOG"
  ok "已备份到 $GBL_BACKUP_DIR，并且只改了 1 个字节"
}

install_supervisor() {
  step "安装监督进程 grokbot-headless（固定版本 ${GBL_SUPERVISOR_REF:0:7}）"
  local home src
  home=$(getent passwd "$GBL_SERVICE_USER" | cut -d: -f6)
  [[ -n $home ]] || home=/home/$GBL_SERVICE_USER
  if [[ -x $home/.local/bin/grok-bot-headless && -f $home/.config/systemd/user/grok-bot-headless.service ]]; then
    ok "已安装（跳过）"
  else
    src=$home/src/grokbot-headless-${GBL_SUPERVISOR_REF:0:7}
    if [[ $DRY_RUN -eq 0 ]]; then
      local tmp; tmp=$(mktemp)
      fetch "$GBL_SUPERVISOR_TARBALL" "$tmp" || fail "下载 grokbot-headless 失败" "GitHub 访问不稳定时，可设置 GBL_SUPERVISOR_TARBALL 为可访问的镜像地址后重试。"
      install -d -o "$GBL_SERVICE_USER" -g "$GBL_SERVICE_USER" "$home/src" "$src"
      tar -xzf "$tmp" -C "$src" --strip-components=1; rm -f "$tmp"
      chown -R "$GBL_SERVICE_USER:" "$src"
    fi
    as_user bash -c "cd '$src' && ./install.sh" >>"$GBL_LOG" 2>&1 ||
      fail "grokbot-headless 安装失败（通常是 Node 版本或 check --local 不通过）" "看日志：tail -n 40 $GBL_LOG"
    ok "监督进程已安装"
  fi
  # the systemd --user service does not see $GBL_NODE_DIR in PATH: pin the node binary
  if [[ $NODE_BIN != /usr/bin/node && $DRY_RUN -eq 0 ]]; then
    # shellcheck disable=SC2016  # ${HOME} and $@ must stay literal in the generated wrapper
    printf '#!/usr/bin/env sh\nset -eu\n\nexec %s "${HOME}/.local/lib/grok-bot-headless/grok-bot-headless.mjs" "$@"\n' "$NODE_BIN" \
      >"$home/.local/bin/grok-bot-headless"
    chown "$GBL_SERVICE_USER:" "$home/.local/bin/grok-bot-headless"; chmod 0755 "$home/.local/bin/grok-bot-headless"
    note "启动脚本已固定使用 $NODE_BIN"
  fi
  as_user "$home/.local/bin/grok-bot-headless" check --local >>"$GBL_LOG" 2>&1 ||
    fail "兼容性自检（check --local）没通过" "确认 RunAsNode 已打开：grokbot-lite read-fuse；看日志：tail -n 30 $GBL_LOG"
  ok "check --local 通过"
  as_user systemctl --user daemon-reload
  as_user systemctl --user enable grok-bot-headless.service >>"$GBL_LOG" 2>&1
  as_user "$GBL_CLI_PATH" install-timer >>"$GBL_LOG" 2>&1 || warn "体检定时器安装失败（不影响使用）"
}

logged_in() {
  local home; home=$(getent passwd "$GBL_SERVICE_USER" | cut -d: -f6)
  [[ -f $home/.config/grok-bot-headless/credentials.json ]]
}

extract_login_url() { grep -oE 'https://[^[:space:]"<>]+' | grep -m1 -iE 'login|auth|challenge' || true; }

show_login_box() { # URL
  local url=$1 line
  line=$(printf '%*s' 66 '' | tr ' ' '=')
  printf '\n%s%s%s\n' "$Y$W" "$line" "$N" >&2
  printf '%s  请在【你自己的】浏览器里打开下面的链接，并登录【正确的】Grok Bot 账号%s\n' "$Y$W" "$N" >&2
  printf '%s  链接一次性有效，约 %d 分钟内完成；不要发给任何人%s\n' "$Y" $((GBL_LOGIN_WINDOW_SEC / 60)) "$N" >&2
  printf '%s%s%s\n\n' "$Y$W" "$line" "$N" >&2
  printf '  %s%s%s\n\n' "$C$W" "$url" "$N" >&2
  if command -v qrencode >/dev/null; then
    note "也可以用手机扫码："
    qrencode -t ANSIUTF8 -m 1 "$url" >&2 || true
  else
    note "（安装 qrencode 可显示二维码：sudo apt-get install qrencode）"
  fi
  printf '%s%s%s\n' "$Y$W" "$line" "$N" >&2
}

do_login() { # runs grok-bot-headless login as the service user, shows the link + countdown
  step "登录 Grok Bot 账号"
  local home out pid url="" start left
  home=$(getent passwd "$GBL_SERVICE_USER" | cut -d: -f6)
  command -v qrencode >/dev/null || apt_quiet install -y --no-install-recommends qrencode || true
  if [[ $DRY_RUN -eq 1 ]]; then run "$home/.local/bin/grok-bot-headless" login; return 0; fi
  out=$(mktemp)
  as_user "$home/.local/bin/grok-bot-headless" login >"$out" 2>&1 &
  pid=$!
  start=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    if [[ -z $url ]]; then
      url=$(extract_login_url <"$out")
      [[ -n $url ]] && show_login_box "$url"
    else
      left=$((GBL_LOGIN_WINDOW_SEC - ($(date +%s) - start)))
      ((left < 0)) && left=0
      printf '\r  %s⏳ 等待你在浏览器完成登录…剩余约 %02d:%02d %s' "$D" $((left / 60)) $((left % 60)) "$N" >&2
    fi
    sleep 1
  done
  printf '\n' >&2
  cat "$out" >>"$GBL_LOG"
  if ! wait "$pid"; then
    rm -f "$out"
    fail "登录没有完成（超时或被取消）" "重新运行本脚本即可生成新链接（已完成的步骤会自动跳过）。"
  fi
  rm -f "$out"
  ok "登录成功"
}

after_login() {
  step "设置策略为 ask 并启动服务"
  local home; home=$(getent passwd "$GBL_SERVICE_USER" | cut -d: -f6)
  as_user "$home/.local/bin/grok-bot-headless" policy ask >>"$GBL_LOG" 2>&1 || fail "设置 policy ask 失败" "看日志：tail -n 20 $GBL_LOG"
  ok "策略：ask（每条远程命令都要你批准）"
  as_user systemctl --user daemon-reload
  as_user systemctl --user restart grok-bot-headless.service
  local i
  for ((i = 0; i < 20 && DRY_RUN == 0; i++)); do
    as_user systemctl --user is-active --quiet grok-bot-headless.service && break; sleep 1
  done
  sleep "${GBL_SETTLE_SEC:-6}"
  ok "服务已启动"
}

summary() {
  step "体检"
  local json="" d s
  as_user "$GBL_CLI_PATH" doctor >&2 || true
  json=$(as_user "$GBL_CLI_PATH" status --json 2>/dev/null) || json=""
  d=$(printf '%s' "$json" | sed -n 's/.*"daemon":{[^}]*"rssKiB":\([0-9]*\).*/\1/p')
  s=$(printf '%s' "$json" | sed -n 's/.*"supervisor":{[^}]*"rssKiB":\([0-9]*\).*/\1/p')
  printf '\n%s╔══════════════════════════════════════════════════════════╗%s\n' "$G$W" "$N" >&2
  printf '%s  🎉 安装完成！这台机器现在可以被 Grok Bot 远程使用了%s\n' "$G$W" "$N" >&2
  [[ -n $d ]] && printf '%s  后台 %d MB + 监督进程 %d MB = 约 %d MB 内存%s\n' "$G" $((d / 1024)) $((${s:-0} / 1024)) $(((d + ${s:-0}) / 1024)) "$N" >&2
  printf '%s  整机：已用 %s MB / 共 %s MB%s\n' "$G" "$(free -m | awk '/^Mem:/ {print $3}')" "$(mem_total_mb)" "$N" >&2
  printf '%s╚══════════════════════════════════════════════════════════╝%s\n' "$G$W" "$N" >&2
  cat >&2 <<EOF
  常用命令（root 下运行）：
    grokbot-lite doctor                 体检
    grokbot-lite fix --restart          apt 升级 grok-bot 后修复
    curl -fsSL $GBL_REPO_RAW/install.sh | sudo bash -s -- --switch-account   换账号
  在 Grok Bot 里看不到这台机器？多半是登录错了账号 —— 用上面的 --switch-account。
EOF
}

# ---------------------------------------------------------------- modes
mode_install() {
  preflight
  maybe_swap
  install_grok_bot
  ensure_node
  ensure_user
  install_cli
  flip_fuse
  install_supervisor
  if [[ $DO_LOGIN -eq 0 ]]; then
    note "跳过登录（--no-login）。之后运行：sudo bash install.sh --switch-account"; return 0
  fi
  if logged_in; then
    ok "已登录过（跳过登录；要换账号用 --switch-account）"
  else
    do_login
  fi
  after_login
  summary
}

mode_switch_account() {
  is_root || fail "需要 root 权限" "sudo bash install.sh --switch-account"
  id "$GBL_SERVICE_USER" >/dev/null 2>&1 || fail "没找到用户 $GBL_SERVICE_USER" "先完整安装一次。"
  local home; home=$(getent passwd "$GBL_SERVICE_USER" | cut -d: -f6)
  step "退出当前账号"
  ask "确定退出当前 Grok Bot 账号并重新登录？" y || { note "已取消"; return 0; }
  as_user "$home/.local/bin/grok-bot-headless" logout >>"$GBL_LOG" 2>&1 || true
  ok "已退出（服务已停止）"
  do_login
  after_login
  summary
}

mode_uninstall() {
  is_root || fail "需要 root 权限" "sudo bash install.sh --uninstall"
  step "卸载 grokbot-lite"
  ask "停止服务、移除体检定时器，并把 grok-bot 恢复成官方原版？" y || { note "已取消"; return 0; }
  local home=""
  if id "$GBL_SERVICE_USER" >/dev/null 2>&1; then
    home=$(getent passwd "$GBL_SERVICE_USER" | cut -d: -f6)
    as_user systemctl --user disable --now grokbot-lite-doctor.timer >>"$GBL_LOG" 2>&1 || true
    as_user systemctl --user disable --now grok-bot-headless.service >>"$GBL_LOG" 2>&1 || true
    ok "服务已停止"
    if [[ -x $home/.local/bin/grok-bot-headless ]] && ask "同时退出 Grok Bot 账号并删除本机凭据？" y; then
      as_user "$home/.local/bin/grok-bot-headless" logout >>"$GBL_LOG" 2>&1 || true
      ok "凭据已删除"
    fi
  fi
  if [[ -x $GBL_CLI_PATH ]]; then
    if run env GBL_CONF="$GBL_CONF" "$GBL_CLI_PATH" --yes restore >>"$GBL_LOG" 2>&1; then ok "grok-bot 已恢复原版"
    else warn "没有匹配的备份；可用 sudo apt-get install --reinstall grok-bot 恢复原版"; fi
  fi
  if id "$GBL_SERVICE_USER" >/dev/null 2>&1 && ask "删除用户 $GBL_SERVICE_USER 及其主目录？" n; then
    run loginctl disable-linger "$GBL_SERVICE_USER" || true
    run userdel -r "$GBL_SERVICE_USER" >>"$GBL_LOG" 2>&1 || warn "删除用户失败（可能有进程仍在运行）"
  fi
  if dpkg-query -W grok-bot >/dev/null 2>&1 && ask "卸载官方 grok-bot 包（约 350 MB）？" n; then
    apt_quiet purge -y grok-bot || warn "卸载 grok-bot 失败"
  fi
  if [[ -f $GBL_NODE_DIR/.installed-by-grokbot-lite ]] && ask "删除脚本安装的 $GBL_NODE_DIR？" n; then
    run rm -rf "$GBL_NODE_DIR"
  fi
  run rm -f "$GBL_CLI_PATH" "$GBL_CONF"
  ok "卸载完成（备份保留在 $GBL_BACKUP_DIR，可手动删除）"
}

usage() {
  cat <<EOF
grokbot-lite installer $INSTALLER_VERSION

用法：curl -fsSL <地址>/install.sh | sudo bash -s -- [选项]
  （无参数）          安装 / 修复（可重复运行，已完成的步骤会跳过）
  --yes, -y           全自动，所有问题使用默认（安全）选项
  --switch-account    退出当前账号并重新登录（登录错账号时用）
  --uninstall         卸载并恢复官方原版二进制
  --no-login          只安装，不登录
  --user NAME         服务用户名（默认 grokbot）
  --dry-run           只打印将要执行的操作
  --log FILE          日志文件（默认 $GBL_LOG）
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -y | --yes) YES=1 ;;
      --switch-account) MODE=switch ;;
      --uninstall) MODE=uninstall ;;
      --no-login) DO_LOGIN=0 ;;
      --dry-run) DRY_RUN=1 ;;
      --user) GBL_SERVICE_USER=${2:?--user 需要用户名}; shift ;;
      --log) GBL_LOG=${2:?--log 需要文件路径}; shift ;;
      -h | --help) usage; exit 0 ;;
      *) usage >&2; exit 2 ;;
    esac
    shift
  done
  [[ $GBL_SERVICE_USER =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] || fail "用户名不合法：$GBL_SERVICE_USER" "只能用小写字母、数字、_ 和 -"
  [[ $GBL_SERVICE_USER != root ]] || fail "不能用 root 作为服务用户" "这正是本项目要避免的事"
}

main() {
  setup_colors
  parse_args "$@"
  mkdir -p "$(dirname "$GBL_LOG")" 2>/dev/null || true
  { : >>"$GBL_LOG"; } 2>/dev/null || GBL_LOG=$(mktemp /tmp/grokbot-lite-install.XXXX.log)
  chmod 600 "$GBL_LOG" 2>/dev/null || true   # may contain the one-time login link
  printf '\n===== %s installer %s mode=%s =====\n' "$(date '+%F %T %z')" "$INSTALLER_VERSION" "$MODE" >>"$GBL_LOG"
  banner
  case $MODE in
    install) mode_install ;;
    switch) mode_switch_account ;;
    uninstall) mode_uninstall ;;
  esac
}

if [[ -z ${GBL_INSTALLER_SOURCED:-} ]]; then main "$@"; fi
