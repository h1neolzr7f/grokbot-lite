# 参与贡献 / Contributing

谢谢！最有价值的贡献是**兼容性报告**：新版本 grok-bot 出来后，告诉大家还能不能用。

## 开发环境

```bash
sudo apt install shellcheck bats python3-matplotlib
make lint test            # shellcheck + bats（全部使用 mock，不需要真实 grok-bot）
make crosscheck           # 可选：用 @electron/fuses 交叉验证 fuse 解析（需要 node + npm）
make chart                # 重新生成 docs/memory.png
```

## 规则

1. **不要提交任何专有内容**：官方二进制、解包出来的 app.asar 内容、截图里的令牌、登录链接、凭据。
2. CLI 保持单文件 bash、`shellcheck` 零告警、不引入运行时依赖（不需要 node/python/jq）。
3. 任何会修改系统的路径都必须：支持 `--dry-run`、需要确认或 `--yes`、先备份、有测试。
4. 不接受自动设置 `policy always` 或以 root 自动修复的改动（理由见 [docs/security.md](docs/security.md)）。
5. 修改 `systemd/` 下的单元文件时同步修改 CLI 里的内嵌副本（测试会比对）。
6. PR 描述里写明你实测的 grok-bot 版本、架构和发行版。

## 兼容性报告

```bash
sh compat/detect.sh --yaml        # 在未 fix 的新装机器上运行，或对备份文件运行
grokbot-lite doctor               # fix 后
```

把输出贴进 “Compatibility report” issue 模板，或直接 PR 修改 `compat/versions.yaml` 与 `compat/README.md`。

## 提交信息

推荐 [Conventional Commits](https://www.conventionalcommits.org/)：`feat:`、`fix:`、`docs:`、`test:`、`compat:`。
