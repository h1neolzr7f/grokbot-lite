# 适用场景 / Use cases

grokbot-lite 的目标：把一台**低内存、无显示器**的 Linux 机器变成 Grok Bot 可以远程操作的开发机，
而 Grok Bot 本身只占约 200 MB。

> 官方 Linux `.deb` 提供 x64（amd64）和 arm64 两种架构（以官方下载页为准）。本项目只在 **amd64** 上实测过；
> arm64 的 fuse 布局相同（Electron 通用机制），理论上可用，但**未验证**——欢迎用 `compat/detect.sh` 提交结果。

## 0. 1–2 GB 云服务器：7×24 远程开发机（已验证，主打场景）

阿里云/腾讯云轻量应用服务器这类几十元一年起（以厂商活动价为准）的 KVM VPS，用一键脚本安装：

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR-GITHUB/grokbot-lite/main/install.sh | sudo bash
```

实测 2 GiB 机器上 Grok Bot 只占约 190 MB，剩下 1 GB 左右可用。典型用法：

- **随时在线的开发机**：手机上让 Grok Bot 去服务器上 `git pull`、跑测试、看日志，电脑不用开。
- **游戏私服开发托管**：例如 .NET 写的单机/私服服务端 + SQLite/MongoDB，自带公网 IP，测试机可以直接连。
  2 GB 机器上数据库请限制内存（MongoDB `--wiredTigerCacheSizeGB 0.25`）。
- **AI 辅助运维，逐条批准**：让 Grok Bot 查 `journalctl`、看磁盘、改 nginx 配置；`ask` 策略下每条命令都要你点批准，
  服务用户没有 sudo，需要 root 的操作它会告诉你命令、由你自己执行。
- 坏了就重装系统、重跑脚本，几分钟恢复。

注意：云厂商镜像自带的监控代理、docker 等会占几百 MB（实测装前已用 480 MB）；一键脚本不会动它们。

## 1. 小主机 / 旧笔记本（已验证）

典型配置：4–8 GB 内存的 x86 小主机，Ubuntu Server 或桌面版切到 `multi-user.target`。

```bash
sudo systemctl set-default multi-user.target    # 不再启动桌面（可随时改回 graphical.target）
grokbot-lite install --supervisor-src ~/src/grokbot-headless
grok-bot-headless login                          # 自己打开链接，不要转发
grok-bot-headless policy ask
systemctl --user restart grok-bot-headless
grokbot-lite doctor
```

## 2. NAS

- 基于 Debian 的 NAS 系统（OpenMediaVault、TrueNAS SCALE 的普通用户环境需谨慎）可以直接装 `.deb`。
- 群晖 DSM / 威联通 QTS 不是 Debian，没有 systemd --user：建议放进一个 Debian/Ubuntu **虚拟机**，
  而不是 Docker（容器里通常没有 systemd 用户实例和 linger）。
- NAS 往往是全家的数据中心：务必用**专用用户**、`ask` 策略，不要给这个用户访问共享盘的写权限。

## 3. 树莓派级 ARM 板（arm64，未验证）

- 需要 64 位系统（Raspberry Pi OS 64-bit / Ubuntu Server arm64）和官方 arm64 `.deb`。
- 1 GB 板子：开 zram（`sudo apt install zram-tools`），见 [benchmark.md](benchmark.md) 的估算表。
- SD 卡寿命：`doctor --notify` 每 15 分钟只写一行日志（上限 500 行），影响可以忽略。

## 4. 远程开发机 + 手机调试（adb）

这是本项目诞生的场景：小主机通过 USB 接一台安卓手机，Grok Bot 远程在小主机上跑 adb 命令。

```text
你（任何地方） ── Grok Bot ──▶ 小主机（grokbot-lite，~200 MB）
                                   │ USB / 局域网 adb
                                   ▼
                               安卓测试机
```

```bash
sudo apt install adb                 # 一次性
adb devices                          # 手机上确认 USB 调试授权
adb install app.apk
adb logcat -v time | grep -i unity   # 让 Grok Bot 帮你看日志
```

- 想看手机画面：在**你自己的电脑**上用 `scrcpy` 连接（`adb tcpip 5555` 后经局域网或 Tailscale），
  小主机仍然不需要图形界面。
- **不要**把 adb 的 5555 端口暴露到公网。用 Tailscale/WireGuard 之类的私有网络。
- 所有 adb 命令在 `ask` 策略下都需要你逐条批准。

## 5. 不适合的场景

- 需要 Grok Bot 操作**图形界面**（点浏览器、看屏幕）的任务：本方案没有显示器。
- 依赖应用白名单（AppArmor/fapolicyd）做安全边界的机器：见 [security.md](security.md#4-runasnode-fuse-的威胁模型)。
- 多人共用、且有人不可信的机器：RunAsNode 打开后任何本地用户都能把 grok-bot 当 Node 用。
