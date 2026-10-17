# 原理 / How it works

## 问题

官方 Grok Bot Linux 客户端是 Electron 应用。远程执行命令靠包里自带的 `local-exec-daemon/main.cjs`。
[andreanjos/grokbot-headless](https://github.com/andreanjos/grokbot-headless) 用
`ELECTRON_RUN_AS_NODE=1 grok-bot main.cjs` 只启动这个后台，不开窗口、不需要显示服务器。

从 **0.71.2** 起，官方二进制关闭了 Electron 的 `RunAsNode` fuse：`ELECTRON_RUN_AS_NODE` 被忽略，
二进制按 GUI 应用启动，没有显示服务器就崩溃（上游 `check --local` 报缺显示服务器 + 段错误）。
退路要么是 Xvfb，要么是完整客户端（~740 MB）。

## Electron fuse 是什么

Electron 在二进制里留了一段“保险丝”区域（fuse wire），构建时决定某些能力开关：

```text
... "dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX" | 0x01 (wire 版本) | 0x09 (fuse 数量) | '0' '1' '0' '0' '1' '1' '0' '1' '1'
                32 字节 sentinel                                              ^ 第 0 位 = RunAsNode
```

每个 fuse 一个字节：`'0'`=关，`'1'`=开，`'r'`=已移除，`0x90`=继承默认值。
（定义见 `@electron/fuses` 源码 `constants.js` / `config.js`。）

## grokbot-lite 做了什么

1. 用 `grep -obaF` 找到**唯一**的 sentinel（找不到或多于一个都拒绝）。
2. 读出 wire，确认版本为 1、RunAsNode 是 `'0'`（或继承）而不是 `'r'`。
3. 备份原版并校验 sha256。
4. 在用户目录里的副本上把那**一个字节**改成 `'1'`，重新读取并确认其它 fuse 全部不变。
5. `sudo install` 到同目录临时文件 → `sudo mv` 原子替换。
6. 监督进程照旧用 `ELECTRON_RUN_AS_NODE=1` 拉起后台，现在它会以纯 Node 模式运行。

之后：
- `grokbot-lite-doctor.timer` 每 15 分钟以普通用户身份检查一次，fuse 被 `apt upgrade` 重置时记日志并通知。
- 可选 apt 钩子在每次 dpkg 运行后打印提醒。
- `grokbot-lite fix --restart` 一条命令恢复（会先为新版本做新备份）。

## 文件位置

| 路径 | 作用 |
| --- | --- |
| `~/.local/bin/grokbot-lite` | CLI（单文件 bash） |
| `~/.local/share/grok-bot-backup/grok-bot.<版本>` (+`.sha256`) | 原版备份 |
| `~/.config/systemd/user/grokbot-lite-doctor.{service,timer}` | 定时体检 |
| `~/.config/grokbot-lite/config` | 可选，例如 `GBL_NOTIFY_CMD=...` |
| `~/.local/state/grokbot-lite/` | `doctor --notify` 的日志与上次状态 |
| `/etc/apt/apt.conf.d/99grokbot-lite` + `/usr/local/lib/grokbot-lite/` | 可选 apt 钩子（root 拥有） |

**一键安装（服务器模式）额外使用：**

| 路径 | 作用 |
| --- | --- |
| `/usr/local/bin/grokbot-lite` | CLI（root 与服务用户共用） |
| `/etc/grokbot-lite.conf` | `GBL_SERVICE_USER`、`GBL_BACKUP_DIR`（CLI 只解析不执行） |
| `/var/lib/grokbot-lite/backup/` | 原版备份（服务用户可读，便于 doctor 校验） |
| `/home/grokbot/` | 服务用户：监督进程、凭据（0600）、systemd 用户单元 |
| `/opt/node22/` | 仅当系统 Node < 20 时安装（带 `.installed-by-grokbot-lite` 标记） |
| `/usr/share/keyrings/grok-bot.gpg`、`/etc/apt/sources.list.d/grok-bot.sources` | 官方 apt 源（包安装后会自行维护 sources 文件） |
| `/var/log/grokbot-lite-install.log` | 安装日志（0600） |
