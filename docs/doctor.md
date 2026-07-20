# 环境与仓库诊断

[← 返回主页](../README.md)

AgentTools 提供 Windows 优先的只读诊断。内部诊断器检查当前目录，也可以检查用户明确指定的其他仓库。

## 运行

```text
@AgentTools 检查当前仓库
@AgentTools 检查 C:\path\to\repo
```

AgentTools 优先使用 PowerShell 7；没有 PowerShell 7 时使用 Windows PowerShell 5.1。

## 检查内容

| 范围 | 检查项 |
| --- | --- |
| PowerShell | PowerShell 5.1 / 7 可用性、控制台输入输出编码与 `$OutputEncoding`。 |
| Python | Python 3 默认文本编码、UTF-8 Mode 与文件系统编码。 |
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
- Python 读取 UTF-8 文本时显式使用 `encoding="utf-8"`；第三方工具依赖系统默认编码时，可为该次运行设置 `PYTHONUTF8=1` 或使用 `-X utf8`；
- 已有 `.gitattributes`、`.editorconfig`、`AGENTS.md` 和构建工具规则优先于通用建议；
- 不要为了消除单个警告而统一转换整个仓库的行尾或编码。

## 边界

诊断不会创建、删除、转换或覆盖仓库文件，也不会修改 Git、PowerShell 或 Windows 设置。
