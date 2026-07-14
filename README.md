# AgentGuard

> 跨平台 `AGENTS.md` 模板 + Windows 优先的只读诊断工具。

AgentGuard 用来发现 AI 编码代理环境中的编码、换行、路径和 Codex 连接风险；它不修改系统、代理、Git 或 Codex 配置。

## 快速开始

在仓库根目录运行：

```powershell
# 基础环境与仓库检查
pwsh -NoProfile -File .\scripts\doctor.ps1

# Codex 发生重连时：额外检查本机代理、路由、进程连接和本地日志
pwsh -NoProfile -File .\scripts\doctor.ps1 -CodexConnectivity -SinceHours 24

# 开发者自检：不读取仓库、系统设置或 Codex 日志
pwsh -NoProfile -File .\scripts\doctor.ps1 -SelfTest
```

没有 PowerShell 7 时，可把 `pwsh` 换成 Windows PowerShell 的 `powershell`。更多参数见：

```powershell
Get-Help .\scripts\doctor.ps1 -Full
```

## 如何看结果

| 级别 | 含义 |
| --- | --- |
| `PASS` | 未发现已知风险，或当前状态符合预期。 |
| `INFO` | 环境信息或无法确认的可选状态。 |
| `WARN` | 需要复核的兼容性、代理或路由风险。 |
| `ACTION` | 已发现较强的失败信号，例如 Codex 的 HTTP 回退记录。 |

`ACTION` 是本机观察到的证据，不会自动归因到某个节点、Codex 版本或服务端。

## Codex 连接检查

`-CodexConnectivity` 默认关闭，目前仅支持 Windows。启用后只做本机只读观察：

- Windows 系统代理与标准代理环境变量；
- 回环代理端口是否监听；
- TUN、TAP、VPN、Clash 等虚拟适配器是否承载默认路由；
- 正在运行的 Codex 或 ChatGPT Desktop 是否连向声明的本地代理；
- `CODEX_HOME`（默认 `~/.codex`）中 `logs*.sqlite` 的流重试与 HTTP 回退聚合。

刚发生重连时，可用 `-SinceHours 1` 缩小日志窗口。检查不会发起外部网络请求、切换节点、启用 TUN，或写入 Codex provider 配置。

## 使用规则模板

| 模板 | 用途 |
| --- | --- |
| [global-AGENTS.md](templates/global-AGENTS.md) | 通用的全局 Codex 规则。 |
| [global-AGENTS.windows.md](templates/windows/global-AGENTS.windows.md) | Windows、PowerShell、UTF-8 和路径处理补充规则。 |
| [repo-AGENTS.md](templates/repo-AGENTS.md) | 单个项目的基础规则。 |

推荐做法：将模板内容**手动合并**到已有规则，不要覆盖个人或项目规则。

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
notepad.exe (Join-Path $codexHome 'AGENTS.md')
```

全局规则保持通用；项目的构建、测试、部署命令应放在仓库 `AGENTS.md`。不要复制整个 `.codex` 目录，也不要覆盖 `config.toml`。有关规则优先级和发现方式，请参阅 [Codex 官方 AGENTS.md 文档](https://learn.chatgpt.com/docs/agent-configuration/agents-md)。

## 安全边界

- 不上传源代码，不读取密钥、Token、Git 凭据或 `auth.json`；
- 不显示提示词、日志正文、工作目录、代理凭据或远程代理主机；
- 不修改注册表、系统代理、TUN、路由、节点、PowerShell Profile 或 Git 配置；
- 不自动转换仓库文件，也不扫描 `node_modules`、`vendor` 或构建产物；
- 公开模板中不要写入公司路径、内网地址、Token 或个人偏好。

## 平台说明

规则模板可用于 Windows、macOS 和 Linux。`doctor.ps1` 是 Windows 优先的诊断入口，兼容 PowerShell 7 和 Windows PowerShell 5.1；包含中文的兼容性脚本建议使用 UTF-8 with BOM。

## 许可证

[MIT](LICENSE)
