# ourclaw 文档

> 入口说明（2026-03-13）：如果目标是继续推进“基于 `framework` 完成 `ourclaw` 主线开发”，当前优先执行入口请使用：
>
> - `ourclaw/docs/specs/framework-based-ourclaw/requirements.md`
> - `ourclaw/docs/specs/framework-based-ourclaw/design.md`
> - `ourclaw/docs/specs/framework-based-ourclaw/tasks.md`
>
> `architecture/` 与 `planning/` 目录仍保留重要历史分析与阶段记录，但其中部分状态描述可能滞后于当前代码；后续大模型执行时，应优先以新 spec 为主，以旧文档为背景参考。

## 当前文档

- `ourclaw/docs/architecture/overall-design.md`：总体架构、模块边界、日志/校验/配置/运行时设计
- `ourclaw/docs/architecture/logging.md`：统一日志中心、sink、trace 集成和脱敏设计
- `ourclaw/docs/architecture/validation.md`：统一校验模型、字段注册表、风险确认和安全规则设计
- `ourclaw/docs/architecture/runtime-pipeline.md`：统一运行时、dispatch pipeline、任务与事件模型设计
- `ourclaw/docs/architecture/agent-runtime.md`：完整业务版 agent runtime、session、stream、tool orchestration 设计
- `ourclaw/docs/architecture/adapters.md`：CLI、bridge、HTTP、service/manager 入口适配层设计
- `ourclaw/docs/architecture/provider-channel-tool.md`：provider/channel/tool registry 与 runtime 设计
- `ourclaw/docs/architecture/config-runtime.md`：配置运行时、field registry、write pipeline、migration 设计
- `ourclaw/docs/architecture/manager-reuse.md`：future `ourclaw-manager` 与 `ourclaw` 的复用边界和分层设计
- `ourclaw/docs/contracts/error-model.md`：统一错误结构、错误码分层和错误映射约定
- `ourclaw/docs/contracts/log-record.md`：统一日志记录结构与 JSONL 投影契约
- `ourclaw/docs/contracts/command-envelope.md`：统一请求/响应/任务接受信封契约
- `ourclaw/docs/contracts/config-field-registry.md`：配置字段注册表元数据与写回约束契约
- `ourclaw/docs/contracts/runtime-event.md`：运行时事件主题、payload 与订阅语义契约
- `ourclaw/docs/contracts/task-state.md`：异步任务状态、迁移规则与查询契约
- `ourclaw/docs/planning/implementation-epics.md`：建议的实施阶段、Epic 拆分和验收重点
- `ourclaw/docs/planning/llm-task-breakdown.md`：面向大模型执行的任务拆分建议
- `ourclaw/docs/planning/session-resume.md`：会话中断后的续接记录、当前阶段判断和最近阻塞点
- `ourclaw/docs/planning/nullclaw-gap-analysis.md`：`nullclaw` 能力盘点、`ourclaw` 差距矩阵和面向大模型的 gap task 清单
- `ourclaw/docs/planning/full-business-gap-tasks.md`：面向完整业务版的 FB 任务清单与建议执行顺序
- `ourclaw/docs/planning/restart-handoff.md`：IDE / 会话重启后给大模型快速恢复上下文的超短续做指引

## 当前业务层进展

- `ourclaw` 已不再只是空骨架；当前已经落地最小业务层、运行时装配和入口适配
- 已有最小命令：`app.meta`、`config.get`、`config.set`、`logs.recent`
- 这 4 个命令现在已进入第一阶段“更完整业务版”：`app.meta` 已补 build/runtime/capabilities/health，`config.get` 已补批量/元数据/来源说明，`config.set` 已补 preview/diff/write summary，`logs.recent` 已补过滤能力
- 已有最小入口：CLI / bridge / HTTP adapter，统一接到 `AppContext + dispatcher`
- `agent.stream`、`task.get`、`task.by_request` 已落地，bridge / HTTP 也已开始使用更稳定的 envelope 协议与状态码映射
- `agent.stream` 现已带 `subscriptionId` 和事件批次返回，开始接近持续订阅式流协议
- HTTP adapter 已补 `/v1/agent/stream/sse`，且 gateway listener 路径现在可按事件增量 flush `meta` / `stream event` / `result` / `done`
- bridge adapter 已补第一版 `agent.stream` NDJSON 持续投影，开始具备 GUI/manager 可消费的结构化流式事件面
- gateway listener 已补 `/v1/agent/stream/ws` 第一版 WebSocket 投影，可把同一批结构化流式事件改用 text frame 连续输出
- CLI 已补 `agent.stream --live`，可持续打印 NDJSON 事件，并带最小 `cancel/backpressure` 控制参数
- `diagnostics.summary`、`diagnostics.doctor`、`events.poll` 已落地，开始形成 diagnostics / event query 命令面
- `events.subscribe`、`metrics.summary`、`observer.recent` 已落地，event bus / observer / metrics 查询面第一版已可用
- `service.status`、`service.install`、`service.start`、`service.stop`、`service.restart`、`gateway.status`、`gateway.start`、`gateway.stop`、`gateway.stream_subscribe` 已落地第一版 host/service 命令面
- `skills.list`、`skills.install`、`skills.run`、`cron.list`、`cron.register`、`cron.tick`、`heartbeat.status`、`tunnel.status`、`tunnel.activate`、`tunnel.deactivate`、`mcp.list`、`mcp.register`、`hardware.list`、`hardware.register`、`peripheral.register` 已落地第一版命令面
- `skills.run` 与 `cron.tick` 已开始执行真实动作，不再只是静态查询/注册包装
- 已有最小业务支撑：config field registry、security policy、provider/channel/tool registry、session state、stream output、tool orchestrator
- 已有最小 memory runtime，并已接入 agent 主链路
- memory runtime 已继续补 `summary`、`compaction`、`retrieval`，并已开始接入简单 embeddings 与 migration preview/migrate 第一版
- 已有第一版 gateway/runtime host、service/daemon、skills/skillforge、cron/heartbeat、tunnel/mcp、peripherals/hardware 骨架
- 这批 runtime/domain 骨架已进入第二轮：开始具备 lifecycle、调度、状态计数与最小操作能力
- 当前这些能力仍然大多属于“更完整的第一版”，不是最终完整版；下一步重点应放在真实 host/service、真实 embeddings/migration、以及各业务域后端集成
- diagnostics / event query 命令域第一版已落地，可查询 runtime、task、event 基本状态
- adapter 仍是最小版，但第一批命令域已经从“最小可用版”推进到“更完整业务版”的第一阶段；继续推进应优先补更完整 WebSocket/CLI 控制语义、真实 provider/tool 业务与更细的入口协议
- 当前流式入口已覆盖 SSE / WebSocket / bridge NDJSON / CLI live 第一版，但仍缺更完整 cancel、backpressure、client disconnect 与双向控制语义
- 当前已新增第一版真实 OpenAI-compatible provider、file/shell/http 工具，以及最小 `agent.run` 主循环
- 当前还已补 provider health/model listing/streaming、tool schema/security/error mapping，以及 provider -> tool -> provider 多步 loop 第一版

## 建议后续补充

- `ourclaw/docs/contracts/runtime-event.md`
- `ourclaw/docs/contracts/task-state.md`
- `ourclaw/docs/contracts/logging-config.md`

## 说明

当前文档来自对 `nullclaw-manager`、`nullclaw`、`openclaw` 的对比分析，目的是为后续详细设计和任务拆分提供统一基线。
