#!/usr/bin/env bats
load helpers/common

setup() { setup_env; }
teardown() { teardown_env; }

@test "doctor: healthy system exits 0" {
  make_bin "$GBL_BINARY" 48 49 48
  "$GBL" --yes fix
  healthy_state
  run "$GBL" doctor
  [ "$status" -eq 0 ]
  [[ $output == *"[ OK ] fuse"* ]]
  [[ $output == *"0 failure(s), 0 warning(s)"* ]]
}

@test "doctor: fuse reset by an upgrade is a failure that names the fix" {
  make_bin "$GBL_BINARY" 48 49 48
  healthy_state
  run "$GBL" doctor
  [ "$status" -eq 2 ]
  [[ $output == *"[FAIL] fuse"*"grokbot-lite fix"* ]]
}

@test "doctor: passwordless sudo is a warning" {
  make_bin "$GBL_BINARY" 48 49 48
  "$GBL" --yes fix
  healthy_state
  export MOCK_SUDO_NOPASSWD_RC=0
  run "$GBL" doctor
  [ "$status" -eq 1 ]
  [[ $output == *"[WARN] sudo"* ]]
}

@test "doctor: policy always + passwordless sudo is a failure" {
  make_bin "$GBL_BINARY" 48 49 48
  "$GBL" --yes fix
  healthy_state
  printf '{"localToolPermission": "always"}\n' >"$HOME/.local/share/grok-bot-headless/settings.json"
  export MOCK_SUDO_NOPASSWD_RC=0
  run "$GBL" doctor
  [ "$status" -eq 2 ]
  [[ $output == *"[FAIL] policy"*"unattended remote root"* ]]
}

@test "doctor: missing login, dead daemon, no linger" {
  make_bin "$GBL_BINARY" 49 49 48
  export MOCK_LINGER=no MOCK_ACTIVE=inactive
  run "$GBL" doctor
  [ "$status" -eq 2 ]
  [[ $output == *"[FAIL] login"* ]]
  [[ $output == *"[FAIL] daemon"* ]]
  [[ $output == *"[WARN] linger"* ]]
  [[ $output == *"[WARN] backup"* ]]
}

@test "doctor never reads credential files" {
  make_bin "$GBL_BINARY" 49 49 48
  healthy_state
  chmod 000 "$HOME/.config/grok-bot-headless/credentials.json"
  run "$GBL" doctor
  [[ $output == *"credentials present"* ]]
}

@test "doctor is read-only without --notify" {
  make_bin "$GBL_BINARY" 48 49 48
  healthy_state
  before=$(sha256sum "$GBL_BINARY")
  "$GBL" doctor || true
  [ "$(sha256sum "$GBL_BINARY")" = "$before" ]
  [ ! -e "$HOME/.local/state/grokbot-lite" ]
  ! grep -Eq "^sudo (install|mv|loginctl)|systemctl --user (restart|stop|enable)|grok-bot-headless (policy|login)" "$MOCK_LOG"
}

@test "status --json is valid JSON with the expected fields" {
  make_bin "$GBL_BINARY" 48 49 48
  "$GBL" --yes fix
  healthy_state
  run "$GBL" status --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["fuse"]["runAsNode"] == "enabled", d
assert d["binary"]["packageVersion"] == "0.71.2"
assert d["backup"]["forInstalledVersion"] is True
assert d["backup"]["relationToInstalled"] == "runasnode-only", d["backup"]
assert d["fuse"]["wireVersion"] == 1 and d["fuse"]["wireLength"] == 3, d["fuse"]
assert d["daemon"]["running"] is True and d["daemon"]["rssKiB"] > 0
assert d["policy"]["value"] == "ask"
assert d["passwordlessSudo"] == "no"
'
}

@test "doctor --json includes checks and summary" {
  make_bin "$GBL_BINARY" 48 49 48
  healthy_state
  run "$GBL" doctor --json
  [ "$status" -eq 2 ]
  printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["summary"]["failures"] >= 1
assert any(c["check"] == "fuse" and c["level"] == "fail" for c in d["checks"])
'
}

@test "doctor --notify alerts once per transition and logs every run" {
  make_bin "$GBL_BINARY" 48 49 48
  healthy_state
  export GBL_NOTIFY_CMD="cat >>'$BATS_TEST_TMPDIR/notes'"
  "$GBL" doctor --quiet --notify || true
  "$GBL" doctor --quiet --notify || true
  [ "$(grep -c "RunAsNode fuse is 'disabled'" "$BATS_TEST_TMPDIR/notes")" -eq 1 ]
  [ "$(wc -l <"$HOME/.local/state/grokbot-lite/doctor.log")" -eq 2 ]
  "$GBL" --yes fix
  "$GBL" doctor --quiet --notify || true
  grep -q "enabled again" "$BATS_TEST_TMPDIR/notes"
}

@test "doctor: live binary that differs from backup beyond the fuse byte is a warning" {
  make_bin "$GBL_BINARY" 48 49 48
  "$GBL" --yes fix
  healthy_state
  printf 'X' | dd of="$GBL_BINARY" bs=1 seek=10 conv=notrunc status=none
  run "$GBL" doctor
  [ "$status" -eq 1 ]
  [[ $output == *"[WARN] backup"*"beyond the RunAsNode byte"* ]]
}

@test "doctor: reports wire version and length" {
  make_bin "$GBL_BINARY" 49 49 48 48
  healthy_state
  run "$GBL" doctor
  [[ $output == *"RunAsNode enabled (wire v1, 4 fuses)"* ]]
}
