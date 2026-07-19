# AgentGuard / AgentPolicy

> 通过唯一入口 `@AgentPolicy` 使用 Agent/Codex 诊断与 `AGENTS.md` 策略模板。

AgentGuard 帮助发现 AI 编码代理环境中的编码、换行、路径与 Codex 连接风险。AgentPolicy 将现有功能封装为一个显式调用的 Skill；诊断不会修改系统、代理、Git 或 Codex 配置。

## 功能

| 功能            | 解决的问题                                             | 平台                  | 详细说明                              |
| --------------- | ------------------------------------------------------ | --------------------- | ------------------------------------- |
| 环境与仓库诊断  | PowerShell/Python 编码、Git 行尾、脚本兼容性与仓库规则 | Windows               | [查看文档](docs/doctor.md)             |
| Codex 连接诊断  | 代理、TUN 路由、进程连接、流重试与 HTTP 回退           | Windows               | [查看文档](docs/codex-connectivity.md) |
| AGENTS 规则模板 | 全局与仓库级执行规则                                   | Windows、macOS、Linux | [查看文档](docs/agents-templates.md)   |

## 开始使用

安装仓库中的插件：

```text
codex plugin marketplace add ksukie/AgentGuard
codex plugin add agent-policy@agentguard
```

安装后开始一个新会话。在支持 Skill 选择器的界面使用 `@AgentPolicy`；文本客户端使用 `$agent-policy`。

```text
@AgentPolicy
@AgentPolicy 你能做什么
@AgentPolicy 检查当前仓库
@AgentPolicy 排查最近 1 小时的 Codex 重连
@AgentPolicy 展示仓库级 AGENTS.md 模板
```

空调用会展示固定能力菜单；任务明确时会直接执行，不会要求重复选择。

<a id="update"></a>

## 更新

AgentPolicy 会在显式调用时进行低频版本检查：正常情况下每 72 小时最多联网一次，失败后 12 小时重试，发现新版本后每 36 小时最多提醒一次。检查失败保持静默，更新提醒只在主要任务完成后显示。

它不会自动拉取、安装或覆盖文件。更新插件：

```text
codex plugin marketplace upgrade agentguard
codex plugin remove agent-policy@agentguard
codex plugin add agent-policy@agentguard
```

更新后开始一个新会话。设置 `AGENT_POLICY_UPDATE_CHECK=0` 可关闭后台更新检查。

## 安全承诺

默认不上传源代码，不读取密钥或 `auth.json`，不修改注册表、系统代理、TUN、路由、Git 或 Codex 配置。更新检查只读取固定的 GitHub `release.json`，并仅在插件数据或用户状态目录写入自己的节流状态。

## 许可证

[MIT](LICENSE)
