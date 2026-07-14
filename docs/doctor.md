# 环境与仓库诊断

[← 返回主页](../README.md)

`scripts/doctor.ps1` 是 Windows 优先的只读诊断入口。默认检查当前目录；可用 `-Path` 指定其他仓库。

## 运行

```powershell
# 检查当前目录
pwsh -NoProfile -File .\scripts\doctor.ps1

# 检查指定仓库
pwsh -NoProfile -File .\scripts\doctor.ps1 -Path C:\path\to\repo

# 验证脚本自身的代理解析与脱敏逻辑
pwsh -NoProfile -File .\scripts\doctor.ps1 -SelfTest
```

Windows PowerShell 5.1 也可运行：将 `pwsh` 替换为 `powershell`。

## 检查内容

| 范围 | 检查项 |
| --- | --- |
| PowerShell | PowerShell 5.1 / 7 可用性、控制台输入输出编码与 `$OutputEncoding`。 |
| Git | `core.autocrlf`、已跟踪文本文件的行尾状态。 |
| 仓库规则 | `.editorconfig`、`.gitattributes`、`AGENTS.md` 是否存在。 |
| 脚本文件 | `.ps1`、`.sh`、`.bat`、`.cmd` 的 BOM、编码与常见换行风险。 |

`node_modules`、`vendor`、构建产物、二进制文件和 `.git` 会被跳过。`mixed` 行尾本身不一定是错误；只有与明确的 Git 行尾属性冲突时才应视为需要处理的问题。

## 结果含义

| 级别 | 含义 | 下一步 |
| --- | --- | --- |
| `PASS` | 未发现已知风险。 | 无需操作。 |
| `INFO` | 环境信息或未确认的状态。 | 按需查看。 |
| `WARN` | 有兼容性风险。 | 结合项目规则复核。 |
| `ACTION` | 已发现较强的失败信号。 | 先确认项目约定，再做最小修复。 |

常见处理方式：

- PowerShell 5.1 处理中文并调用原生命令时，显式使用 UTF-8，或使用 UTF-8 临时文件；
- 已有 `.gitattributes`、`.editorconfig`、`AGENTS.md` 和构建工具规则优先于通用建议；
- 不要为了消除单个警告而统一转换整个仓库的行尾或编码。

## 边界

脚本不会创建、删除、转换或覆盖仓库文件，也不会修改 Git、PowerShell 或 Windows 设置。完整参数可通过以下命令查看：

```powershell
Get-Help .\scripts\doctor.ps1 -Full
```
