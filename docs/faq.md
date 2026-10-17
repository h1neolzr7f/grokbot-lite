# 新手 FAQ

### Grok Bot 里看不到我的服务器
九成是**登录错了账号**（浏览器里登录的不是你平时用的那个）。运行：
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR-GITHUB/grokbot-lite/main/install.sh | sudo bash -s -- --switch-account
```
它会退出当前账号、生成新链接。打开前先确认浏览器里是对的账号。其余情况运行 `sudo grokbot-lite doctor` 看哪一项是 `[FAIL]`。

### 提示「Node 太旧」/ 系统 Node 是 v18
Ubuntu 24.04 自带 Node 18，监督进程需要 20 以上。**不用管**：脚本会把 Node 22 装到 `/opt/node22`，不影响系统自带的 Node。
如果下载 Node 失败（国内网络），脚本会自动换 npmmirror 镜像；还不行可以：
```bash
curl -fsSL …/install.sh | sudo GBL_NODE_MIRRORS=https://npmmirror.com/mirrors/node bash
```

### 提示「磁盘空间不足」
需要约 1.2 GB。清理：`sudo apt-get clean && sudo journalctl --vacuum-size=100M`，或在控制台扩容系统盘。

### 提示「systemd 没有在运行」
你的机器是 OpenVZ/LXC 容器或 WSL1，不支持。换成 KVM 虚拟机（阿里云/腾讯云轻量、大多数 VPS 都是 KVM）。WSL2 需要在 `/etc/wsl.conf` 里加 `[boot]` `systemd=true` 后重启。

### 提示「不支持 32 位 ARM」
官方只提供 x86_64 和 arm64。树莓派请重装 **64 位**系统。

### 提示「没有 apt」
你装的是 CentOS / Alibaba Cloud Linux / Rocky 等。在控制台把系统重装成 **Ubuntu 24.04**。

### 登录链接超时 / 我关掉了终端
直接重新运行一键命令，已完成的步骤会跳过，只会重新生成登录链接。

### 安装时问我是否重启服务（紫色/蓝色对话框）
脚本已经让 needrestart 只列出、不重启。如果你手动 `apt upgrade` 时弹出，**不要勾选 docker** 等正在用的服务，选“取消/不重启”即可。

### `apt upgrade` 之后 Grok Bot 连不上了
官方升级会把开关恢复成关闭。运行 `sudo grokbot-lite fix --restart`。每 15 分钟的体检定时器也会在日志里提醒你（`journalctl --user` 需在 grokbot 用户下看，或直接 `sudo grokbot-lite doctor`）。

### 这安全吗？Grok Bot 能随便操作我的服务器吗？
- 它运行在一个**没有 sudo 的专用用户**下，碰不到系统文件；
- 策略是 `ask`：**每条命令**都要你在 Grok Bot 里点批准；
- 不开放任何端口，不改防火墙/fail2ban/SSH。
详见 [安全设计](security.md)。千万别把策略改成 `always`，更别给 grokbot 用户加 sudo。

### 会占多少内存？1 GB 的机器行不行？
实测 2 GB 机器上约 190 MB。1 GB 能跑，但一定要开 swap（脚本会提示），见 [benchmark.md](benchmark.md)。

### 我能用同一个脚本装到家里的小主机/旧电脑上吗？
可以，只要是 Ubuntu/Debian + systemd。也可以不建专用用户、用自己的账号跑：见 [适用场景](use-cases.md)。

### 怎么完全卸载？
```bash
curl -fsSL …/install.sh | sudo bash -s -- --uninstall
```
它会停止服务、恢复官方原版二进制，并逐项询问是否删除用户、卸载 grok-bot、删除 Node（默认都是“不删”）。

### 出错了怎么求助？
运行 `sudo grokbot-lite doctor`，并附上 `sudo tail -n 50 /var/log/grokbot-lite-install.log`，**先删掉其中的链接、邮箱、令牌**再发 issue。
