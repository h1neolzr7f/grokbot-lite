# 安全设计 / Security design

grokbot-lite 改动的是一个由 root 拥有的官方二进制，并让远端能在你的机器上执行命令。所以安全是设计的一部分，不是附录。

## 1. 原则

| 原则 | 落地方式 |
| --- | --- |
| **默认 `ask`，永不 `always`** | `install` 只会调用 `grok-bot-headless policy ask`；代码里没有任何设置 `always` 的路径（有测试保证）。已有 `always` 时会改回 `ask`。`doctor` 把 `always` 标为警告，`always` + 免密 sudo 标为**失败**。 |
| **先备份再修改** | 修改前把原版复制到 `~/.local/share/grok-bot-backup/grok-bot.<版本>`，校验 sha256 并写 `.sha256` 旁注文件。备份失败就中止。已经被改过的二进制不会被当作“原版”备份。 |
| **只改一个字节** | 只修改 fuse wire 的第 0 个字节（RunAsNode）。修改后重新读取整个 wire，任何其他 fuse 变化都会中止。实机用 `cmp -l` 确认与备份仅差 1 字节。 |
| **不原地写、不半写** | 在用户目录下的副本上打补丁并验证，再以 root `install` 到同目录临时文件，最后 `mv` 原子替换。正在运行的后台继续使用旧 inode，不会出现 ETXTBSY 或损坏的二进制。 |
| **一条命令还原** | `grokbot-lite restore`：校验备份 sha256 后原子替换回去；版本不匹配时拒绝（建议 `sudo apt reinstall grok-bot`），除非 `--force`。`uninstall` 默认也会还原。 |
| **最小 root** | 只有三处需要 sudo：替换二进制（`install` + `mv`）、`loginctl enable-linger`、可选的 apt 钩子。每次都先打印要执行的命令，交互确认（或 `--yes`）。 |
| **不联网、不跑 npx** | CLI 自己解析 fuse wire（纯 bash + `grep`/`dd`/`od`），不下载任何东西。尤其不会以 root 运行 `npx @electron/fuses`。 |
| **不碰凭据** | `doctor` 只检查凭据文件**是否存在**，从不读取内容（测试中把它设成 000 权限验证）。 |

## 1.5 服务器（VPS）上的额外设计

| 设计 | 说明 |
| --- | --- |
| **专用非 root 用户** | 一键脚本创建 `grokbot`：不在 sudo 组、密码锁定（只能 root `runuser` 进入）。即使你误批准了一条坏命令，影响也限于这个用户的家目录。 |
| **不开放入站端口** | 后台只主动连出到 Grok Bot 服务；在实测 VPS 上 `ss -lntup` 看不到它的 TCP 监听。不需要在安全组/防火墙放行任何端口。 |
| **不碰现有安全设施** | 不修改 ufw/iptables、安全组、fail2ban、SSH 配置。 |
| **不擅自重启服务** | apt 运行时设 `NEEDRESTART_MODE=l`（只列出），避免 needrestart 自动重启 docker 等。 |
| **Node 不污染系统** | 新 Node 装在 `/opt/node22`，sha256 校验，系统自带的旧 Node 原样保留；卸载时可选删除。 |
| **登录链接** | 只在你的终端里显示（含二维码），日志里会记录监督进程输出——日志文件 `/var/log/grokbot-lite-install.log` 只有 root 可读，链接一次性且约 24 分钟过期。 |
| **登录错账号** | `--switch-account`：先 `logout`（停止服务并删除本机凭据），再生成新链接。 |

## 2. 关于 `npx @electron/fuses write`

我们查阅并实测了 `@electron/fuses` 2.1.3 的源码：命令行 `write` 会把二进制里**所有** fuse 重新写一遍，
把 `Inherited` 和 `Removed` 状态都改成 `Disabled`。对官方 0.71.2 二进制（9 个 fuse 全是明确的开/关）来说，
`write --app <path> RunAsNode=on` 实际只改了 1 个字节——这在阿里云 VPS 上已验证；但对含 `Inherited`/`Removed`
的二进制，它会改动其他开关，违背“只改一个开关”。它的 JS API
`flipFuses(path, {version: '1', [FuseV1Options.RunAsNode]: true})` 则只会写 RunAsNode。
grokbot-lite 的原生实现与 JS API 行为一致，CI 中用 `getCurrentFuseWire` 交叉验证。

## 3. 为什么 apt 钩子只提醒、不自动修复

自动修复意味着每次 `apt` 运行时，以 root 身份改写厂商二进制，甚至以 root 拉取网络上的 npm 包。
这把一次性、可审计的操作变成了长期驻留的 root 自动化，风险远大于“升级后手动跑一次 `grokbot-lite fix`”。
所以：apt 钩子（`DPkg::Post-Invoke`）只读 fuse 并打印警告，总是 `exit 0`；systemd 定时器以普通用户身份运行
`doctor --notify`，只在状态变化时通知一次。

## 4. RunAsNode fuse 的威胁模型

**打开它意味着什么**：任何能执行 `/opt/Grok Bot/grok-bot` 的本地用户，都可以
`ELECTRON_RUN_AS_NODE=1 "/opt/Grok Bot/grok-bot" script.js`，把它当作一个通用 Node.js 解释器使用。

| 场景 | 风险 | 在 Linux 上的评估 |
| --- | --- | --- |
| 继承应用权限（macOS TCC、Windows 信任签名） | 攻击者借用“受信任应用”的身份 | **基本不适用**。Linux 没有按应用授予的权限；二进制不是 setuid（`chrome-sandbox` 才可能是）。 |
| 本地代码执行 | 获得一个 Node 运行时 | **增量很小**。能执行它的人本来就能跑 bash/python。 |
| 应用白名单环境（AppArmor/fapolicyd 只放行特定程序） | 用受信任二进制绕过白名单 | **适用**。如果你依赖这类白名单，请为 grok-bot 单独写规则，或不要使用本方案。 |
| 环境变量注入 | 篡改用户进程环境，把客户端变成 Node | 需要先能控制你的会话环境，已经等同于代码执行。`NODE_OPTIONS` 与 `--inspect` 两个 fuse 保持关闭不变。 |
| 访问客户端数据 | 读 cookie/会话 | 不因 fuse 改变：文件权限仍是唯一屏障。Cookie 加密 fuse 保持开启。 |

**真正的大风险不是这个 fuse，而是“远端可以在这台机器上执行命令”本身**：

- `always` + 免密 sudo = 远端无人值守 root。`doctor` 判定为失败。
- 建议：专用 Linux 用户（不在 sudo 组）、保持 `ask`、只在需要时开机、定期看 `journalctl --user -u grok-bot-headless`。
- 一次性登录链接、`credentials.json`、`machine.json`、守护进程凭据都**不要**分享或提交到 issue。

## 5. 残余风险

- 依赖官方内部启动方式：未来版本可能把 RunAsNode 编译为 `removed`，或修改后台入口，本方法随之失效（`doctor` 会报告）。
- 依赖第三方监督进程（andreanjos/grokbot-headless）。安装前请自行审阅其源码；它把 OAuth 凭据以明文 JSON（0600）保存。
- 改动官方二进制可能不符合某些使用条款，请自行判断。

## 6. 报告漏洞

请用 GitHub 私密漏洞报告（Security → Report a vulnerability），不要公开提 issue。见 [SECURITY.md](../SECURITY.md)。
