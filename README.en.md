# grokbot-lite

[![CI](https://img.shields.io/badge/CI-shellcheck%20%2B%20bats-blue)](docs/ci.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Linux%20x86__64%20%7C%20systemd-blue)
![RAM](https://img.shields.io/badge/RAM-~190%20MB%20on%20a%202%20GiB%20VPS-brightgreen)

**Make Grok Bot run on Linux servers that have no graphical desktop — and keep it lightweight.**

The official client is a desktop app. On a headless cloud VPS it either will not start, or a forced headless Electron session needs Xvfb and ~740 MB of RAM.
**grokbot-lite** is a working no-GUI setup (dedicated user + systemd + a 1-byte RunAsNode fuse flip) so the remote-exec daemon runs in about **190 MB** total — no desktop, no Xvfb, not as root. A cheap 1–2 GB VPS becomes a 24/7 remote dev box.

> ⚠️ **Unofficial.** Not affiliated with xAI or the Grok Bot team. It modifies one Electron fuse (RunAsNode) in the
> official binary **at your own risk**; a backup is made first and `grokbot-lite restore` undoes it.

[中文](README.md) · [Benchmark](docs/benchmark.md) · [Security](docs/security.md) · [Use cases](docs/use-cases.md) · [How it works](docs/how-it-works.md) · [Compatibility](compat/README.md)

## One-click VPS install

On a fresh Ubuntu 24.04/22.04 or Debian 12 KVM server:

```bash
curl -fsSL https://raw.githubusercontent.com/h1neolzr7f/grokbot-lite/main/install.sh | sudo bash
```

The installer (Chinese prompts, safe defaults) checks OS/arch/RAM/disk/systemd,
offers swap, adds the official apt repo and installs `grok-bot` with `--no-install-recommends`, installs Node 22 to
`/opt/node22` if the system Node is older than 20 (sha256-verified, system Node untouched), creates a dedicated
non-root user `grokbot` without sudo, enables linger, backs up the official binary and flips **only** the RunAsNode
fuse (1 byte), installs a pinned [grokbot-headless](https://github.com/andreanjos/grokbot-headless) supervisor, shows
the one-time login link in a highlighted box with a terminal QR code and countdown, then sets policy `ask`, starts
the service and runs `doctor`.

Flags: `--yes` (non-interactive, safe defaults), `--switch-account` (wrong account → logout + new link),
`--uninstall`, `--no-login`, `--dry-run`, `--log FILE` (default `/var/log/grokbot-lite-install.log`). Re-runnable.

## Tested on / Not yet tested

| ✅ Tested | ⚠️ Not yet tested |
| --- | --- |
| Ubuntu 24.04 x86_64, 2 GiB cloud VPS (Aliyun lightweight) | A full end-to-end run of `install.sh` on a fresh machine |
| Ubuntu 24.04 x86_64, 8 GB mini PC | arm64 |
| grok-bot 0.71.2 (Electron 42.1.0) | Debian 12, Ubuntu 22.04 |
| `doctor` / `status --json` / `read-fuse` / 1-byte fuse patch | 1 GB RAM hosts (1 GB numbers in the docs are estimates) |

The VPS was set up manually following the same steps; every installer step is covered by mocked bats tests, but the
one-click script has not yet run end-to-end on real hardware. **Compatibility reports are very welcome** — run
`sh compat/detect.sh --yaml` and open a [Compatibility report](https://github.com/h1neolzr7f/grokbot-lite/issues/new?template=compat_report.yml)
(successes and failures both help).

## Why

**The core problem: the official Grok Bot client needs a graphical desktop**, so it cannot run on a normal headless
Linux server. Starting the full Electron client "headless" still needs Xvfb and ~740 MB. Community grokbot-headless
avoids the window, but official 0.71.2 disabled Electron's RunAsNode fuse, so it crashes. grokbot-lite restores a
working no-GUI path (flip that one byte, backup first, one-command restore, upgrade detection) and packages the
whole server setup — with memory down to ~190 MB as a bonus. We know of no other ready-made way to run Grok Bot
remote execution on a headless Linux cloud VPS (especially 1–2 GB).

## Measured

| Host | Daemon | Supervisor | Total | Machine |
| --- | --- | --- | --- | --- |
| Aliyun lightweight, 2 vCPU / 2 GiB (1613 MB visible) + 2 GB swap, Ubuntu 24.04.2 | 122 MB | 70 MB | **~190 MB** | used 480 → 544 MB, 1068 MB available |
| Mini PC, 8 cores / 7.6 GB, Ubuntu 24.04.5 | 120 MB | 78 MB | **~200 MB** | — |
| Full client started headless (mini PC) | — | — | ~740 MB | — |

![memory chart](docs/memory.png)

## Day-to-day (as root)

`grokbot-lite doctor` · `grokbot-lite status --json` · `grokbot-lite fix --restart` (after `apt upgrade`) ·
`grokbot-lite switch-account` · `grokbot-lite restore` · `grokbot-lite read-fuse`. As root, per-user commands are
re-executed as the service user from `/etc/grokbot-lite.conf`. On a desktop/mini PC under your own account use
`./bin/grokbot-lite install --supervisor-src <dir>`.

## Security highlights

- Dedicated non-root service user without sudo; policy `ask`; grokbot-lite never sets `always`.
- No inbound port is opened; firewall, fail2ban and SSH config are untouched. apt runs with `NEEDRESTART_MODE=l`
  so services like docker are never restarted behind your back.
- Backup + sha256 before modifying; patch a copy, verify all other fuses are unchanged, atomic rename; one-command restore.
- `npx @electron/fuses write` re-serialises **every** fuse (Inherited/Removed become Disabled). On the official
  0.71.2 binary (all fuses plainly on/off) it changes exactly one byte, as verified; grokbot-lite's native patcher
  guarantees that for any wire and is cross-checked against the library in CI.

See also [docs/ci.md](docs/ci.md) (Actions workflow currently ships as an example).

## Legal

Independent, unofficial project; not affiliated with xAI or the Grok Bot team. No proprietary code or binaries.
It modifies an Electron fuse in the official binary; this may conflict with some terms of use — **use at your own
risk**. MIT licensed, provided "as is" without warranty.
