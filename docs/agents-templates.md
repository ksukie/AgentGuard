# AGENTS 规则模板

[← 返回主页](../README.md)

这些模板为 Codex 提供安全、低侵入的执行规则。它们是可复制的起点，不是对个人或项目规则的替代。

## 选择模板

| 模板 | 适用位置 | 内容 |
| --- | --- | --- |
| [global-AGENTS.md](../templates/global-AGENTS.md) | 全局 Codex 规则 | 跨平台的编码、行尾、路径和 shell 约定。 |
| [global-AGENTS.windows.md](../templates/windows/global-AGENTS.windows.md) | Windows 用户的全局补充 | `pwsh`、Windows PowerShell 5.1、UTF-8 管道与 `-LiteralPath`。 |
| [repo-AGENTS.md](../templates/repo-AGENTS.md) | 单个仓库 | 构建、测试、运行时和项目例外的占位结构。 |

Windows 增强模板应与通用全局模板合并使用，不应把 Windows 命令强加给 macOS 或 Linux 项目。

## 全局规则

默认全局目录是 `~/.codex`；设置 `CODEX_HOME` 时则使用该目录。先打开现有文件，再手动合并适用条目：

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
New-Item -ItemType Directory -Force -Path $codexHome | Out-Null
notepad.exe (Join-Path $codexHome 'AGENTS.md')
```

不要覆盖已有的 `AGENTS.md`、`config.toml` 或整个 `.codex` 目录。全局规则只保留跨项目通用的约定。

## 仓库规则

若仓库还没有 `AGENTS.md`，可复制模板后填写占位项：

```powershell
Copy-Item -LiteralPath .\templates\repo-AGENTS.md -Destination .\AGENTS.md
```

若文件已经存在，请手动合并。仓库规则应写明真实的安装、构建、测试和部署命令，以及生成文件、第三方代码或安全要求等项目例外。

## 优先级与公开边界

用户明确要求优先；项目中更接近当前目录的规则通常比全局规则更具体。在同一目录中，非空的 `AGENTS.override.md` 优先于 `AGENTS.md`。完整发现规则见 [Codex 官方 AGENTS.md 文档](https://learn.chatgpt.com/docs/agent-configuration/agents-md)。

公开模板不要包含公司路径、内网域名、私有命令、Token、代理地址或 Git 凭据。
