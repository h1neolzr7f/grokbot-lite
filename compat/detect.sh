#!/bin/sh
# compat/detect.sh - report grok-bot package version, Electron version and fuse
# wire state for the compatibility matrix.  Read-only; POSIX sh; no root needed.
#
#   sh compat/detect.sh [--json|--yaml] [BINARY]
#
# SPDX-License-Identifier: MIT
set -eu

SENTINEL=dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX
FORMAT=text
BIN=""
for a in "$@"; do
  case $a in
    --json) FORMAT=json ;;
    --yaml) FORMAT=yaml ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) BIN=$a ;;
  esac
done
[ -n "$BIN" ] || BIN=${GBL_BINARY:-${GROK_BOT_BINARY:-"/opt/Grok Bot/grok-bot"}}
PKG=${GBL_PACKAGE:-grok-bot}

version=${GBL_PACKAGE_VERSION:-}
if [ -z "$version" ] && command -v dpkg-query >/dev/null 2>&1; then
  version=$(dpkg-query -W -f='${Version}' "$PKG" 2>/dev/null || true)
fi
if [ -z "$version" ] && command -v rpm >/dev/null 2>&1; then
  version=$(rpm -q --qf '%{VERSION}' "$PKG" 2>/dev/null || true)
fi
[ -n "$version" ] || version=unknown

if command -v dpkg >/dev/null 2>&1; then arch=$(dpkg --print-architecture 2>/dev/null || uname -m); else arch=$(uname -m); fi
os=unknown
# shellcheck disable=SC1091
[ -r /etc/os-release ] && os=$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-$ID}")

bytes() { dd if="$BIN" bs=1 skip="$1" count="$2" 2>/dev/null | od -An -v -tu1 | tr -s ' \n' '  ' | sed 's/^ //; s/ $//'; }
state() { case $1 in 48) echo disabled;; 49) echo enabled;; 114) echo removed;; 144) echo inherit;; *) echo "unknown($1)";; esac; }

electron=unknown wire_version="" wire_length="" wire="" run_as_node=error error=""
if [ ! -r "$BIN" ]; then
  error="binary not readable: $BIN"
else
  electron=$(LC_ALL=C grep -aom1 'Electron/[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' "$BIN" 2>/dev/null | head -n1 | cut -d/ -f2 || true)
  [ -n "$electron" ] || electron=unknown
  offs=$(LC_ALL=C grep -obaF "$SENTINEL" "$BIN" | cut -d: -f1 || true)
  n=$(printf '%s\n' "$offs" | grep -c '[0-9]' || true)
  if [ "$n" -ne 1 ]; then
    error="expected 1 fuse sentinel, found $n"
  else
    # word splitting is intended: "1 9" -> $1 $2
    # shellcheck disable=SC2046
    set -- $(bytes $((offs + 32)) 2)
    wire_version=$1 wire_length=$2
    wire=$(bytes $((offs + 34)) "$wire_length")
    # shellcheck disable=SC2086
    set -- $wire
    run_as_node=$(state "$1")
  fi
fi

case $FORMAT in
  text)
    printf 'package=%s\nversion=%s\narch=%s\nos=%s\nelectron=%s\nbinary=%s\n' "$PKG" "$version" "$arch" "$os" "$electron" "$BIN"
    printf 'fuse_wire_version=%s\nfuse_wire_length=%s\nfuse_wire=%s\nRunAsNode=%s\n' "$wire_version" "$wire_length" "$wire" "$run_as_node"
    [ -z "$error" ] || printf 'error=%s\n' "$error" ;;
  json)
    printf '{"package":"%s","version":"%s","arch":"%s","os":"%s","electron":"%s","fuseWireVersion":%s,"fuseWireLength":%s,"fuseWire":[%s],"runAsNode":"%s","error":"%s"}\n' \
      "$PKG" "$version" "$arch" "$os" "$electron" "${wire_version:-null}" "${wire_length:-null}" \
      "$(printf '%s' "$wire" | tr ' ' ',')" "$run_as_node" "$error" ;;
  yaml)
    cat <<Y
  - version: "$version"
    arch: [$arch]
    electron: "$electron"
    fuse_wire: {version: ${wire_version:-null}, length: ${wire_length:-null}}
    run_as_node_default: $run_as_node   # state BEFORE grokbot-lite fix (run on a fresh install)
    status: unknown                     # works-stock | works-with-fix | broken
    verified_by: "<your GitHub handle>, $os, $(date +%Y-%m-%d)"
Y
    ;;
esac
[ -z "$error" ]
