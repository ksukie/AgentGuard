# AgentGuard / AgentPolicy

> 通过唯一入口 `@AgentPolicy` 使用 Agent/Codex 诊断、`AGENTS.md` 策略模板与任务上下文梳理。

AgentGuard 帮助发现 AI 编码代理环境中的编码、换行、路径与 Codex 连接风险，也能把长对话重建为可继续执行的当前任务上下文。AgentPolicy 将这些功能封装为一个只接受显式调用的 Skill；安装本身不会触发任何功能。

## 功能

| 功能                 | 解决的问题                                                                           | 平台                  | 详细说明                                                                 |
| -------------------- | ------------------------------------------------------------------------------------ | --------------------- | ------------------------------------------------------------------------ |
| Agent/Codex 诊断     | PowerShell/Python 编码、Git 行尾、脚本兼容性、仓库规则、代理、TUN 与 Codex 重连信号 | Windows               | [仓库诊断](docs/doctor.md) · [连接诊断](docs/codex-connectivity.md)      |
| AGENTS.md 策略模板   | 全局、Windows 增强与仓库级执行规则                                                    | Windows、macOS、Linux | [查看文档](docs/agents-templates.md)                                     |
| 任务上下文梳理与续接 | 当前任务主线、代码或执行流程、关键做法、有效状态、未决分支与下一步                   | Windows、macOS、Linux | [查看文档](docs/context-structuring.md)                                  |

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
@AgentPolicy 总结当前任务上下文
@AgentPolicy 生成可供新会话继续的上下文
```

空调用会展示固定能力菜单；任务明确时会直接执行，不会要求重复选择。

## 显式调用边界

只有当前消息显式调用 `@AgentPolicy`（或文本客户端中的 `$agent-policy`）时，Skill 才会运行。它不会因为已经安装、请求内容碰巧匹配、上一轮调用过或会话很长而隐式启动，也不会自动诊断或总结上下文。

更新检查同样只在显式调用后运行。插件没有全局消息提交 Hook，也没有安装后常驻的后台任务。

<a id="update"></a>

## 更新

AgentPolicy 会在显式调用后进行低频版本检查：正常情况下每 72 小时最多联网一次，失败后 12 小时重试，发现新版本后每 36 小时最多提醒一次。检查失败保持静默，更新提醒只在主要任务完成后显示。

它不会自动拉取、安装或覆盖文件。更新插件：

```text
codex plugin marketplace upgrade agentguard
codex plugin remove agent-policy@agentguard
codex plugin add agent-policy@agentguard
```

更新后开始一个新会话。设置 `AGENT_POLICY_UPDATE_CHECK=0` 可关闭更新检查。

## 安全承诺

默认不上传源代码，不读取密钥或 `auth.json`，不修改注册表、系统代理、TUN、路由、Git 或 Codex 配置。更新检查只读取固定的 GitHub `release.json`，并仅在插件数据或用户状态目录写入自己的节流状态。

## 许可证

[MIT](LICENSE)
