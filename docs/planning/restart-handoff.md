# ourclaw 重启续做指引

如果 IDE / 会话重启，新的大模型请按下面顺序恢复上下文：

## 1. 必读文档顺序

1. `README.md`
2. `WORKSPACE_CONTEXT.md`
3. `ourclaw/docs/specs/framework-based-ourclaw/tasks.md`
4. `ourclaw/docs/specs/framework-based-ourclaw/next-stage-backlog.md`
5. `docs/planning/current-task-board.md`
6. `ourclaw/docs/planning/session-resume.md`
7. `ourclaw/docs/README.md`

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

现在继续开发时，以 `ourclaw/docs/specs/framework-based-ourclaw/tasks.md` 为主入口。

如果 `tasks.md` 显示主线已完成，则继续转到 `ourclaw/docs/specs/framework-based-ourclaw/next-stage-backlog.md`，不要再从旧 `full-business-gap-tasks.md` 恢复任务。

## 4. 当前建议下一步

按 `docs/planning/current-task-board.md` 的“下一步”与 `next-stage-backlog.md` 的优先级继续。

如果没有新指令，默认原则：

1. 先看 `next-stage-backlog.md` 中当前仍为 `active` 的项
2. 若 `B6` 未完成，优先继续清理文档入口与历史映射
3. `B6` 完成后，再进入 `B4`

## 5. 工作约定

- 只要有新的设计判断、阶段结论、阻塞或任务拆分，立刻写回 `docs/`
- 不要只把上下文留在对话里
- 当前执行中的任务状态优先写回 `docs/planning/current-task-board.md`
- 完成一轮后，优先更新：
  - `docs/planning/current-task-board.md`
  - `ourclaw/docs/planning/session-resume.md`
  - `ourclaw/docs/specs/framework-based-ourclaw/tasks.md`
  - `ourclaw/docs/specs/framework-based-ourclaw/next-stage-backlog.md`

## 6. 最短启动提示词

可直接对新大模型说：

先读：
`README.md`
`WORKSPACE_CONTEXT.md`
`ourclaw/docs/specs/framework-based-ourclaw/tasks.md`
`ourclaw/docs/specs/framework-based-ourclaw/next-stage-backlog.md`
`docs/planning/current-task-board.md`
`ourclaw/docs/planning/session-resume.md`
`ourclaw/docs/README.md`

然后先按 `docs/planning/current-task-board.md` 的“当前清单 / 下一步”恢复执行，再按 `next-stage-backlog.md` 中的 `active / todo` 顺序继续开发，不要把归档任务重新当成活跃项，并把新的阶段结论及时写回 docs。
