# 兼容性矩阵 / Compatibility matrix

数据源：[`versions.yaml`](versions.yaml)。检测脚本：[`detect.sh`](detect.sh)（只读、POSIX sh、无需 root）。

| grok-bot | 架构 | Electron | RunAsNode 出厂状态 | 结论 | 验证者 |
| --- | --- | --- | --- | --- | --- |
| 0.30.0 | amd64 | ? | 开（推断） | 原版即可用 | 上游 grokbot-headless 声明，本项目未复测 |
| 0.71.2 | amd64 | 42.1.0 | **关** | `grokbot-lite fix` 后可用 | 本项目：小主机 Ubuntu 24.04.5；阿里云轻量 2 GiB Ubuntu 24.04.2（2026-10-18） |
| 0.71.2 | arm64 | — | — | 未测试 | 欢迎提交 |

## 如何贡献一条记录 / How to add an entry

在**刚装好、还没运行 `grokbot-lite fix`** 的机器上：

```bash
sh compat/detect.sh            # 人类可读
sh compat/detect.sh --yaml     # 直接粘进 versions.yaml 的片段
```

已经 fix 过？对备份跑：`sh compat/detect.sh --yaml ~/.local/share/grok-bot-backup/grok-bot.<版本>`。

然后实际跑一次 `grokbot-lite doctor`，把 `status` 改成 `works-stock` / `works-with-fix` / `broken`，用
"Compatibility report" issue 模板或 PR 提交。**不要**附上二进制文件、凭据、登录链接或 machineId。

## 字段含义

- `fuse_wire.version/length`：Electron fuse wire 头部（sentinel 后两个字节）。
- `run_as_node_default`：未修改的官方二进制中 RunAsNode 的状态（`enabled`/`disabled`/`removed`）。
  `removed` 表示该 Electron 构建把这个开关编译掉了，本方法将无法工作。
- 0.71.2 起官方关闭了 RunAsNode。新版本若改成 `removed` 或换用别的启动方式，需要新的方案。
