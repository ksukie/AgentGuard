# AgentGuard

> 跨平台 `AGENTS.md` 模板 + Windows 优先的只读诊断工具。

AgentGuard 帮助发现 AI 编码代理环境中的编码、换行、路径与 Codex 连接风险。它不修改系统、代理、Git 或 Codex 配置。

## 功能

| 功能 | 解决的问题 | 平台 | 详细说明 |
| --- | --- | --- | --- |
| 环境与仓库诊断 | PowerShell 编码、Git 行尾、脚本兼容性与仓库规则 | Windows | [查看文档](docs/doctor.md) |
| Codex 连接诊断 | 代理、TUN 路由、进程连接、流重试与 HTTP 回退 | Windows | [查看文档](docs/codex-connectivity.md) |
| AGENTS 规则模板 | 全局与仓库级执行规则 | Windows、macOS、Linux | [查看文档](docs/agents-templates.md) |

## 开始使用

```powershell
pwsh -NoProfile -File .\scripts\doctor.ps1
```

没有 PowerShell 7 时，可将 `pwsh` 换成 Windows PowerShell 的 `powershell`。

## 安全承诺

默认不上传源代码，不读取密钥或 `auth.json`，不修改注册表、系统代理、TUN、路由、Git 或 Codex 配置。

## 许可证

[MIT](LICENSE)
