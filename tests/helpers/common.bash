# shellcheck shell=bash disable=SC2034  # variables are used by the .bats files
# Shared bats helpers: an isolated $HOME, mocked system commands and fake
# Electron binaries.  No real grok-bot binary, sudo or systemd is touched.
REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
GBL="$REPO_ROOT/bin/grokbot-lite"
SENTINEL=dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX

# make_bin PATH BYTE... : write a fake Electron binary whose fuse wire holds BYTE...
make_bin() {
  local path=$1; shift
  local wire="" b
  for b in "$@"; do wire+=$(printf '\\%03o' "$b"); done
  {
    head -c 4096 /dev/zero
    printf 'some ELF-ish padding Electron/30.1.2 more padding'
    printf '%s' "$SENTINEL"
    # shellcheck disable=SC2059  # $wire holds octal escapes that printf must expand
    printf "\\001\\$(printf '%03o' $#)$wire"
    head -c 4096 /dev/zero
  } >"$path"
  chmod 0755 "$path"
}

# wire_of PATH -> decimal fuse bytes
wire_of() {
  local off len
  off=$(LC_ALL=C grep -obaF "$SENTINEL" "$1" | cut -d: -f1)
  len=$(dd if="$1" bs=1 skip=$((off + 33)) count=1 status=none | od -An -tu1 | tr -d ' ')
  dd if="$1" bs=1 skip=$((off + 34)) count="$len" status=none | od -An -v -tu1 | xargs
}

setup_env() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"
  export MOCKBIN="$BATS_TEST_TMPDIR/mockbin"
  mkdir -p "$HOME/.local/bin" "$HOME/.config/grok-bot-headless" "$HOME/.local/share/grok-bot-headless" "$MOCKBIN"
  : >"$MOCK_LOG"
  export GBL_SUDO_PROBE_ALWAYS=1 NO_COLOR=1 USER=tester GBL_CONF="$BATS_TEST_TMPDIR/none.conf"
  unset XDG_CONFIG_HOME XDG_STATE_HOME GBL_BINARY GROK_BOT_BINARY GBL_PACKAGE_VERSION DBUS_SESSION_BUS_ADDRESS
  export GBL_BINARY="$BATS_TEST_TMPDIR/opt/Grok Bot/grok-bot"
  mkdir -p "$(dirname "$GBL_BINARY")"
  export GBL_SUPERVISOR_BIN="$HOME/.local/bin/grok-bot-headless"
  export GBL_APT_HOOK="$BATS_TEST_TMPDIR/apt.conf.d/99grokbot-lite"
  export GBL_APT_HELPER_DIR="$BATS_TEST_TMPDIR/usr-local-lib/grokbot-lite"
  export MOCK_PKG_VERSION=0.71.2 MOCK_ACTIVE=active MOCK_ENABLED=enabled MOCK_LINGER=yes MOCK_SUDO_NOPASSWD_RC=1

  # sudo: '-n true' answers the passwordless probe, anything else runs as us
  cat >"$MOCKBIN/sudo" <<'M'
#!/usr/bin/env bash
if [[ $1 == -n && $2 == true ]]; then echo "sudo -n true" >>"$MOCK_LOG"; exit "$MOCK_SUDO_NOPASSWD_RC"; fi
echo "sudo $*" >>"$MOCK_LOG"
# drop -o/-g root for install (tests are unprivileged)
if [[ $1 == install ]]; then
  args=(); skip=0
  for a in "$@"; do
    if [[ $skip -eq 1 ]]; then skip=0; continue; fi
    case $a in -o|-g) skip=1; continue ;; esac
    args+=("$a")
  done
  exec "${args[@]}"
fi
exec "$@"
M
  cat >"$MOCKBIN/systemctl" <<'M'
#!/usr/bin/env bash
echo "systemctl $*" >>"$MOCK_LOG"
[[ $1 == --user ]] && shift
case $1 in
  is-active) echo "$MOCK_ACTIVE"; [[ $MOCK_ACTIVE == active ]] ;;
  is-enabled) echo "$MOCK_ENABLED"; [[ $MOCK_ENABLED == enabled ]] ;;
  show) echo "${MOCK_SUP_PID:-0}" ;;
  *) exit 0 ;;
esac
M
  cat >"$MOCKBIN/loginctl" <<'M'
#!/usr/bin/env bash
echo "loginctl $*" >>"$MOCK_LOG"
case $1 in show-user) echo "$MOCK_LINGER" ;; *) exit 0 ;; esac
M
  cat >"$MOCKBIN/dpkg-query" <<'M'
#!/usr/bin/env bash
[[ -n $MOCK_PKG_VERSION ]] && printf '%s' "$MOCK_PKG_VERSION"
M
  cat >"$MOCKBIN/logger" <<'M'
#!/usr/bin/env bash
echo "logger $*" >>"$MOCK_LOG"
M
  cat >"$MOCKBIN/apt-get" <<'M'
#!/usr/bin/env bash
echo "apt-get $*" >>"$MOCK_LOG"
M
  # upstream supervisor CLI mock
  cat >"$GBL_SUPERVISOR_BIN" <<'M'
#!/usr/bin/env bash
echo "grok-bot-headless $*" >>"$MOCK_LOG"
if [[ $1 == policy ]]; then
  printf '{\n  "version": 1,\n  "localToolPermission": "%s"\n}\n' "$2" >"$HOME/.local/share/grok-bot-headless/settings.json"
fi
M
  chmod +x "$MOCKBIN"/* "$GBL_SUPERVISOR_BIN"
  export PATH="$MOCKBIN:$PATH"
}

# healthy_state: logged in, policy ask, daemon + supervisor processes alive
healthy_state() {
  : >"$HOME/.config/grok-bot-headless/credentials.json"
  : >"$HOME/.config/grok-bot-headless/machine.json"
  printf '{\n  "version": 1,\n  "localToolPermission": "ask"\n}\n' >"$HOME/.local/share/grok-bot-headless/settings.json"
  sleep 300 &
  DAEMON_PID=$!
  sleep 300 &
  export MOCK_SUP_PID=$!
  printf '{"pid":%s,"port":1234}\n' "$DAEMON_PID" >"$HOME/.local/share/grok-bot-headless/local-exec-daemon.json"
  printf '{"ts":1}\n' >"$HOME/.local/share/grok-bot-headless/local-exec-supervisor.json"
  mkdir -p "$HOME/.config/systemd/user"
  : >"$HOME/.config/systemd/user/grokbot-lite-doctor.timer"
}

teardown_env() {
  if [[ -n ${DAEMON_PID:-} ]]; then kill "$DAEMON_PID" 2>/dev/null || true; fi
  if [[ -n ${MOCK_SUP_PID:-} ]]; then kill "$MOCK_SUP_PID" 2>/dev/null || true; fi
}
