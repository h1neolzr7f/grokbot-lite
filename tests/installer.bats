#!/usr/bin/env bats
# Tests for the one-click installer. Everything privileged is mocked.
load helpers/common

setup() {
  setup_env
  export GBL_INSTALLER_SOURCED=1 NO_COLOR=1
  export GBL_LOG="$BATS_TEST_TMPDIR/install.log" GBL_TTY=/nonexistent
  export GBL_CONF="$BATS_TEST_TMPDIR/grokbot-lite.conf" GBL_CLI_PATH="$BATS_TEST_TMPDIR/usr-local-bin/grokbot-lite"
  export GBL_BACKUP_DIR="$BATS_TEST_TMPDIR/var/backup" GBL_NODE_DIR="$BATS_TEST_TMPDIR/opt/node22"
  export GBL_SYSTEMD_RUNDIR="$BATS_TEST_TMPDIR/run-systemd" GBL_LOGIN_WINDOW_SEC=60 GBL_SETTLE_SEC=0
  mkdir -p "$GBL_SYSTEMD_RUNDIR" "$(dirname "$GBL_CLI_PATH")"
  export SVC_HOME="$BATS_TEST_TMPDIR/home-grokbot"
  mkdir -p "$SVC_HOME/.local/bin" "$SVC_HOME/.config/grok-bot-headless"
  # runuser -u USER -- CMD... -> CMD... (as the test user)
  cat >"$MOCKBIN/runuser" <<'M'
#!/usr/bin/env bash
echo "runuser $*" >>"$MOCK_LOG"
shift 3; exec "$@"
M
  cat >"$MOCKBIN/getent" <<'M'
#!/usr/bin/env bash
echo "grokbot:x:1001:1001::$SVC_HOME:/bin/bash"
M
  chmod +x "$MOCKBIN"/*
  export GBL_RUNUSER="$MOCKBIN/runuser"
}

# inst 'CODE' : source the installer in a fresh bash (strict mode and all) and eval CODE
inst() {
  run bash -c 'source "$1"; setup_colors; eval "$2"' _ "$REPO_ROOT/install.sh" "$1"
}
teardown() { teardown_env; }

@test "detect_arch maps 64-bit and rejects 32-bit ARM with a friendly fix" {
  inst "detect_arch x86_64"; [ "$output" = amd64 ]
  inst "detect_arch aarch64"; [ "$output" = arm64 ]
  inst "detect_arch armv7l"
  [ "$status" -ne 0 ]
  [[ $output == *"不支持 32 位 ARM"* && $output == *"64 位系统"* ]]
}

@test "node_major reads versions and treats missing node as 0" {
  printf '#!/bin/sh\necho v18.19.1\n' >"$BATS_TEST_TMPDIR/node18"; chmod +x "$BATS_TEST_TMPDIR/node18"
  inst "node_major '$BATS_TEST_TMPDIR/node18'"; [ "$output" = 18 ]
  inst "node_major /nonexistent/node"; [ "$output" = 0 ]
}

@test "ensure_node reuses an existing Node >= 20 in GBL_NODE_DIR (idempotent)" {
  mkdir -p "$GBL_NODE_DIR/bin"
  printf '#!/bin/sh\necho v22.20.0\n' >"$GBL_NODE_DIR/bin/node"; chmod +x "$GBL_NODE_DIR/bin/node"
  inst 'ARCH=amd64; ensure_node 2>/dev/null; echo "$NODE_BIN"'
  [ "$status" -eq 0 ]
  [ "$output" = "$GBL_NODE_DIR/bin/node" ]
  ! grep -q "curl" "$MOCK_LOG"
}

@test "extract_login_url finds the one-time link in supervisor output" {
  inst "printf 'Open this URL to log in:\\nhttps://example.test/loginDeepControl?challenge=abc&uuid=1\\nWaiting...\\n' | extract_login_url"
  [ "$output" = "https://example.test/loginDeepControl?challenge=abc&uuid=1" ]
}

@test "show_login_box prints the link prominently with a warning" {
  inst 'show_login_box "https://example.test/login?x=1"'
  [[ $output == *"https://example.test/login?x=1"* ]]
  [[ $output == *"不要发给任何人"* ]]
}

@test "ask uses the safe default without a terminal and with --yes" {
  inst 'ask "删除用户？" n'
  [ "$status" -ne 0 ]
  inst 'YES=1; ask "创建 swap？" y'
  [ "$status" -eq 0 ]
}

@test "preflight refuses non-root with a sudo hint" {
  [ "$(id -u)" -ne 0 ] || skip "running as root"
  inst preflight
  [ "$status" -ne 0 ]
  [[ $output == *"需要 root 权限"* && $output == *"sudo bash"* ]]
}

@test "preflight explains missing systemd" {
  export GBL_TEST_AS_ROOT=1 GBL_SYSTEMD_RUNDIR=/nonexistent
  inst preflight
  [ "$status" -ne 0 ]
  [[ $output == *"systemd 没有在运行"* && $output == *"KVM"* ]]
}

@test "preflight explains low disk" {
  export GBL_TEST_AS_ROOT=1 GBL_MIN_DISK_MB=999999999
  inst preflight
  [ "$status" -ne 0 ]
  [[ $output == *"磁盘空间不足"* && $output == *"apt-get clean"* ]]
}

@test "parse_args rejects root and invalid service users" {
  inst "parse_args --user root"
  [ "$status" -ne 0 ]
  inst "parse_args --user 'Bad Name'"
  [ "$status" -ne 0 ]
}

@test "do_login shows the link, waits for the supervisor and reports success" {
  cat >"$SVC_HOME/.local/bin/grok-bot-headless" <<'M'
#!/usr/bin/env bash
echo "grok-bot-headless $*" >>"$MOCK_LOG"
echo "Open https://example.test/loginDeepControl?challenge=zzz in a browser"
sleep 2
M
  chmod +x "$SVC_HOME/.local/bin/grok-bot-headless"
  printf '#!/bin/sh\nexit 0\n' >"$MOCKBIN/qrencode"; chmod +x "$MOCKBIN/qrencode"
  inst do_login
  [ "$status" -eq 0 ]
  [[ $output == *"loginDeepControl?challenge=zzz"* ]]
  [[ $output == *"登录成功"* ]]
}

@test "do_login failure tells the user to re-run for a new link" {
  printf '#!/bin/sh\necho "https://example.test/login?c=1"; exit 1\n' >"$SVC_HOME/.local/bin/grok-bot-headless"
  chmod +x "$SVC_HOME/.local/bin/grok-bot-headless"
  printf '#!/bin/sh\nexit 0\n' >"$MOCKBIN/qrencode"; chmod +x "$MOCKBIN/qrencode"
  inst do_login
  [ "$status" -ne 0 ]
  [[ $output == *"重新运行本脚本"* ]]
}

@test "full installer --dry-run --yes --no-login plans every step and changes nothing" {
  cat >"$MOCKBIN/id" <<'M'
#!/usr/bin/env bash
[[ $* == *grokbot* ]] && exit 1
exec /usr/bin/id "$@"
M
  cat >"$MOCKBIN/dpkg-query" <<'M'
#!/usr/bin/env bash
exit 1
M
  chmod +x "$MOCKBIN"/*
  export GBL_TEST_AS_ROOT=1 GBL_MIN_DISK_MB=1 MOCK_LINGER=no
  inst "main --dry-run --yes --no-login"
  [ "$status" -eq 0 ]
  [[ $output == *"安装官方 grok-bot 包"* ]]
  [[ $output == *"useradd --create-home --shell /bin/bash grokbot"* ]]
  [[ $output == *"loginctl enable-linger grokbot"* ]]
  [[ $output == *"跳过登录"* ]]
  [ ! -e "$GBL_CONF" ]
  ! grep -q '^sudo ' "$MOCK_LOG"
}

@test "installer never asks the supervisor for policy always" {
  ! grep -n "policy always" "$REPO_ROOT/install.sh"
  grep -q "policy ask" "$REPO_ROOT/install.sh"
}

@test "installer runs apt with needrestart in list-only mode" {
  grep -q "NEEDRESTART_MODE=l" "$REPO_ROOT/install.sh"
}

@test "installer is wrapped so a truncated download cannot run" {
  [ "$(tail -n1 "$REPO_ROOT/install.sh")" = 'if [[ -z ${GBL_INSTALLER_SOURCED:-} ]]; then main "$@"; fi' ]
}
