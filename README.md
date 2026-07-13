# AgentGuard

让 AI 编码代理在 Windows、macOS 和 Linux 上更稳定地执行任务。

AgentGuard 是一套可复制的跨平台协作基线：

- `AGENTS.md` 模板：告诉 Codex 如何避免编码、换行和 shell 兼容性问题；
- `doctor.ps1`：只读检查当前 Windows、PowerShell 和 Git 环境；
- 本 README：解释如何安装规则，以及发现风险后如何处理。

它不会自动修改系统设置、Git 配置、文件编码或项目内容。

> 第一版是“跨平台规则模板 + Windows 优先的只读诊断脚本”，不是自动修复工具。

## 解决的问题

- Windows PowerShell 5.1 将中文通过原生命令管道时变成 `?`；
- UTF-8、BOM、GBK、UTF-16 的兼容性问题；
- LF、CRLF、mixed 行尾导致脚本或 Git 异常；
- Linux/macOS shell 与 Windows PowerShell/Cmd 语法混用；
- 中文、emoji、空格路径导致的任务失败；
- AI 编码代理依赖本机默认环境而产生不稳定命令。

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

## 将规则用于 Codex

AgentGuard 提供两种规则模板：

- `templates/global-AGENTS.md`：适用于本机 Codex 默认规则；
- `templates/repo-AGENTS.md`：适用于单个项目。

### 推荐：合并到全局 Codex 规则

全局规则文件默认位于 `~/.codex/AGENTS.md`。如果设置了 `CODEX_HOME`，则使用 `$CODEX_HOME/AGENTS.md`。

Windows PowerShell 示例：

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
New-Item -ItemType Directory -Force -Path $codexHome | Out-Null
$globalAgents = Join-Path $codexHome 'AGENTS.md'

notepad.exe $globalAgents
```

打开后，将 `templates/global-AGENTS.md` 中适合你的规则复制进去。

保留已有的个人规则，并将 AgentGuard 模板作为补充；不要盲目覆盖已有内容。

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
- PowerShell 中传递非 ASCII 内容时显式处理 UTF-8；
- 复杂命令避免多层引号和重定向；
- 不主动重写生成文件、第三方文件或项目已有格式。

项目专属偏好不应放入全局模板。

## `doctor.ps1` 检查内容

当前第一版重点检查 Windows：

- Windows PowerShell 5.1 与 PowerShell 7 是否存在；
- Console Input/Output 编码与 `$OutputEncoding`；
- Git `core.autocrlf` 与行尾状态；
- `.editorconfig`、`.gitattributes`、`AGENTS.md` 是否存在；
- 已跟踪文本文件是否出现 mixed 行尾；
- 已跟踪的 `.ps1`、`.sh`、`.bat`、`.cmd` 的常见编码与换行风险。

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
- 不修改 Windows 注册表、系统代码页或 PowerShell Profile；
- 不改 Git 全局配置；
- 不自动转换全仓文件；
- 不扫描 `node_modules`、`vendor`、构建产物或二进制文件；
- 不因单个合法 CRLF 文件要求整个仓库重写。

## 项目状态

当前为 v0.1 MVP：

1. 跨平台 `AGENTS.md` 模板；
2. Windows 优先、严格只读的 `doctor.ps1`；
3. 清晰的平台化修复说明。

后续是否增加 CLI、自动修复、GitHub Action 或 Codex Plugin，取决于真实使用反馈。

## 许可证

建议使用 MIT License。
