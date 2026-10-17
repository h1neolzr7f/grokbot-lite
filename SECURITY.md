# Security policy

- 请通过 GitHub **私密漏洞报告**（Security → Report a vulnerability）提交安全问题，不要开公开 issue。
- Please report vulnerabilities privately via GitHub Security Advisories, not public issues.

提交前请删除：OAuth/刷新令牌、一次性登录链接、`credentials.json`、`machine.json`、守护进程凭据、
Authorization 头、未脱敏日志、邮箱、machineId。

设计说明见 [docs/security.md](docs/security.md)。支持版本：最新的 0.x 版本。
