# Changelog

格式参考 [Keep a Changelog](https://keepachangelog.com/)，版本号遵循 [SemVer](https://semver.org/)。

## [0.2.0] - 2026-10-18

### Added
- **一键安装器 `install.sh`**（`curl … | sudo bash`）：面向 1–2 GB 无桌面云服务器。环境检测（系统/架构/内存/磁盘/systemd/root）、
  可选 swap、官方 apt 源 + `--no-install-recommends`、Node 22 到 `/opt/node22`（sha256 校验、镜像回退）、专用非 root 用户 + linger、
  备份 + 只翻转 RunAsNode、固定版本的 grokbot-headless、醒目登录框 + 终端二维码 + 倒计时、`policy ask`、体检与成功总结。
  支持 `--yes`、`--switch-account`、`--uninstall`、`--no-login`、`--dry-run`、`--log`；可重复运行；中文错误提示附修复方法。
- CLI：`switch-account`；root 下 `doctor`/`status`/`switch-account` 自动以服务用户执行；`/etc/grokbot-lite.conf`；
  `fix`/`restore` 可在 root 下运行；备份与线上二进制的“只差 RunAsNode 一个字节”校验；非 sudo 组用户跳过 sudo 探测。
- 文档：新手教程（从买服务器到连上）、新手 FAQ、VPS 实测基准与新图表、VPS 安全设计、VPS 场景。
- 16 个安装器 bats 测试。

### Verified
- 阿里云轻量 2 GiB（Ubuntu 24.04.2）与小主机（Ubuntu 24.04.5）上只读运行 `doctor`、`status --json`、`read-fuse`、`detect.sh`。
  注意：`install.sh` 本身尚未在全新机器上端到端运行过（VPS 是按同样流程手工搭建的）。

## [0.1.0] - 2026-10-18

### Added
- `grokbot-lite` 单文件 CLI：`install`、`doctor`、`status --json`、`fix`、`restore`、`uninstall`、
  `read-fuse`、`install-timer`、`install-apt-hook`、`apt-check`。
- 原生 fuse wire 读写（纯 bash），只修改 RunAsNode 一个字节；备份 + sha256 校验；原子替换。
- systemd 用户定时器 `grokbot-lite-doctor.timer`（状态变化时通过 journal / `logger` / `notify-send` /
  `GBL_NOTIFY_CMD` 通知）。
- 只提醒的 apt `DPkg::Post-Invoke` 钩子。
- `compat/versions.yaml` + `compat/detect.sh`；0.30.0（上游）与 0.71.2（本项目实测）。
- 内存基准文档与图表、安全设计、适用场景文档。
- bats 测试（全部使用 mock，不需要真实二进制）与 GitHub Actions CI（shellcheck + bats + @electron/fuses 交叉验证）。

### Verified
- Ubuntu 24.04.5 amd64、grok-bot 0.71.2（Electron 42.1.0）：只读运行 `doctor` / `status --json` /
  `read-fuse` / `detect.sh`，确认线上二进制与备份仅差 RunAsNode 一个字节。
