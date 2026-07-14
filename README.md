# AgentGuard

让 AI 编码代理在 Windows、macOS 和 Linux 上更稳定地执行任务。

AgentGuard v0.2.0 是一套可复制的跨平台协作基线：

- `AGENTS.md` 模板：告诉 Codex 如何避免编码、换行和 shell 兼容性问题；
- `doctor.ps1`：只读检查当前 Windows、PowerShell 和 Git 环境；
- 可选的 Codex 连接诊断：检查本机代理、路由、进程连接和本地重试/HTTP 回退汇总；
- 本 README：解释如何安装规则，以及发现风险后如何处理。

它不会自动修改系统设置、Git 配置、文件编码、Codex 配置或项目内容。

> v0.2.0 仍是“跨平台规则模板 + Windows 优先的只读诊断脚本”，不是自动修复工具、代理切换器或常驻守护进程。

## 解决的问题

- Windows PowerShell 5.1 将中文通过原生命令管道时变成 `?`；
- UTF-8、BOM、GBK、UTF-16 的兼容性问题；
- LF、CRLF、mixed 行尾导致脚本或 Git 异常；
- Linux/macOS shell 与 Windows PowerShell/Cmd 语法混用；
- 中文、emoji、空格路径导致的任务失败；
- AI 编码代理依赖本机默认环境而产生不稳定命令。
- Codex/ChatGPT Desktop 是否实际连到声明的本地代理，以及本地是否出现可识别的流重试/HTTP 回退信号。

## 快速开始

克隆或下载本仓库后，在 Windows PowerShell 或 PowerShell 7 中运行只读诊断：

```powershell
pwsh -NoProfile -File .\scripts\doctor.ps1
```

如果尚未安装 PowerShell 7，脚本也支持 Windows PowerShell 5.1：

```powershell
powershell -NoProfile -File .\scripts\doctor.ps1
```

`doctor.ps1` 严格只读：不会创建、删除、转换或覆盖任何文件，也不会修改 Git、PowerShell 或 Windows 设置。

遇到 Codex 反复重连时，显式启用连接诊断（Windows v0.2.0）：

```powershell
pwsh -NoProfile -File .\scripts\doctor.ps1 -CodexConnectivity -SinceHours 24
```

`-CodexConnectivity` 仅检查本机状态，不会发起外部网络探测、切换节点、启用 TUN、修改系统代理或修改 Codex 配置。刚发生一次重连后，可以把窗口缩短为 `-SinceHours 1`，以便减少历史噪声。

开发者可运行不触及本机设置或日志的自检：

```powershell
pwsh -NoProfile -File .\scripts\doctor.ps1 -SelfTest
```

PowerShell 自带帮助也提供参数说明：`Get-Help .\scripts\doctor.ps1 -Full`。

## Codex 连接诊断（v0.2.0）

连接诊断默认关闭，当前只在 Windows 实现。启用后，它按以下顺序进行只读观察：

1. Windows 系统代理、当前进程的 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY`，以及仅变量名形式的持久环境变量；
2. 声明为回环地址的本地代理端口是否正在监听；
3. 名称或描述匹配 TUN、TAP、Wintun、WireGuard、VPN、Clash 或 Mihomo 的虚拟适配器是否承载 IPv4 默认路由；
4. 正在运行的 Codex 或 ChatGPT Desktop 进程是否有已建立 TCP 连接，并且是否连向声明的本地代理端口；
5. `CODEX_HOME`（或默认 `~/.codex`）根目录中 `logs*.sqlite` 的聚合结果：只统计固定的“流重试”和“回退 HTTP”信号的数量与最近时间。

它不会读取 `auth.json`，不会输出提示词、日志正文、工作目录、令牌、代理凭据或远程代理主机；非回环代理端点只显示为 `<remote>:端口`。日志数据库以 SQLite 只读方式查询，结果只保留计数和时间。它也不会上传任何结果。

| 结果 | 应如何理解 |
| --- | --- |
| `PASS`：本地代理端口监听且当前 Codex/ChatGPT Desktop 连向它 | 只能证明该时刻进程正在使用该本地代理，不能证明上游节点或 WebSocket 一定稳定。 |
| `WARN`：存在虚拟默认路由、代理端口未监听、或有流重试 | 说明路由/代理或流传输值得复核；请结合代理客户端和节点日志判断。 |
| `ACTION`：检测到可识别的 HTTP 回退记录 | 说明本机日志记录了该现象；这不是对某个节点、Codex 版本或服务端的唯一归因。 |

这项检查刻意不自动写入任何 Codex provider 配置。公开的 [Codex 配置 schema](https://github.com/openai/codex/blob/main/codex-rs/core/config.schema.json) 中存在 `supports_websockets` 和 `stream_max_retries` 等字段，但它们的适用范围会随版本和登录/Provider 方式变化；诊断工具只报告证据，不替用户做配置决策。

## 将规则用于 Codex

AgentGuard 提供三种规则模板：

- `templates/global-AGENTS.md`：跨平台、安全、低侵入的本机 Codex 默认规则；
- `templates/windows/global-AGENTS.windows.md`：可选的 Windows 增强规则，关注 `pwsh`、Windows PowerShell 5.1、UTF-8 管道和 `-LiteralPath`；
- `templates/repo-AGENTS.md`：适用于单个项目。

仓库发布的是通用模板副本，不是某位用户真实的 `~/.codex/AGENTS.md`。请不要将个人偏好、公司路径、私有命令、Token、代理地址或内网信息上传到公开模板中。

### 推荐：合并到全局 Codex 规则

全局规则文件默认位于 `~/.codex/AGENTS.md`。如果设置了 `CODEX_HOME`，则使用 `$CODEX_HOME/AGENTS.md`。

Windows PowerShell 示例：

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
New-Item -ItemType Directory -Force -Path $codexHome | Out-Null
$globalAgents = Join-Path $codexHome 'AGENTS.md'

notepad.exe $globalAgents
```

打开后，将 `templates/global-AGENTS.md` 中适合你的规则复制进去。若主要在 Windows 上使用 Codex，可再合并 `templates/windows/global-AGENTS.windows.md` 的增强规则。

保留已有的个人规则，并将 AgentGuard 模板作为补充；不要盲目覆盖已有内容。

### 可选：Windows 增强规则

`templates/windows/global-AGENTS.windows.md` 不是完整替代品；它应与跨平台全局模板一起手动合并。它只补充 Windows 和 PowerShell 的编码、路径及 shell 约定，不会要求 Linux 或 macOS 项目使用 Windows 命令。

### 可选：完整替换全局 `AGENTS.md`

仅当你确认当前全局规则为空或不再需要时，才使用完整替换。先备份已有文件：

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
New-Item -ItemType Directory -Force -Path $codexHome | Out-Null
$globalAgents = Join-Path $codexHome 'AGENTS.md'

if (Test-Path -LiteralPath $globalAgents) {
  $backup = "$globalAgents.$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
  Copy-Item -LiteralPath $globalAgents -Destination $backup -ErrorAction Stop
}
```

再复制模板：

```powershell
Copy-Item -LiteralPath .\templates\global-AGENTS.md -Destination $globalAgents -Force
```

不要覆盖 `~/.codex/config.toml`，也不要覆盖整个 `~/.codex` 目录。AgentGuard 只管理 `AGENTS.md` 中的自然语言执行规则。

### 将规则用于单个仓库

如果项目根目录没有 `AGENTS.md`：

```powershell
Copy-Item -LiteralPath .\templates\repo-AGENTS.md -Destination .\AGENTS.md
```

如果项目已经有 `AGENTS.md`，请手动合并，不要覆盖。

仓库级规则可以比全局规则更具体，例如项目的构建、测试和部署命令；指定的运行时版本；`.editorconfig`、`.gitattributes` 的要求；以及生成文件、第三方代码和特殊脚本的例外。

## 规则优先级

模板只有在复制到全局或仓库后才会生效；它不是一个独立的运行时规则层。

```text
用户明确要求
  ↓
当前目录：AGENTS.override.md 或 AGENTS.md
  ↓
父目录至仓库根目录：每层一个 AGENTS 文件
  ↓
全局：$CODEX_HOME/AGENTS.override.md 或 AGENTS.md
```

在每一层目录中，非空的 `AGENTS.override.md` 优先于 `AGENTS.md`，两者不会同时合并。项目层从仓库根目录读取到当前目录，越接近当前目录的规则越晚合并、优先级越高。

全局模板只放安全、普适、低侵入的规则，例如：

- 不依赖默认编码、行尾、时区和当前目录；
- 使用带空格、中文、emoji 的路径时正确引用；
- 使用项目要求的 shell 和解释器，不混用 shell 语法；
- 复杂命令避免多层引号和重定向；
- 不主动重写生成文件、第三方文件或项目已有格式。

项目专属偏好不应放入全局模板。Codex 在新任务或新会话开始时构建规则链；编辑后请新开任务或重启相应会话。合并后的规则总大小也有限制，因此全局模板应保持简短。有关发现顺序、`CODEX_HOME` 和大小限制，请参阅 [Codex 官方 AGENTS.md 文档](https://learn.chatgpt.com/docs/agent-configuration/agents-md)。

本机全局规则只服务于本机 Codex 环境；不要假设 Codex 云端或远程任务能读取你电脑上的 `.codex` 目录。

## 公开模板安全边界

公开的 `AGENTS.md` 模板不应包含：

- 个人姓名、公司名称、私有仓库路径、内网域名；
- API Key、Token、代理地址或 Git 凭据；
- 某个项目专属的构建、测试和部署命令；
- “每次都安装依赖”“每次都提交代码”等高侵入操作；
- 强制所有系统使用 Windows 命令的规则。

适合公开模板的内容包括编码和路径安全、尊重项目规则、PowerShell 非 ASCII 管道处理、以及不主动改写生成文件或第三方文件等通用约定。

## `doctor.ps1` 检查内容

默认模式重点检查 Windows：

- Windows PowerShell 5.1 与 PowerShell 7 是否存在；
- Console Input/Output 编码与 `$OutputEncoding`；
- Git `core.autocrlf` 与行尾状态；
- `.editorconfig`、`.gitattributes`、`AGENTS.md` 是否存在；
- 已跟踪文本文件是否出现 mixed 行尾；
- 已跟踪的 `.ps1`、`.sh`、`.bat`、`.cmd` 的常见编码与换行风险。

附加 `-CodexConnectivity` 后，才会执行上一节的连接诊断；默认模式不会枚举进程、读取网络状态或访问 `.codex` 日志数据库。

检查结果分为：

| 级别 | 含义 |
| --- | --- |
| PASS | 未发现已知风险 |
| INFO | 环境信息或可选建议 |
| WARN | 有兼容性风险，建议确认 |
| ACTION | 已明确违反项目规则，或有较高概率导致错误 |

`mixed` 行尾不自动等同于错误。若文件由 `.gitattributes`、项目规范或生成工具明确允许，应保留原状；脚本只会提示复核。若 Git 明确为该文件声明 `eol=lf` 或 `eol=crlf`，却检测到 mixed 行尾，才会报告为 `ACTION`。

## 平台处理

### Windows

- 优先使用 `pwsh`；Windows PowerShell 5.1 仍可运行本诊断脚本。
- Windows PowerShell 5.1 将非 ASCII 内容传给原生命令时，显式将 Console Input/Output 编码和 `$OutputEncoding` 设为 UTF-8，或使用 UTF-8 临时文件代替管道。
- 需要兼容 Windows PowerShell 5.1 且包含中文提示的 `.ps1`，使用 UTF-8 with BOM；AgentGuard 的 `doctor.ps1` 已按此方式保存。
- 如下载的脚本被执行策略阻止，请按你的组织策略处理；不要为了运行诊断而永久放宽全局执行策略。

### macOS 和 Linux

- 使用 UTF-8 locale；可用 `locale` 查看当前环境。
- 文本文件优先 LF，但以项目的 `.gitattributes` 和 `.editorconfig` 为准。
- 使用 Bash、Zsh 或 POSIX shell 时遵循其自身语法，避免混入 PowerShell 或 Cmd 语法。

### 所有平台

项目已有的 `.gitattributes`、`.editorconfig`、`AGENTS.md` 和构建工具规则优先。不主动统一生成文件、第三方文件或被项目刻意保留为 CRLF 的文件。

## 安全原则

AgentGuard 默认：

- 不上传源代码；
- 不访问密钥、Token 或 Git 凭据；
- 不读取 Codex `auth.json`，也不显示本地日志正文；
- 不修改 Windows 注册表、系统代码页或 PowerShell Profile；
- 不改 Git 全局配置；
- 不修改系统代理、TUN、路由、节点或 Codex provider 配置；
- 不自动转换全仓文件；
- 不扫描 `node_modules`、`vendor`、构建产物或二进制文件；
- 不因单个合法 CRLF 文件要求整个仓库重写。

## 项目状态

当前为 v0.2.0：

1. 跨平台 `AGENTS.md` 模板；
2. Windows 优先、严格只读的 `doctor.ps1`；
3. 可选的 Codex 本机代理、路由、进程连接与本地重试/HTTP 回退诊断；
4. 代理与日志隐私边界、结果解释和可重复自检。

后续是否增加其他平台检测、GitHub Action、CLI 或自动修复，取决于真实使用反馈；任何自动修复都应保持显式授权和可撤销。

## 许可证

本项目采用 [MIT License](LICENSE)。
