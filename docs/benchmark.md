# 内存基准 / Memory benchmark

![memory chart](memory.png)

## 实测（measured）

### A. 阿里云轻量应用服务器（2 GiB VPS）

| 项目 | 数值 |
| --- | --- |
| 配置 | 2 vCPU，2 GiB（系统可见 1613 MB）+ 2 GB swap，x86_64，Ubuntu 24.04.2 LTS |
| 安装方式 | 官方 apt 源，`apt-get install --no-install-recommends grok-bot` → 0.71.2，约 350 MB，无额外依赖 |
| 运行方式 | 专用非 root 用户 `grokbot`（无 sudo）+ linger；Node 22（`/opt/node22`）；grokbot-headless 0.2.2 |
| 后台 RSS | **~122 MB**（同日复测 125–130 MB） |
| 监督进程 RSS | **~70 MB**（复测 75 MB） |
| **合计** | **~190 MB** |
| 整机 `free -m` | 安装前已用 **480 MB**；登录运行后已用 **544 MB**，可用 **1068 MB** |

> 为什么整机“已用”只涨了约 64 MB，而两个进程 RSS 加起来约 190 MB？
> RSS 包含与系统共享的页（libc 等），而这台机器有 swap，一部分冷页被换出（复测时 swap 用了约 220 MB，
> 其中也包括其他服务）。“已用”不含缓存与已换出的页。两个数字都是真的，只是口径不同。

### B. 小主机

| 项目 | 数值 |
| --- | --- |
| 配置 | 松下 CF-SV7，8 核，7.6 GB，Ubuntu 24.04.5 LTS，`multi-user.target` |
| 后台 RSS | **~120 MB**（复测 131 MiB） |
| 监督进程 RSS | **~78 MB**（复测 84 MiB） |
| 合计 | **~200 MB** |
| 完整客户端无界面启动 | **~740 MB**（所有 Electron 进程合计，且为未登录状态） |

### 方法

- RSS 来自 `ps -o rss` / `/proc/<pid>/status` 的 `VmRSS`；`grokbot-lite status --json` 中的 `daemon.rssKiB`、`supervisor.rssKiB`。
- 整机数据来自 `free -m` 的 `used` 与 `available`。
- 全部是 **2026-10-18 的单次抽样**，不是长期统计；没有测峰值。

### 局限

- RSS 会重复计算共享页；更精确可以用 `smem -k` 看 PSS。
- 后台执行命令时会派生 shell/子进程，那部分内存取决于你让它做什么，不在上表内。
- 完整客户端（740 MB）只在小主机上测过。

## 不同内存的机器怎么配（**估算 / estimates**，未实测）

| 机器内存 | 系统空闲（服务器版） | grokbot-lite | 留给你的工作负载 | 建议 |
| --- | --- | --- | --- | --- |
| **1 GB** | 150–250 MB | ~200 MB | ~500 MB | 能跑。**必须开 swap**（一键脚本会建议 2 GB）。适合 adb、脚本、轻量服务；不要再跑数据库。完整客户端基本跑不动。 |
| **2 GB**（已实测） | ~480 MB（云厂商镜像常带监控代理等） | ~190 MB | ~1 GB | 舒适。一个小型游戏服务端或 Web 服务 + SQLite 没问题；MongoDB/MySQL 建议限内存。 |
| **4 GB+** | 300–500 MB | ~200 MB | 3 GB+ | 随意：私服 + 数据库 + Docker。 |

经验法则：给 grokbot-lite 预留 **250 MB**（含波动），剩下的才是你的预算。

## 复现

```bash
grokbot-lite status --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["daemon"]["rssKiB"], d["supervisor"]["rssKiB"])'
free -m
python3 scripts/gen-chart.py     # 修改脚本顶部的数字后重新生成 docs/memory.png
```
