# 基于 framework 完成 ourclaw 主线开发 — Requirements

> 使用说明（2026-03-13）：本文件定义目标与边界，但不表示所有能力都尚未开始。当前 `framework/` 与 `ourclaw/` 已有大量第一版实现；任务状态请以同目录 `tasks.md` 的已校准状态为准，阶段进展请结合 `ourclaw/docs/planning/session-resume.md` 阅读。
>
> 说明（2026-03-16）：本文件现在主要承担 phase-1 baseline 说明角色；新的 active spec 已切换到 `ourclaw/docs/specs/reference-aligned-ourclaw/`。

## 1. 背景

工作区的主线目标不是继续扩写 `nullclaw/` 或 `openclaw/`，而是：

- 在 `framework/` 中沉淀 Zig 通用基础能力
- 在 `ourclaw/` 中实现对标 `nullclaw` / 参考 `openclaw` 的 claw runtime、agent、gateway、tool、stream、service 业务能力

当前 `framework/` 已具备共享运行时主干，`ourclaw/` 已具备一版业务骨架与部分真实实现，但距离“基于 framework 完成 ourclaw 主线开发”仍存在明显能力缺口与边界不稳定问题。

本 spec 的目标是为后续大模型提供一个可执行的中文规格包，统一回答三件事：

1. 要完成什么
2. 这些能力应该落到哪里
3. 后续应该按什么顺序推进

## 1.1 当前实现状态摘要

截至 2026-03-13，当前主线不是“从零开始”，而是“共享底座 + 业务第一版已落地，继续向完整业务版收口”：

- `framework/` 已具备共享运行时主干：`AppContext`、`CommandDispatcher`、`TaskRunner`、`EventBus`、统一错误模型、校验、envelope、配置写回链路均已落地第一版。
- `ourclaw/` 已具备业务第一版主线：`runtime/app_context.zig`、`agent_runtime.zig`、`memory_runtime.zig`、`stream_output.zig`、`stream_registry.zig`、`gateway_host.zig`、`runtime_host.zig`、`service_manager.zig`、`daemon.zig` 等关键骨架与部分真实行为已存在。
- CLI / Bridge / HTTP 已接入统一 dispatcher；SSE / WebSocket / bridge NDJSON / CLI live 已有第一版流式投影能力。
- provider / tool / config / diagnostics / events / metrics / skills / cron / mcp / hardware 等命令面与运行时语义已进入“第一版可用，但尚未完整业务版”的阶段。

因此，本 spec 的真实语义应理解为：

1. 保持主线边界稳定
2. 在已落地第一版的基础上继续补齐与深化
3. 避免后续模型重复实现已经存在的骨架与第一版行为

## 2. 目标

本 spec 要求后续开发工作完成以下目标：

1. 以 `framework/` 作为共享底座，稳定承接日志、校验、错误、事件、任务、配置写回、AppContext 等横切能力。
2. 以 `ourclaw/` 作为业务主线，完成 runtime、agent、provider、channel、tool、memory、stream、gateway、service 等能力落地。
3. 明确“共享能力进入 framework、claw 业务能力进入 ourclaw”的边界，避免后续模型误把共享能力写回业务层，或把业务语义塞回框架层。
4. 将 `nullclaw/` 与 `openclaw/` 的参考价值显式化为“参考文件路径 + 参考目的 + 主线落点”，降低后续协作中的盲目推理。
5. 为后续实现提供可追踪 tasks 列表，支持多轮大模型逐步完成主线开发。

## 3. 范围

### 3.1 本 spec 覆盖范围

- `framework/` 共享运行时与通用能力边界
- `ourclaw/` 业务运行时与核心域能力边界
- `ourclaw/docs/specs/framework-based-ourclaw/` 下的 requirements / design / tasks 三件套
- 参考映射：`nullclaw/`、`openclaw/` 的关键文件到主线落点的映射关系

### 3.2 本 spec 不覆盖范围

- 不直接修改 `nullclaw/` 或 `openclaw/`
- 不把 `ourclaw-manager/` 的完整消费面纳入本 spec 统一实现
- 不把现有 `ourclaw/docs/architecture/*.md` 和 `ourclaw/docs/planning/*.md` 全量重写
- 不在本 spec 中定义所有低层实现细节与所有接口字段

## 4. 需求陈述

### R1. 主线边界必须明确

后续实现必须遵守：

- 无 claw 业务语义、可跨应用复用的能力进入 `framework/`
- 带有 agent / provider / channel / tool / gateway / memory / stream / service 业务语义的能力进入 `ourclaw/`

### R2. ourclaw 必须建立统一运行时主干

CLI、Bridge、HTTP、Daemon / Service 等入口最终必须汇聚到统一执行主干，而不是各自维护一套日志、错误、校验和任务处理逻辑。

补充说明：当前统一执行主干的第一版已经存在，后续重点不是重新搭主干，而是继续稳定入口协议、流式控制语义和运行时边界。

### R3. agent runtime 必须成为业务核心

`ourclaw` 不应只停留在命令骨架，而应逐步形成完整 agent 主循环，覆盖：

- request → session → prompt → provider → tool → memory → stream → result

补充说明：当前最小闭环已存在，后续重点是补齐更完整的 session 结构、tool loop 边界、memory 长期能力与更接近生产级的 agent 行为。

### R4. 参考映射必须显式化

后续设计与任务文档中，每个关键能力点必须明确给出：

- 主线目标文件/目录
- `nullclaw` 参考文件
- `openclaw` 参考文件
- 参考目的

### R5. 后续实现必须可验证

tasks 必须能指导后续模型执行，并且每一项都要带：

- 前置依赖
- 完成定义
- 目标落点
- 参考锚点
- 验证方式

## 5. 非目标

以下内容不是本 spec 的直接交付目标：

1. 一次性完成 `ourclaw` 全部业务能力
2. 把 `openclaw` 逐文件翻译为 Zig
3. 让 `framework/` 承担 `ourclaw` 业务语义
4. 在本次文档交付中完成 manager 端协同设计全量闭环

## 6. 验收标准

本 spec 交付完成时，应满足：

1. 存在中文 `requirements.md`、`design.md`、`tasks.md`
2. 三份文档共同覆盖：范围、落点、参考锚点、任务拆解、验证方式
3. `design.md` 中每个关键能力点都能定位到主线落点与参考文件
4. `tasks.md` 可被未来大模型逐步执行，不需要重新做大范围架构猜测
5. 文档明确区分“第一版已落地的能力”与“仍待继续深化的能力”，避免重复开工

## 7. 影响面

### framework 侧

- `framework/src/runtime/*`
- `framework/src/app/*`
- `framework/src/config/*`
- `framework/src/observability/*`
- `framework/src/core/*`
- `framework/src/contracts/*`

### ourclaw 侧

- `ourclaw/src/runtime/*`
- `ourclaw/src/domain/*`
- `ourclaw/src/commands/*`
- `ourclaw/src/interfaces/*`
- `ourclaw/src/providers/*`
- `ourclaw/src/channels/*`
- `ourclaw/src/tools/*`
- `ourclaw/src/config/*`

## 8. 主线落点总览

| 能力 | 主线落点 | 说明 |
|---|---|---|
| 共享日志 / 校验 / 错误 / 事件 / 任务 / 配置写回 | `framework/` | 跨应用共享，无 claw 业务语义 |
| AppContext 共享装配与统一 dispatcher | `framework/` | 共享运行时主干 |
| provider / channel / tool / memory / agent / gateway / stream / service | `ourclaw/` | 带 claw 业务语义 |
| 业务级 runtime host / daemon / session / stream projection | `ourclaw/` | 面向业务域与运行时行为 |
