# ourclaw 重启续做指引

如果 IDE / 会话重启，新的大模型请按下面顺序恢复上下文：

## 1. 必读文档顺序

1. `README.md`
2. `WORKSPACE_CONTEXT.md`
3. `docs/planning/current-task-board.md`
4. `ourclaw/docs/planning/session-resume.md`
5. `ourclaw/docs/planning/full-business-gap-tasks.md`
6. `ourclaw/docs/README.md`

如果当前任务涉及具体专题，再继续读：

- agent / session / stream：`ourclaw/docs/architecture/agent-runtime.md`
- adapter：`ourclaw/docs/architecture/adapters.md`
- provider / channel / tool：`ourclaw/docs/architecture/provider-channel-tool.md`
- config：`ourclaw/docs/architecture/config-runtime.md`
- runtime event：`ourclaw/docs/contracts/runtime-event.md`
- task state：`ourclaw/docs/contracts/task-state.md`

## 2. 当前状态简述

- `framework` 共享运行时底座已经基本成型，可通过 `zig build test`
- `ourclaw` 已经有最小业务层、最小命令域、最小 adapter、第一版 agent runtime、memory runtime、diagnostics/event 查询面
- `ourclaw-manager` 仍主要是骨架

## 3. 当前任务主线

现在继续开发时，以 `ourclaw/docs/planning/full-business-gap-tasks.md` 为准。

优先关注仍然是 `partial` 的项，不要重复做已标记 `done` 的项。

## 4. 当前建议下一步

按 `ourclaw/docs/planning/session-resume.md` 末尾的“建议下一步”继续。

如果没有新指令，默认原则：

1. 先收口 `FB-19`
2. 再收口 `FB-23`
3. 再收口 `FB-24` ~ `FB-31`

## 5. 工作约定

- 只要有新的设计判断、阶段结论、阻塞或任务拆分，立刻写回 `docs/`
- 不要只把上下文留在对话里
- 当前执行中的任务状态优先写回 `docs/planning/current-task-board.md`
- 完成一轮后，优先更新：
  - `docs/planning/current-task-board.md`
  - `ourclaw/docs/planning/session-resume.md`
  - `ourclaw/docs/planning/full-business-gap-tasks.md`

## 6. 最短启动提示词

可直接对新大模型说：

先读：
`README.md`
`WORKSPACE_CONTEXT.md`
`docs/planning/current-task-board.md`
`ourclaw/docs/planning/session-resume.md`
`ourclaw/docs/planning/full-business-gap-tasks.md`
`ourclaw/docs/README.md`

然后先按 `docs/planning/current-task-board.md` 的“当前清单 / 下一步”恢复执行，再按当前仍为 `partial` / `todo` 的任务继续开发，不要重复实现 `done` 项，并把新的阶段结论及时写回 docs。
