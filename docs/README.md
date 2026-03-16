# ourclaw 文档

## 默认入口

如果要继续推进 `ourclaw`，默认只看：

1. `ourclaw/docs/specs/reference-aligned-ourclaw/requirements.md`
2. `ourclaw/docs/specs/reference-aligned-ourclaw/design.md`
3. `ourclaw/docs/specs/reference-aligned-ourclaw/tasks.md`

## 文档分层

### Active spec

- `ourclaw/docs/specs/reference-aligned-ourclaw/README.md`
- `ourclaw/docs/specs/reference-aligned-ourclaw/requirements.md`
- `ourclaw/docs/specs/reference-aligned-ourclaw/design.md`
- `ourclaw/docs/specs/reference-aligned-ourclaw/tasks.md`

### Baseline / historical spec

- `ourclaw/docs/backup/framework-based-ourclaw/requirements.md`
- `ourclaw/docs/backup/framework-based-ourclaw/design.md`
- `ourclaw/docs/backup/framework-based-ourclaw/tasks.md`
- `ourclaw/docs/backup/framework-based-ourclaw/next-stage-backlog.md`
- `ourclaw/docs/specs/framework-based-ourclaw/archive/completed-mainline-tasks-2026-03-16.md`

### Supporting docs

- `ourclaw/docs/architecture/*`
- `ourclaw/docs/architecture/README.md`
- `ourclaw/docs/contracts/*`
- `ourclaw/docs/contracts/manager-runtime-surface.md`

### Shared foundation docs

- `framework/docs/README.md`
- `framework/docs/architecture/logging.md`
- `framework/docs/architecture/validation.md`
- `framework/docs/architecture/runtime-pipeline.md`

### Historical / recovery docs

- `ourclaw/docs/planning/README.md`
- `ourclaw/docs/planning/session-resume.md`
- `ourclaw/docs/planning/restart-handoff.md`
- `ourclaw/docs/backup/planning/full-business-gap-tasks.md`
- `ourclaw/docs/planning/nullclaw-gap-analysis.md`
- `ourclaw/docs/backup/planning/next-session-handoff-2026-03-13.md`
- `ourclaw/docs/backup/planning/implementation-epics.md`
- `ourclaw/docs/backup/planning/llm-task-breakdown.md`

## 说明

`architecture/` 与 `planning/` 继续保留重要背景价值，但当前默认主入口已经切换到 `reference-aligned-ourclaw`。

## 当前进展摘要

- `framework-based-ourclaw/`：已完成的一阶段基线
- `reference-aligned-ourclaw/`：当前 active spec 与完整任务表
- 当前代码基线已经覆盖 core runtime、control-plane、扩展子域与 manager contract 第一版
- 如需看细节，请优先读：
  - `ourclaw/docs/specs/reference-aligned-ourclaw/requirements.md`
  - `ourclaw/docs/specs/reference-aligned-ourclaw/design.md`
  - `ourclaw/docs/specs/reference-aligned-ourclaw/tasks.md`
  - `ourclaw/docs/planning/session-resume.md`

## 建议后续补充

- `ourclaw/docs/contracts/runtime-event.md`
- `ourclaw/docs/contracts/task-state.md`
- `ourclaw/docs/contracts/logging-config.md`

## 说明

当前文档来自对 `nullclaw-manager`、`nullclaw`、`openclaw` 的对比分析，目的是为后续详细设计和任务拆分提供统一基线。
