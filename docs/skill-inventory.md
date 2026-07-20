# Codex Skill 清单与调用审计

这个功能通过当前 Codex 运行时列出当前工作目录实际可发现的全部 Skill：

```text
@AgentTools 列出当前 Codex 的全部 Skill
```

这是该功能唯一保留的公开示例，不是精确匹配口令。只要当前消息显式调用 AgentTools，并涉及发现、查找、检查、审计或排查本地/当前 Codex Skill，都会进入同一个运行时清单流程，不会拆成不同功能或改走文件缓存扫描。全量问题列出全部 Skill；针对某个 Skill 的问题则基于同一份完整清单聚焦回答。

一次调用会输出：

- Skill 总数、启用与停用数量；
- 允许隐式调用、仅显式调用和状态未知的数量；
- 每个 Skill 的名称、来源或插件、启用状态和调用模式；
- 每个 Skill 的显式调用语法、用途和 README 位置；
- Skill 发现错误、无效调用策略和同名冲突。

“允许隐式调用”表示 Codex 可以在任务与 Skill 描述匹配时选择它，不表示 Skill 会在启动时或每轮自动运行。`allow_implicit_invocation: false` 表示仅允许显式调用；未配置该字段时，Codex 默认为允许隐式调用。

清单来自 Codex 的 `skills/list` 运行时结果，不会把磁盘上的未安装插件缓存算作当前 Skill。扫描只读取公开 Skill 元数据和调用策略，不会激活被列出的 Skill，也不会输出完整 `SKILL.md`、README 内容或隐藏指令。
