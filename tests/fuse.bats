#!/usr/bin/env bats
load helpers/common

setup() { setup_env; }
teardown() { teardown_env; }

@test "read-fuse names every fuse state" {
  make_bin "$GBL_BINARY" 48 49 48 48 144 114 48 49 48
  run "$GBL" read-fuse
  [ "$status" -eq 0 ]
  [[ $output == *"RunAsNode                                disabled"* ]]
  [[ $output == *"EnableEmbeddedAsarIntegrityValidation    inherit"* ]]
  [[ $output == *"OnlyLoadAppFromAsar                      removed"* ]]
}

@test "fix flips only the RunAsNode byte and keeps every other fuse" {
  make_bin "$GBL_BINARY" 48 49 48 48 144 114 48 49 48
  run "$GBL" --yes fix
  [ "$status" -eq 0 ]
  [ "$(wire_of "$GBL_BINARY")" = "49 49 48 48 144 114 48 49 48" ]
}

@test "fix writes a verified backup of the pristine binary first" {
  make_bin "$GBL_BINARY" 48 49 48
  orig=$(sha256sum "$GBL_BINARY" | cut -d' ' -f1)
  run "$GBL" --yes fix
  [ "$status" -eq 0 ]
  b="$HOME/.local/share/grok-bot-backup/grok-bot.0.71.2"
  [ -f "$b" ]
  [ "$(sha256sum "$b" | cut -d' ' -f1)" = "$orig" ]
  grep -q "^$orig  grok-bot.0.71.2$" "$b.sha256"
  [ "$(wire_of "$b")" = "48 49 48" ]
}

@test "fix replaces the binary by rename (new inode), never writes in place" {
  make_bin "$GBL_BINARY" 48 49 48
  before=$(stat -c %i "$GBL_BINARY")
  run "$GBL" --yes fix
  [ "$status" -eq 0 ]
  [ "$(stat -c %i "$GBL_BINARY")" != "$before" ]
  grep -q "^sudo mv -f -- " "$MOCK_LOG"
}

@test "fix is idempotent and needs no sudo when already enabled" {
  make_bin "$GBL_BINARY" 49 49 48
  run "$GBL" --yes fix
  [ "$status" -eq 0 ]
  [[ $output == *"already enabled"* ]]
  ! grep -q "^sudo install" "$MOCK_LOG"
}

@test "fix refuses a REMOVED RunAsNode fuse" {
  make_bin "$GBL_BINARY" 114 49 48
  run "$GBL" --yes fix
  [ "$status" -ne 0 ]
  [ "$(wire_of "$GBL_BINARY")" = "114 49 48" ]
}

@test "binary without a sentinel is rejected" {
  head -c 9000 /dev/zero >"$GBL_BINARY"
  run "$GBL" --yes fix
  [ "$status" -ne 0 ]
  [[ $output == *"no Electron fuse sentinel"* ]]
}

@test "binary with two sentinels is rejected" {
  make_bin "$GBL_BINARY" 48 49
  cat "$GBL_BINARY" "$GBL_BINARY" >"$GBL_BINARY.2" && mv "$GBL_BINARY.2" "$GBL_BINARY"
  run "$GBL" read-fuse
  [ "$status" -ne 0 ]
  [[ $output == *"more than one fuse sentinel"* ]]
}

@test "fix without --yes in a non-interactive shell refuses" {
  make_bin "$GBL_BINARY" 48 49 48
  run "$GBL" fix </dev/null
  [ "$status" -ne 0 ]
  [ "$(wire_of "$GBL_BINARY")" = "48 49 48" ]
}

@test "--dry-run changes nothing" {
  make_bin "$GBL_BINARY" 48 49 48
  run "$GBL" --dry-run fix
  [ "$status" -eq 0 ]
  [ "$(wire_of "$GBL_BINARY")" = "48 49 48" ]
  [ ! -e "$HOME/.local/share/grok-bot-backup/grok-bot.0.71.2" ]
}

@test "already-enabled binary without backup: ensure_backup refuses to back up a patched file" {
  make_bin "$GBL_BINARY" 49 49 48
  run "$GBL" --yes restore
  [ "$status" -ne 0 ]
  [[ $output == *"apt reinstall"* ]]
}

@test "agrees with @electron/fuses reader (optional; GBL_TEST_ELECTRON_FUSES=<node_modules dir>)" {
  [ -n "${GBL_TEST_ELECTRON_FUSES:-}" ] || skip "set GBL_TEST_ELECTRON_FUSES to a dir containing node_modules/@electron/fuses"
  make_bin "$GBL_BINARY" 48 49 48 48 144 114 48 49 48
  "$GBL" --yes fix
  ref=$(cd "$GBL_TEST_ELECTRON_FUSES" && NO_COLOR=1 FORCE_COLOR=0 node --input-type=module -e "
    import {getCurrentFuseWire} from '@electron/fuses';
    const c = await getCurrentFuseWire(process.argv[1]);
    const out = []; for (let i = 0; ; i++) { if (c[i] === undefined) break; out.push(c[i]); }
    console.log(out.join(' '));" "$GBL_BINARY")
  [ "$ref" = "$(wire_of "$GBL_BINARY")" ]
  [ "$ref" = "49 49 48 48 144 114 48 49 48" ]
}
