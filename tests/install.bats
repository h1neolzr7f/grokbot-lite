#!/usr/bin/env bats
load helpers/common

setup() { setup_env; }
teardown() { teardown_env; }

@test "install end-to-end with mocks" {
  make_bin "$GBL_BINARY" 48 49 48
  : >"$HOME/.config/grok-bot-headless/credentials.json"
  export MOCK_LINGER=no
  run "$GBL" --yes install
  [ "$status" -eq 0 ]
  [ "$(wire_of "$GBL_BINARY")" = "49 49 48" ]
  [ -f "$HOME/.local/share/grok-bot-backup/grok-bot.0.71.2" ]
  grep -q "systemctl --user enable grok-bot-headless.service" "$MOCK_LOG"
  grep -q "sudo loginctl enable-linger tester" "$MOCK_LOG"
  grep -q "grok-bot-headless policy ask" "$MOCK_LOG"
  grep -q "systemctl --user enable --now grokbot-lite-doctor.timer" "$MOCK_LOG"
  [ -x "$HOME/.local/bin/grokbot-lite" ]
  [ -f "$HOME/.config/systemd/user/grokbot-lite-doctor.timer" ]
  ! grep -q "restart grok-bot-headless" "$MOCK_LOG"
}

@test "install never sets policy always, and fixes an existing always" {
  make_bin "$GBL_BINARY" 48 49 48
  : >"$HOME/.config/grok-bot-headless/credentials.json"
  printf '{"localToolPermission": "always"}\n' >"$HOME/.local/share/grok-bot-headless/settings.json"
  run "$GBL" --yes install
  [ "$status" -eq 0 ]
  ! grep -q "policy always" "$MOCK_LOG"
  grep -q '"localToolPermission": "ask"' "$HOME/.local/share/grok-bot-headless/settings.json"
}

@test "install before login prints next steps instead of calling policy" {
  make_bin "$GBL_BINARY" 48 49 48
  run "$GBL" --yes install
  [ "$status" -eq 0 ]
  [[ $output == *"login"* ]]
  ! grep -q "grok-bot-headless policy" "$MOCK_LOG"
}

@test "install without supervisor and without --supervisor-src stops after the fuse step" {
  make_bin "$GBL_BINARY" 48 49 48
  rm "$GBL_SUPERVISOR_BIN"
  run "$GBL" --yes install
  [ "$status" -ne 0 ]
  [[ $output == *"--supervisor-src"* ]]
}

@test "install --dry-run touches nothing" {
  make_bin "$GBL_BINARY" 48 49 48
  : >"$HOME/.config/grok-bot-headless/credentials.json"
  run "$GBL" --dry-run install
  [ "$status" -eq 0 ]
  [ "$(wire_of "$GBL_BINARY")" = "48 49 48" ]
  [ ! -e "$HOME/.config/systemd/user/grokbot-lite-doctor.timer" ]
  ! grep -Eq "^sudo |grok-bot-headless policy|enable" "$MOCK_LOG"
}

@test "uninstall removes timer + CLI and restores the original binary" {
  make_bin "$GBL_BINARY" 48 49 48
  orig=$(sha256sum "$GBL_BINARY" | cut -d' ' -f1)
  : >"$HOME/.config/grok-bot-headless/credentials.json"
  "$GBL" --yes install
  run "$GBL" --yes uninstall --purge
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.config/systemd/user/grokbot-lite-doctor.timer" ]
  [ ! -e "$HOME/.local/bin/grokbot-lite" ]
  [ "$(sha256sum "$GBL_BINARY" | cut -d' ' -f1)" = "$orig" ]
  [ -f "$HOME/.local/share/grok-bot-backup/grok-bot.0.71.2" ]   # backups kept unless --purge-backups
}

@test "uninstall --keep-fuse leaves the patched binary" {
  make_bin "$GBL_BINARY" 48 49 48
  "$GBL" --yes fix
  run "$GBL" --yes uninstall --keep-fuse
  [ "$status" -eq 0 ]
  [ "$(wire_of "$GBL_BINARY")" = "49 49 48" ]
}
