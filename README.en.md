# grokbot-lite

**Turn a cheap 1–2 GB cloud VPS into a 24/7 remote dev box that Grok Bot can operate — in ~190 MB of RAM.**
No desktop, no Xvfb, not running as root.

[中文](README.md) · [Benchmark](docs/benchmark.md) · [Security](docs/security.md) · [Use cases](docs/use-cases.md) · [How it works](docs/how-it-works.md) · [Compatibility](compat/README.md)

## One-click VPS install

On a fresh Ubuntu 24.04/22.04 or Debian 12 KVM server:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR-GITHUB/grokbot-lite/main/install.sh | sudo bash
```

(`YOUR-GITHUB` is a placeholder.) The installer (Chinese prompts, safe defaults) checks OS/arch/RAM/disk/systemd,
offers swap, adds the official apt repo and installs `grok-bot` with `--no-install-recommends`, installs Node 22 to
`/opt/node22` if the system Node is older than 20 (sha256-verified, system Node untouched), creates a dedicated
non-root user `grokbot` without sudo, enables linger, backs up the official binary and flips **only** the RunAsNode
fuse (1 byte), installs a pinned [grokbot-headless](https://github.com/andreanjos/grokbot-headless) supervisor, shows
the one-time login link in a highlighted box with a terminal QR code and countdown, then sets policy `ask`, starts
the service and runs `doctor`.

Flags: `--yes` (non-interactive, safe defaults), `--switch-account` (wrong account → logout + new link),
`--uninstall`, `--no-login`, `--dry-run`, `--log FILE` (default `/var/log/grokbot-lite-install.log`). Re-runnable.

## Why

The full Electron client started headless needs ~740 MB plus Xvfb. grokbot-headless avoids that, but official
0.71.2 disabled Electron's RunAsNode fuse, so it crashes. grokbot-lite flips that single byte (backup first,
one-command restore, upgrade detection) and packages the whole server setup. We know of no other ready-made way to
run Grok Bot remote execution on a 1–2 GB headless VPS.

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

## Legal

Independent, unofficial project; not affiliated with xAI or the Grok Bot team. No proprietary code or binaries.
Modifying the official binary may conflict with some terms of use. MIT licensed.
