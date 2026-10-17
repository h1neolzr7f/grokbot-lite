#!/usr/bin/env bats
load helpers/common

setup() { setup_env; }
teardown() { teardown_env; }

@test "restore puts the exact original back" {
  make_bin "$GBL_BINARY" 48 49 48
  orig=$(sha256sum "$GBL_BINARY" | cut -d' ' -f1)
  "$GBL" --yes fix
  run "$GBL" --yes restore
  [ "$status" -eq 0 ]
  [ "$(sha256sum "$GBL_BINARY" | cut -d' ' -f1)" = "$orig" ]
}

@test "restore refuses a backup that no longer matches its .sha256" {
  make_bin "$GBL_BINARY" 48 49 48
  "$GBL" --yes fix
  printf 'x' >>"$HOME/.local/share/grok-bot-backup/grok-bot.0.71.2"
  run "$GBL" --yes restore
  [ "$status" -ne 0 ]
  [[ $output == *"does not match"* ]]
}

@test "restore refuses another version's backup unless --force" {
  make_bin "$GBL_BINARY" 48 49 48
  "$GBL" --yes fix
  export MOCK_PKG_VERSION=0.72.0
  run "$GBL" --yes restore
  [ "$status" -ne 0 ]
  [[ $output == *"no backup for installed version 0.72.0"* ]]
  run "$GBL" --yes restore --force
  [ "$status" -eq 0 ]
}

@test "after an upgrade fix makes a new backup for the new version" {
  make_bin "$GBL_BINARY" 48 49 48
  "$GBL" --yes fix
  make_bin "$GBL_BINARY" 48 49 49      # 'apt upgrade' drops in a new pristine binary
  export MOCK_PKG_VERSION=0.72.0
  run "$GBL" --yes fix --restart
  [ "$status" -eq 0 ]
  [ -f "$HOME/.local/share/grok-bot-backup/grok-bot.0.72.0" ]
  [ "$(wire_of "$GBL_BINARY")" = "49 49 49" ]
  grep -q "systemctl --user restart grok-bot-headless.service" "$MOCK_LOG"
}

@test "apt-check is silent when the fuse is enabled" {
  make_bin "$GBL_BINARY" 49 49 48
  run "$GBL" apt-check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "apt-check warns (and still exits 0) when the fuse was reset" {
  make_bin "$GBL_BINARY" 48 49 48
  run "$GBL" apt-check
  [ "$status" -eq 0 ]
  [[ $output == *"grokbot-lite fix --restart"* ]]
  [ "$(wire_of "$GBL_BINARY")" = "48 49 48" ]
}

@test "install-apt-hook writes a warn-only hook (no npx, no fix)" {
  make_bin "$GBL_BINARY" 49 49 48
  mkdir -p "$(dirname "$GBL_APT_HOOK")"
  run "$GBL" --yes install-apt-hook
  [ "$status" -eq 0 ]
  grep -q 'DPkg::Post-Invoke' "$GBL_APT_HOOK"
  grep -q 'apt-check || true' "$GBL_APT_HOOK"
  ! grep -Eq 'npx|fuses write| fix' "$GBL_APT_HOOK"
  [ -x "$GBL_APT_HELPER_DIR/grokbot-lite" ]
}

@test "embedded systemd units match the files in systemd/" {
  diff <(sed -n '/^unit_doctor_service() {/,/^}/p' "$GBL" | sed '1,2d;$d' | sed '$d') "$REPO_ROOT/systemd/grokbot-lite-doctor.service"
  diff <(sed -n '/^unit_doctor_timer() {/,/^}/p' "$GBL" | sed '1,2d;$d' | sed '$d') "$REPO_ROOT/systemd/grokbot-lite-doctor.timer"
}

@test "compat/detect.sh agrees with the CLI" {
  make_bin "$GBL_BINARY" 48 49 48 48 144
  run sh "$REPO_ROOT/compat/detect.sh" "$GBL_BINARY"
  [ "$status" -eq 0 ]
  [[ $output == *"version=0.71.2"* ]]
  [[ $output == *"electron=30.1.2"* ]]
  [[ $output == *"fuse_wire=48 49 48 48 144"* ]]
  [[ $output == *"RunAsNode=disabled"* ]]
  run sh "$REPO_ROOT/compat/detect.sh" --json "$GBL_BINARY"
  printf '%s' "$output" | python3 -m json.tool >/dev/null
}

@test "version and help" {
  run "$GBL" version
  [[ $output == "grokbot-lite "* ]]
  run "$GBL" help
  [[ $output == *"doctor"* && $output == *"restore"* ]]
  run "$GBL" bogus
  [ "$status" -ne 0 ]
}

@test "refuses to run state-changing commands as root" {
  [ "$(id -u)" -eq 0 ] || skip "only meaningful as root"
  make_bin "$GBL_BINARY" 48 49 48
  run "$GBL" --yes fix
  [ "$status" -ne 0 ]
}
