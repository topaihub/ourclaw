# ourclaw 当前进度与续接记录

> 使用说明（2026-03-13）：本文件继续保留为“阶段进度 / 续接记录”入口，但如果目标是继续推进当前主线开发，请优先参考：
>
> - `ourclaw/docs/specs/reference-aligned-ourclaw/requirements.md`
> - `ourclaw/docs/specs/reference-aligned-ourclaw/design.md`
> - `ourclaw/docs/specs/reference-aligned-ourclaw/tasks.md`
>
> 本文档更适合回答“之前做到哪了”，不再作为唯一的开发任务入口。
>
> 说明（2026-03-16）：phase-1 baseline 已迁移到 backup：
>
> - `ourclaw/docs/backup/framework-based-ourclaw/requirements.md`
> - `ourclaw/docs/backup/framework-based-ourclaw/design.md`
> - `ourclaw/docs/backup/framework-based-ourclaw/tasks.md`
> - `ourclaw/docs/backup/framework-based-ourclaw/next-stage-backlog.md`
> - `ourclaw/docs/specs/framework-based-ourclaw/archive/completed-mainline-tasks-2026-03-16.md`

本文档用于在会话中断时快速恢复上下文。

如果你现在是要给新会话快速续接，请优先看：`ourclaw/docs/specs/reference-aligned-ourclaw/requirements.md`、`ourclaw/docs/specs/reference-aligned-ourclaw/design.md`、`ourclaw/docs/specs/reference-aligned-ourclaw/tasks.md`、`docs/planning/current-task-board.md`

后续如果有新的设计判断、任务拆分、阶段结论或阻塞分析，应优先更新本文档或同目录对应专题文档，而不是只留在对话上下文里。

当前 live 执行任务清单统一维护在根级 `docs/planning/current-task-board.md`；本文档继续负责记录阶段结论、设计判断与续做说明。

## 最后更新

- 日期：2026-03-12
- 状态：已推进到 ourclaw 最小业务层、命令域与入口适配第一版落地阶段，`FB-19`、`FB-05`、`FB-06`、`FB-07`、`FB-08`、`FB-16`、`FB-18`、`FB-11`、`FB-12` 的当前顺序收口已完成
- **本次更新 (2026-03-12)**：已完成 TASK-022 收口，ourclaw-manager host / bridge / services 最小闭环已落地并通过验证

## 最近结论

- **C1 已完成（2026-03-16）**：
  - `gateway.status` / `start` / `stop` / `reload` / `stream_subscribe` 已统一到同一份 gateway snapshot contract
  - `/health` 与 `/ready` 已改为真实 gateway 状态投影
  - `http_adapter.zig` 已补 gateway control-plane route smoke
  - 验证：`ourclaw` 执行 `zig build test --summary all -j1` 通过（177/177）

- **B3 已完成（2026-03-16）**：
  - summary-first prompt compression 已完成
  - `max_tool_rounds`、`allow_provider_tools`、`prompt_profile`、`response_mode` 已从 command/runtime 进入 `session.get`
  - `prompt_assembly` 已新增 `Execution Strategy JSON`，让 provider prompt 显式携带 execution strategy
  - 验证：`ourclaw` 执行 `zig build test --summary all -j1` 通过（175/175）

- **B3 第四子步已完成（2026-03-16）**：
  - `prompt_assembly` 已新增 `Execution Strategy JSON` system message
  - `agent_runtime` 已把 budgets / `max_tool_rounds` / `allow_provider_tools` / `prompt_profile` / `response_mode` 传入 prompt 组装
  - `openai_compatible` probe 已要求 execution strategy message 存在，既有 smoke 因而自动覆盖这条 prompt surface

- **B3 第三子步已完成（2026-03-16）**：
  - `agent.run` / `agent.stream` 已显式接收 `allow_provider_tools / prompt_profile / response_mode`
  - `session.turn.completed` 已写出 `allowProviderTools / promptProfile / responseMode`
  - `session.get` 顶层、`latestTurn` 与 `recentTurns` 已对外暴露这组策略面
  - 验证：`ourclaw` 执行 `zig build test --summary all -j1` 通过（175/175）

- **B3 第二子步已完成（2026-03-16）**：
  - `agent.run` / `agent.stream` 已显式接收 `max_tool_rounds`
  - `session.turn.completed` 已写出 `maxToolRounds`
  - `session.get` 的 `latestTurn` / `recentTurns` 已对外暴露 `maxToolRounds`
  - 验证：`ourclaw` 执行 `zig build test --summary all -j1` 通过（175/175）

- **B2 最后一小刀已完成（2026-03-16）**：
  - `memory.snapshot_import` 对显式 `embeddingProvider:null` / `embeddingModel:null` 已改为真正清空，不再被默认 embedding 配置污染
  - `memory_runtime.zig` domain test 与 `tests/smoke.zig` 已补手写 snapshot richer metadata 回归

- **B2 已完成（2026-03-16）**：
  - `memory_runtime.exportSnapshotJson()` / `importSnapshotJson()` 已稳定保留 `tsUnixMs / embeddingProvider / embeddingModel`
  - `memory_runtime.zig` 已有 richer metadata roundtrip domain test，`tests/smoke.zig` 也已覆盖 export/import roundtrip 与 retrieval metadata 输出
  - 结论：B2 当前无需继续补 richer metadata 保真代码，可转入后续 wave

- **B1 已完成（2026-03-16）**：
  - `session_state.snapshotMeta()` 已提供 ledger header、最新 turn 元数据、累计 `prompt/completion/total tokens`
  - `session_state.recentTurns()` 已补最近 completed turns 的结构化提取
  - `session.get` 已补 `usage`、`recentTurns` 与 `recovery.executionCursor`，不再只暴露 `latestTurn`
  - 验证：`ourclaw` 执行 `zig build test --summary all -j1` 通过（174/174）

- **B1 第三子步已完成（2026-03-16）**：
  - `session.turn.completed` 中已有的 `promptTokens / completionTokens / totalTokens` 现已在 `session_state.snapshotMeta()` 中做累计聚合
  - `session.get` 已新增 `usage` 结构化块，开始稳定输出 session 级累计 token 视图，而不再只暴露最近一次 turn 的 token 值
  - `session_state.zig` 已补累计 usage domain test，`tests/smoke.zig` 已补双次 `agent.run` 后的累计 usage 回归
  - 验证：`ourclaw` 执行 `zig build test --summary all -j1` 通过（173/173）

- **B3 第一子步已完成（2026-03-16）**：
  - `session.compact` 产出的 compacted summary 不再只是落在 `session.summary` / `session.get` 中，而是已真正接入 `agent_runtime -> prompt_assembly` 主链路
  - `memory_runtime.recallForTurn()` 现会把 `compacted_summary_text` 与 recent raw recall 分离；prompt 注入顺序变为 `Compacted Session Summary` 在前、`Recent Memory Recall` 在后
  - `prompt_assembly.zig`、`agent_runtime.zig`、`providers/openai_compatible.zig` 与 `tests/smoke.zig` 已补 summary-first 回归
  - 验证：`ourclaw` 执行 `zig build test --summary all -j1` 通过（172/172）

- **TASK-001 收口完成**：
  - 明确了 replay-only、resume、continue 三种模式的语义边界
  - replay-only：仅回放历史事件，不启动新执行
  - resume：恢复仍在 running 状态的执行
  - continue：启动新执行或继续已 terminal 的执行
  - 已在 SSE、WebSocket、Bridge 三个适配器中实现执行状态检查，避免重复执行
  - 添加了 `StreamRegistry.findRunningBySession()` 方法来查找正在运行的执行
  - Meta 响应现在始终包含 `execution_id`，客户端可以追踪执行上下文

- **TASK-002 收口完成**：
  - 修复了 `stream_projection.zig` 的 compile drift（`buildMetaJson` 签名对齐 + 无效块标签清理）
  - `stream_websocket.zig` 已新增 `writeCloseFrameWithReason` 与 close payload 解析能力
  - `gateway_host.zig` 已把 client close raw code/reason 透传到 callback 边界
  - `http_adapter.zig` 已改为严格小型控制解析器，支持 `ack/pause/resume/cancel` 与 legacy plain `cancel`
  - `stream_projection.zig` 已接入 WS 控制原子信号并保持 `control.pause` / `control.resume` / `control.close` 事件语义
  - 终态映射仍保持 runtime 归一为 `client_disconnect`，同时保留 gateway 边界 raw close 细节
  - 已通过聚焦测试与 `zig build test` 验证

- **TASK-004 收口完成**：
  - `framework/src/config/` 已新增共享 `parser.zig`、`defaults.zig`、`loader.zig`
  - `ourclaw/src/config/runtime.zig` 已补应用级 bootstrap defaults / loader / parser 装配
  - `config.get` 已改为通过 loader 统一读取 runtime store + bootstrap defaults，并保留原有 `bootstrap_default / runtime_store / unset` 语义
  - `config.set` 已改为复用共享 parser，避免命令层继续各自维护值解析逻辑
  - `runtime/app_context.zig` 已改为通过配置运行时模块统一做默认值读取与 bootstrap seeding
  - 已通过 `framework` 115/115 与 `ourclaw` 91/91 测试验证

- **TASK-005 收口完成**：
  - `field_registry.zig` 已补 `category`、`display_group`、`default_value_json`、`side_effect_kind`、`allowed_in_sources` 元数据
  - 配置字段覆盖面已扩到 logging rotation、provider base_url/model、Anthropic API key、runtime limit、service autostart 等首批 manager 相关字段
  - `config.get` / `config.set` 现在会稳定输出新增元数据，供后续 manager 配置编辑直接消费
  - 已通过 `framework` 116/116 与 `ourclaw` 91/91 测试验证

- **TASK-006 收口完成**：
  - `ourclaw/src/config/migration.zig` 已补 preview / prepare / apply 第一版迁移链路，并支持 legacy path alias rewrite
  - `ourclaw/src/compat/config_import.zig` 已补 `generic / nullclaw / openclaw` source kind 包装的 compatibility import 第一版
  - 已新增 `config.migrate_preview`、`config.migrate_apply`、`config.compat_import` 三条命令，并接入 HTTP route 与 CLI 入口
  - 已通过 `framework` 116/116 与 `ourclaw` 96/96 测试验证

- **TASK-007 收口完成**：
  - `ourclaw/src/runtime/config_runtime_hooks.zig` 已补真实 config side effect / post-write hook 第一版
  - `config.set` / migration apply / compat import 已切到 ourclaw runtime config pipeline，不再只用 framework 记录型 sink
  - `logging.level` 变更会立即更新 `logger.min_level`
  - `providers.*` 变更会真正推进 provider refresh state
  - 真实写回会推进 heartbeat，并记录 post-write summary
  - 已通过 `framework` 116/116 与 `ourclaw` 98/98 测试验证

- **TASK-008 收口完成**：
  - `ourclaw/src/domain/prompt_assembly.zig` 已新增统一 prompt assembly 第一版
  - agent runtime 现在会显式注入 system prompt、tools prompt、memory recall 与 tool result，而不是只发送单条 user prompt
  - `mock://openai/chat` 已补 prompt assembly probe，验证 provider 请求中确实存在 system/tools 注入
  - 已通过 `framework` 116/116 与 `ourclaw` 100/100 测试验证

- **TASK-009 收口完成**：
  - `session_state.zig` 已补 `SessionSnapshot` 与 `snapshotMeta()`
  - 已新增 `session.get`、`session.compact` 两条命令，并接入 HTTP/CLI 入口
  - `session.compact` 会把 memory summary 同步回 session event，`session.get` 可联合返回 event/memory/summary 视图
  - 已通过 `framework` 116/116 与 `ourclaw` 102/102 测试验证

- **TASK-010 收口完成**：
  - `channels/root.zig` 已新增 `CliChannelRuntime` 与 `CliChannelSnapshot`
  - `cli_adapter` 现在会把 CLI 请求与 live stream 使用情况记录到 channel runtime
  - CLI channel 已具备最小真实收发/状态语义
  - 已通过 `framework` 116/116 与 `ourclaw` 104/104 测试验证

- **TASK-011 收口完成**：
  - `channels/root.zig` 已补 bridge / HTTP edge channel runtime snapshot 与状态记录
  - `bridge_adapter`、`http_adapter` 现在会把请求与流式使用情况记录到 channel runtime
  - bridge / HTTP 已具备最小真实 channel/runtime 语义
  - 已通过 `framework` 116/116 与 `ourclaw` 105/105 测试验证

- **TASK-012 收口完成**：
  - 已新增 `memory.snapshot_export`、`memory.migrate_apply` 两条命令
  - memory 现在除了 `summary / retrieve / migrate_preview` 之外，也具备 `snapshot export / migrate apply` 第一版
  - 已通过 `framework` 116/116 与 `ourclaw` 106/106 测试验证

- **TASK-013 收口完成**：
  - tools prompt 已升级为结构化 JSON，带上 requiredAuthority / riskLevel / parameters
  - provider `supports_tools` 现在会真实影响 prompt 注入与 `enable_tools`
  - tool 调用 started/denied/failed 事件现在会带 toolId、authority、risk 等元数据
  - 已通过 `framework` 116/116 与 `ourclaw` 106/106 测试验证

- **TASK-014 收口完成**：
  - skills / cron / tunnel / mcp / hardware 相关命令现在会返回更真实的操作状态与时间戳
  - `skills.run`、`cron.list`、`tunnel.status`、`mcp.list`、`hardware.list` 都已具备最小可观察状态
  - 已通过 `framework` 116/116 与 `ourclaw` 107/107 测试验证

- **TASK-015 收口完成**：
  - `gateway.start / gateway.stop` 现在统一走 `runtime_host`
  - `gateway.status / service.status` 现在会暴露 `handlerAttached / hostRunning / hostLoopActive / gatewayRunning` 等托管状态
  - `runtime_host.status()` 已把 gateway 托管状态并入输出
  - 已通过 `framework` 116/116 与 `ourclaw` 107/107 测试验证

- **TASK-016 收口完成**：
  - `service_manager` 已补 `stop_count` 与更稳定的 start/stop 语义
  - `daemon.status` 与 `service.*` 命令现在会带更完整的 lifecycle 计数
  - 已通过 `framework` 116/116 与 `ourclaw` 107/107 测试验证

- **TASK-017 收口完成**：
  - `metrics.summary`、`observer.recent`、`events.subscribe`、`events.poll`、`diagnostics.summary` 已补更稳定的查询字段
  - 查询面现在会带 observer 计数、subscriptionCount、eventCount、runtimeHost/service 关键信号
  - 已通过 `framework` 116/116 与 `ourclaw` 107/107 测试验证

- **TASK-018 收口完成**：
  - 已新增根级 `docs/planning/manager-prerequisite-contract-checklist.md`
  - 已新增 `ourclaw-manager/docs/planning/runtime-contract-entry.md`
  - 已明确 manager MVP 优先依赖的 stable / provisional 契约面

- **TASK-019 收口完成**：
  - 已新增 `ourclaw-manager/docs/planning/manager-mvp-plan.md`
  - 已明确 manager 的产品边界、技术边界、MVP 范围、模块拆分与 runtime_client/view_models/host/bridge 实施顺序

- **TASK-020 收口完成**：
  - `ourclaw-manager/src/runtime_client/` 已从 scaffold 升级为 foundation 阶段
  - 已新增统一 invoker / request / result 模型，以及 config/status/diagnostics/events/memory 五个分域 client
  - 已通过 `ourclaw-manager` 10/10、`ourclaw` 107/107、`framework` 116/116 测试验证

- **TASK-021 收口完成**：
  - 已新增 `config_view_model.zig`、`status_view_model.zig`、`diagnostics_view_model.zig`、`logs_view_model.zig`
  - view_models 已从 scaffold 升级为 foundation 阶段，并具备 UI 友好的加载/错误/聚合输出基础结构
  - 已通过 `ourclaw-manager` 11/11、`ourclaw` 107/107、`framework` 116/116 测试验证

- **TASK-022 收口完成**：
  - `ourclaw-manager/src/host/` 已补最小 `ManagerHost` 装配 runtime_client 与 services
  - `ourclaw-manager/src/services/` 已补 config/status/diagnostics/logs 四类 service，并可产出对应 view model
  - `ourclaw-manager/src/bridge/` 已补最小 `ManagerBridge`，可直接暴露 host-backed 的 view model 加载入口
  - 已通过 `ourclaw-manager` 12/12、`ourclaw` 107/107、`framework` 116/116 测试验证

- **TASK-003 收口完成**：
  - `ProjectionPolicy` 已新增显式 text-delta 策略字段：`text_delta_coalesce_event_limit`、`text_delta_coalesce_byte_limit`、`text_delta_throttle_window_ms`
  - `stream_projection.resolvePolicy(...)` 已支持从 request params 解析上述字段，不再依赖局部硬编码常量
  - `writeBridgeAgentStream(...)` 已从 direct projector + `runStream` 切到 execution drain loop，bridge/CLI live 现可与 SSE/WebSocket 一样按时间窗口执行 pending text flush
  - 已新增测试覆盖 policy 解析与 bridge 时间窗口行为差异（默认窗口 vs `text_delta_throttle_window_ms=0`）
  - 已通过 `zig build test --summary all`（`ourclaw/`，90/90）验证

- 工作区已经明确分成两部分：参考仓库 `nullclaw/`、`openclaw/`、`nullclaw-manager/`，以及新主线 `framework/`、`ourclaw/`、`ourclaw-manager/`。
- 当前主线目标不是直接堆 `ourclaw` 业务，而是先沉淀可复用 `framework`，再让 `ourclaw` 和未来 `ourclaw-manager` 共享这套基础能力。
- `ourclaw/docs/` 下的架构、契约和任务拆分文档已经形成可继续推进的基线。
- 已补一版 `nullclaw` 对照分析，见 `ourclaw/docs/planning/nullclaw-gap-analysis.md`，后续可直接拿来指导大模型持续推进 gap 任务。
- 已补完整业务版设计包第一批文档，包括 `agent-runtime.md`、`adapters.md`、`provider-channel-tool.md`、`config-runtime.md`、`runtime-event.md`、`task-state.md` 与 `full-business-gap-tasks.md`。

## 当前代码状态

### framework

- `build.zig`、`build.zig.zon`、`src/main.zig`、`src/root.zig` 已建立。
- `.fingerprint` 已修正，`zig build test` 可通过。
- `src/core/error.zig` 已落地共享 `AppError`、错误码常量、域前缀判断和基础 helper constructor。
- `src/core/error.zig` 已补齐常见内部错误名到 `AppError` 的统一映射 helper，`dispatcher` 后续可直接复用。
- `src/contracts/envelope.zig` 已落地共享 `Envelope<T>`、`EnvelopeMeta`、`TaskAccepted`。
- `src/core/logging/` 已落地第一阶段共享日志主干：`LogLevel`、`LogField`、`LogRecord`、`LogSink`、`MemorySink`、`Logger`。
- `src/core/logging/` 已继续补齐 `ConsoleSink`、`JsonlFileSink`、`MultiSink`、`RedactMode`，并已把字段级脱敏接到 `Logger` 写入链路。
- `src/core/logging/logger.zig` 已补 trace 上下文自动注入接口，可自动带入 `trace_id`、`span_id`、`request_id`。
- `src/core/validation/` 已落地 `ValidationIssue`、`ValidationReport`，并在 `src/core/error.zig` 补上 `fromValidationReport(...)`。
- `src/core/validation/` 已继续补齐 `rule.zig`、`rules_basic.zig`、`rules_security.zig`、`validator.zig`，当前支持 request/config 模式、required 检查、unknown field 严格拒绝、类型检查、基础 object/array/schema 校验、security rule 与 risk confirmation 基础流程。
- `src/core/validation/rules_config.zig` 已补齐第一批配置交叉字段规则，当前可表达依赖字段必填与风险确认类规则。
- `src/core/validation/issue.zig` 已补 `details_json`，schema 校验和部分规则会带结构化 details。
- `src/app/command_types.zig`、`src/app/command_context.zig`、`src/app/command_registry.zig` 已落地，形成共享请求/权限/命令元数据骨架。
- `src/app/command_dispatcher.zig` 已继续推进到支持 authority 校验、同步 handler dispatch、async handler 提交、observer/event bus 事件发射的骨架。
- `src/runtime/task_runner.zig` 已落地最小内存任务提交器，可返回 `task_id` 与 `queued` 状态。
- `src/config/store.zig` 已落地 `ConfigStore` / `MemoryConfigStore`，`src/config/pipeline.zig` 已可执行校验后真实写回。
- `src/runtime/task_runner.zig` 已继续补齐状态流转与查询接口，可标记 `running` / `succeeded` / `failed` / `cancelled` 并查询快照。
- `src/core/validation/validator.zig` 已继续细化，当前支持 primitive array element rules、对象数组 schema 推断和更完整 nested details。
- `src/runtime/event_bus.zig`、`src/observability/observer.zig`、`src/observability/multi_observer.zig` 已落地，dispatcher/config write/task state 现在都可发事件。
- `src/runtime/task_runner.zig` 已支持真正异步 job 执行与 `result_json` 回写。
- `src/observability/log_observer.zig`、`src/observability/file_observer.zig`、`src/observability/metrics.zig` 已落地，observer 层已有 log/file/metrics 三类最小实现。
- `src/runtime/event_bus.zig` 已补订阅治理与 subscription cursor 轮询语义。
- `src/config/store.zig` / `src/config/pipeline.zig` 已补更细 diff 元数据（如 `kind`、`sensitive`、`value_kind`）以及 side effect hook。
- `src/runtime/app_context.zig` 已落地，可统一装配 logger、observer、event bus、task runner、command registry、config store 等核心依赖。
- `src/observability/metrics.zig` 已继续细化，请求/任务时长、队列深度、活动任务数、config changed fields、side effect/post-write hook 次数等指标已接入。
- `src/config/pipeline.zig` 已继续补 post-write hook，配置写回现在有 side effect 分类与 post-write summary。
- `AppContext.makeDispatcher(...)`、`AppContext.makeConfigPipeline(...)` 已可直接为后续入口层和命令域提供装配好的运行时主干。
- `src/providers/openai_compatible.zig` 已落地第一版真实 OpenAI-compatible provider runtime，并已接入 provider registry。
- `src/providers/root.zig` 已继续补 provider health、model listing、streaming 接口。
- `src/tools/file_read.zig`、`src/tools/shell.zig`、`src/tools/http_request.zig` 已落地第一版真实工具实现，并已接入 tool registry 与 security policy。
- `src/tools/root.zig` 与 `src/domain/tool_orchestrator.zig` 已继续补 tool schema、security、error mapping 与 tool call lifecycle 事件。
- `src/domain/agent_runtime.zig` 与 `src/commands/agent_run.zig` 已落地第一版 agent runtime 主循环，可串起 session、tool、provider、stream output 主链路。
- `src/domain/agent_runtime.zig` 已继续推进到 provider -> tool -> provider 多步 loop 第一版，可处理 provider 触发的工具调用。

### ourclaw

- `build.zig`、`build.zig.zon`、`src/main.zig`、`src/root.zig` 已建立。
- `src/runtime/app_context.zig` 已落地，开始在 `ourclaw` 侧装配共享 `framework` 与业务域依赖。
- `src/config/field_registry.zig` 已落地，提供最小配置字段注册表与配置交叉规则入口。
- `src/security/policy.zig` 已落地，提供最小 secret store 与 authority/security policy 判定。
- `src/providers/root.zig`、`src/channels/root.zig`、`src/tools/root.zig` 已落地最小 registry 骨架，并已注册 builtin stub。
- `src/domain/session_state.zig`、`src/domain/stream_output.zig`、`src/domain/tool_orchestrator.zig`、`src/domain/services.zig` 已落地，开始承载 session、stream output、tool orchestration 和命令层服务容器。
- `src/commands/app_meta.zig`、`src/commands/config_get.zig`、`src/commands/config_set.zig`、`src/commands/logs_recent.zig` 已落地，形成第一批最小业务命令。
- `src/commands/app_meta.zig` 已推进到更完整业务版，当前可输出版本、build、runtime、capabilities、health 摘要。
- `src/commands/config_get.zig` 已推进到更完整业务版，当前支持批量读取、字段元数据和来源说明。
- `src/commands/config_set.zig` 已推进到更完整业务版，当前支持 preview、risk confirm、diff 详情与 write summary。
- `src/commands/logs_recent.zig` 已推进到更完整业务版，当前支持 level/subsystem/trace 过滤。
- `src/commands/agent_stream.zig`、`src/commands/task_get.zig`、`src/commands/task_by_request.zig` 已落地，`agent.stream` 现已按本轮新增事件切片返回流式事件快照，任务查询命令域也已可用。
- `src/commands/diagnostics_summary.zig`、`src/commands/diagnostics_doctor.zig`、`src/commands/events_poll.zig` 已落地，diagnostics 与事件轮询命令域第一版已可用。
- `src/commands/events_subscribe.zig`、`src/commands/metrics_summary.zig`、`src/commands/observer_recent.zig` 已落地，event bus / observer / metrics 查询面第一版已可用。
- `src/commands/service_status.zig`、`src/commands/gateway_status.zig` 已落地，开始暴露 gateway / runtime host / service 状态查询面。
- `src/commands/service_install.zig`、`src/commands/service_start.zig`、`src/commands/service_stop.zig`、`src/commands/service_restart.zig`、`src/commands/gateway_start.zig`、`src/commands/gateway_stop.zig`、`src/commands/gateway_stream_subscribe.zig` 已落地，开始补 gateway / service 真实控制命令。
- `src/commands/skills_list.zig`、`src/commands/skills_install.zig`、`src/commands/skills_run.zig`、`src/commands/cron_list.zig`、`src/commands/cron_register.zig`、`src/commands/cron_tick.zig`、`src/commands/heartbeat_status.zig`、`src/commands/tunnel_status.zig`、`src/commands/tunnel_activate.zig`、`src/commands/tunnel_deactivate.zig`、`src/commands/mcp_list.zig`、`src/commands/mcp_register.zig`、`src/commands/hardware_list.zig`、`src/commands/hardware_register.zig`、`src/commands/peripheral_register.zig` 已落地，开始暴露 skills / cron / heartbeat / tunnel / mcp / hardware 第一版控制与查询面。
- `skills.run` 已从单纯返回 entry command 推进到真正 dispatch skill 对应命令；`cron.tick` 已开始实际调度 cron job 对应命令。
- `service.status`、`gateway.status` 已补更多运行时细节（计数、状态、生命周期字段），第二轮收口已开始。
- `service` / `gateway` 当前已经从只读状态面推进到可控制生命周期的第一版；但仍缺真正对外监听的 host、OS service 安装与后台运行模型。
- `skills` / `cron` / `tunnel` / `mcp` / `hardware` / `peripheral` 当前已经从 list/register stub 推进到最小可操作版；但仍缺真实业务后端与外部集成。
- `src/interfaces/cli_adapter.zig`、`src/interfaces/bridge_adapter.zig`、`src/interfaces/http_adapter.zig` 已落地，开始把三类入口接到 `AppContext + dispatcher`。
- `src/interfaces/bridge_adapter.zig`、`src/interfaces/http_adapter.zig` 已继续细化到更稳定的 envelope 协议与 HTTP 状态码映射。
- `src/interfaces/http_adapter.zig` 已继续补 `/v1/agent/stream/sse` 的真正增量 flush 路径；`src/runtime/gateway_host.zig` / `src/runtime/app_context.zig` 已补 streaming body 与 `content-type` 透传，gateway 现在可以按事件向外写出 `text/event-stream`。
- `src/interfaces/http_adapter.zig` / `src/interfaces/stream_websocket.zig` 也已补第一版 `/v1/agent/stream/ws` WebSocket 投影，可把同一批结构化事件按 text frame 连续推送给外部客户端。
- `src/interfaces/bridge_adapter.zig` 已补第一版 `agent.stream` NDJSON 持续投影；`src/interfaces/cli_adapter.zig` 也已补 `agent.stream --live`，CLI 现在可以持续打印结构化事件。
- 当前流式投影层已加最小 `cancel_after_events` / `max_total_bytes` / `max_event_bytes` 控制，开始形成第一版 cancel/backpressure 语义。
- `src/interfaces/stream_projection.zig` 已继续补 request 级流控参数解析，SSE / WebSocket / bridge 现在都可直接消费 `cancel_after_events` / `max_total_bytes` / `max_event_bytes`。
- 流式终态现在会补 `terminalCode`、`terminalReason`、`emittedEvents`、`emittedBytes`；policy cancel/backpressure 可稳定回传终止原因，broken pipe / connection reset 也会归一成 `StreamClientDisconnected` 并停止继续回写。
- `src/domain/agent_runtime.zig` 已补流式异常路径上的 tool result / tool id 回收，避免取消或断连时泄漏临时分配。
- `src/interfaces/stream_websocket.zig`、`src/runtime/gateway_host.zig`、`src/interfaces/http_adapter.zig` 已继续补客户端入站控制链路：gateway 现在会读取 WebSocket client text / close frame，并把 `cancel` 控制消息映射成流式 cancel，把 close/disconnect 映射成 client closed signal。
- `src/interfaces/stream_projection.zig` 已补第一版 SSE `Last-Event-ID` replay-only 语义：可按 session 回放指定 seq 之后的 `stream.output` 事件，并以 replay-only 模式安全结束，避免断线重连时重复执行同一轮 agent run。
- `src/interfaces/stream_projection.zig` 也已补 `text.delta` coalescing，当前会把连续 delta 合并后再输出，以降低 flush 次数和小包压力。
- `src/main.zig` 已不再只是 bootstrap 文本输出，而是开始走最小 CLI adapter 调度。
- `src/domain/memory_runtime.zig` 已落地最小 memory runtime，并已接入 agent 主链路的 recall / append / tool-result writeback。
- `src/domain/memory_runtime.zig` 已继续补 `summary`、`compaction`、`retrieval`，并开始为长期上下文系统提供基础能力；现在已经有简单 embeddings 与 migration preview/migrate 第一版。
- `src/domain/skills.zig`、`src/domain/skillforge.zig`、`src/domain/tunnel_runtime.zig`、`src/domain/mcp_runtime.zig`、`src/domain/peripherals.zig`、`src/domain/hardware.zig` 已落地第一版业务骨架。
- `src/runtime/heartbeat.zig`、`src/runtime/cron.zig`、`src/runtime/gateway_host.zig`、`src/runtime/runtime_host.zig`、`src/runtime/service_manager.zig`、`src/runtime/daemon.zig` 已落地第一版运行时骨架。
- `gateway_host`、`runtime_host`、`service_manager`、`daemon` 现在已不只是静态骨架，开始具备可变更状态、生命周期计数和更完整 status 输出。
- `skills`、`cron`、`tunnel`、`mcp`、`peripherals`、`hardware` 现在已不只是 list/register stub，开始具备最小操作行为与命令面。
- 设计文档已经落盘，包括 `docs/architecture/`、`docs/contracts/`、`docs/planning/`。
- 已验证 `zig build test` 可以通过。
- `tests/smoke.zig` 已补齐，`build.zig` 也已挂上独立 smoke test 入口，因此 Epic 01 / TASK-03 已收口。
- 由于横切基础能力已迁移到共享层，Epic 02 的 `AppError` 与 `Envelope` 首批实现实际落在 `framework/`，而不是 `ourclaw/src/core/`。
- 目前这批命令和 adapter 已达到“最小可用版”，但还不是完整业务版：输出协议、错误投影、bridge/http 细节、provider/tool 实际业务行为都还需要继续补齐。

### ourclaw-manager

- `build.zig`、`build.zig.zon`、`src/main.zig`、`src/root.zig` 已建立。
- `src/host/`、`src/bridge/`、`src/runtime_client/`、`src/services/`、`src/view_models/` 目前都还是 scaffold 导出。
- `.fingerprint` 已修正，`zig build test` 可通过。
- 仍处于 manager 骨架阶段。

## 当前阻塞与验证记录

- `framework`、`ourclaw`、`ourclaw-manager` 三个主线目录现在都已验证 `zig build test` 通过。
- `framework/` 和 `ourclaw/` 下仍存在 `tmp.zig`、`out.log`、`err.log` 一类临时验证文件，说明之前做过临时试跑，但这些文件不属于主线设计产出。
- `ourclaw/docs/planning/implementation-epics.md` 与 `ourclaw/docs/planning/llm-task-breakdown.md` 中，旧的 `ourclaw/src/core/*` 路径应按当前架构理解为共享 `framework/src/*` 落点。

## 当前判断

- 如果按当前共享架构看，TASK-01、TASK-02、TASK-03 已完成。
- Epic 02 的首批工作也已完成：共享 `AppError` 与 `Envelope` 已先落到 `framework`。
- Epic 02 的错误映射 helper 已补齐，Epic 03 的日志主干第一批核心文件也已落地。
- 当前等价于 TASK-07、TASK-08、TASK-09、TASK-10、TASK-11 已完成，TASK-12 的脱敏和 trace 注入接口也已补齐。
- Epic 04 的 TASK-13 已完成，且 `fromValidationReport(...)` 已提前补到共享错误模型中。
- Epic 04 的 `rules_basic.zig`、`rules_security.zig` 与 `validator.zig` 基础版已落地，并且已经开始接入最小 dispatcher/config validation pipeline。
- `rules_config.zig` 也已落地，当前更接近“同步 dispatcher + config validation pipeline 骨架已成立”。
- `authority`、`command registry`、`sync dispatch` 与 `async task accept` 骨架也已落地。
- `config store` 写回链路与 `task state` 查询骨架也已落地。
- `observer/event bus` 接线与真正 async 执行链路第一版也已落地。
- observer 的 log/file/metrics 第一版也已落地，event bus 订阅治理第一版也已落地。
- `AppContext`、metrics 深化、config post-write hook 第一版也已落地。
- `ourclaw` 侧的 provider/channel/tool registry、最小 CLI/bridge/HTTP adapter、最小业务命令域、session/stream/tool orchestration 第一版现在都已落地。
- 当前共享 runtime 已经足以支撑 `ourclaw` 做一个最小可运行的 agent 应用骨架，用来继续叠 `nullclaw` 风格能力。
- `full-business-gap-tasks.md` 中的 `FB-01`、`FB-02`、`FB-03`、`FB-04` 已完成，最小业务命令第一阶段已收口。
- `full-business-gap-tasks.md` 中的 `FB-09`、`FB-10`、`FB-13`、`FB-14`、`FB-15`、`FB-17` 现已完成。
- `full-business-gap-tasks.md` 中的 `FB-20`、`FB-21`、`FB-22` 也已完成，memory runtime 已进入可继续深化的阶段。
- `full-business-gap-tasks.md` 中的 `FB-26` 现在也已完成；`FB-19` 与 `FB-23` 仍保持 partial。
- `FB-19` 已继续推进：HTTP 侧 `/v1/agent/stream/sse` 现在已能通过 gateway listener 按事件增量 flush `meta` / `stream event` / `result` / `done`；WebSocket、bridge NDJSON、CLI live 也都已有第一版持续投影。
- `FB-19` 本轮已补一版更完整 cancel/backpressure/client disconnect 语义：request 可携带流控参数，终态可回传 cancel/backpressure 元数据，transport 断连可归一感知并停止回写。
- `FB-19` 本轮已继续补 WebSocket fuller control protocol：`ack / pause / resume / close reason` 已收口，HTTP adapter 已支持双向控制消息，gateway callback 已保留 client close frame 的 raw `code/reason`，而 runtime terminal 仍统一归一为 `client_disconnect`。
- `FB-19` 本轮已把时间窗口型 throttle/flush 调度补到 bridge/CLI live；当前仍未收口的主要是“真正恢复同一执行”的 reconnect。
- `FB-05` 本轮已收口第一版：共享 `loader/parser/defaults` 已落地，当前 `config.get` / `config.set` / bootstrap defaults 已不再各自散落维护。
- `FB-06` 本轮已收口第一版：field registry 已具备 manager 可消费的分类、分组、默认值、side effect、来源约束元数据，字段覆盖面也已明显扩大。
- `FB-07` 本轮已收口第一版：配置迁移 preview / apply 与 compatibility import 入口已打通，但还不是完整配置文件迁移体系。
- `FB-08` 本轮已收口第一版：config side effect / post-write hook 已具备最小真实行为，不再只是记录型 sink。
- `FB-16` 本轮已收口第一版：agent runtime 已具备 prompt assembly / system prompt / tools prompt 注入主链路。
- `FB-18` 本轮已收口第一版：session snapshot / compaction / summary 已具备最小可查询闭环。
- `FB-11` 本轮已收口第一版：CLI channel 已具备最小真实 runtime 语义，不再只是 registry 定义。
- `FB-12` 本轮已收口第一版：bridge / HTTP 已具备最小真实 channel/runtime 语义，不再只是 adapter 入口。
- `FB-23` 本轮已继续收口第一版：memory 主路线已经具备 export / preview / apply / retrieve / summary 的最小闭环。
- provider / tool integration 本轮也已继续收口：provider tools 能力约束、结构化 tools prompt、tool 元数据事件都已补齐第一版。
- `FB-28` ~ `FB-31` 本轮已继续深化：skills / cron / tunnel / mcp / hardware 都已具备更真实的最小操作状态。
- `FB-24` 本轮已继续收口：gateway/runtime host 已具备更稳定的托管状态面，不再只是有状态骨架。
- `FB-25` 本轮已继续收口：service/daemon 生命周期语义与状态计数已更稳定。
- `FB-27` 本轮已继续收口：event bus / observer / metrics 查询面对 manager/control plane 更稳定。
- manager 前置契约清单已经落盘，后续 `ourclaw-manager` 可直接据此决定 stable / provisional 依赖面。
- `ourclaw-manager` 的专项规划文档也已落盘，后续实现可直接按 runtime_client → view_models → host/bridge/services 顺序推进。
- `ourclaw-manager` 的 `runtime_client` 第一版已落地，后续 `view_models` 和 `services` 不需要再直接面对 runtime 命令细节。
- `ourclaw-manager` 的最小 view models 也已落地，后续 `host / bridge / services` 可以直接围绕这些 UI 友好模型装配闭环。
- `ourclaw-manager` 的 host / bridge / services 最小闭环也已落地，当前第五批任务已全部收口。
- `FB-24`、`FB-25`、`FB-27`、`FB-28`、`FB-29`、`FB-30`、`FB-31` 当前都已进入 partial：第一版骨架和查询命令已落地，但距离完整业务版仍有明显差距。
- 第二轮收口后，`FB-24/25/27/28/29/30/31` 已从“只有查询面”推进到“有最小控制/执行行为”的阶段，但仍未达到完整业务版。
- 第二轮收口后，`FB-24`~`FB-31` 已从“仅查询面”推进到“带最小操作行为”的阶段，但仍不是完整业务版。
- 仍未完成的是 provider/channel/tool 的真实业务实现、更完整入口协议、会话/流式细节、以及更接近生产级的 agent 运行链路。
- 现在已经具备“完整业务版详细设计包”的第一版，足以让后续大模型按文档持续推进开发，而不只依赖上下文对话。

## 本轮 spec tasks 执行记录（2026-03-13）

- **T2.2 已完成**：
  - `daemon` 已收紧为 `service_manager` 的只读投影视图，不再参与生命周期写操作
  - `service.install` 已去掉重复 install，`service.status` 已显式标记 `daemonProjected`
  - 验证：`zig build test --summary all` 通过（107/107）
  - 提交：`7c850af` `固化 runtime 与 daemon 边界`

- **T3.1 已完成**：
  - `session_state.zig` 已补 turn 级 snapshot 字段：provider/model/tool/usage/error/tool trace
  - `agent_runtime` 会写回 `session.turn.completed`，`session.get` 已可直接返回 richer session snapshot
  - 验证：`zig build test --summary all` 通过（108/108）
  - 提交：`47fbc77` `扩展 session turn 快照模型`

- **T3.3 已完成**：
  - `ToolOrchestrator` 已显式收口为单次调用合约（`SingleInvokeRequest` / `invokeSingle()`）
  - 多轮 provider → tool → provider loop 已继续收口在 `agent_runtime`
  - 验证：`zig build test --summary all` 通过（109/109）
  - 提交：`0e07cda` `收口工具调用与 agent loop 边界`

- **T4.2 已完成**：
  - `service_manager` 生命周期动作已具备幂等返回值与更稳定计数
  - `service.install/start/stop/restart` 命令面已补 `changed` / `stopApplied` / `startApplied`
  - 验证：`zig build test --summary all` 通过（110/110）
  - 提交：`521dfbe` `完善 service manager 生命周期语义`
  - 提交：`8e32bc6` `统一 service 生命周期命令输出`
  - 提交：`5a6c795` `补充 service lifecycle smoke 覆盖`

- **T4.3 已完成**：
  - `heartbeat` 健康判断已改为基于 stale window，而不是只看是否 beat 过
  - `cron` 已区分 tick 次数与实际执行 job 次数，并补最小 schedule 间隔语义
  - `cron.tick` 已去掉重复 heartbeat 计数，`cron.list` / `heartbeat.status` 已补更多运行态字段
  - 验证：`zig build test --summary all` 通过（112/112）
  - 注：测试过程中 `gateway_host` listener 线程在 Windows 下仍会输出一条 `GetLastError(87)` stderr，但构建摘要与测试结果均为成功
  - 提交：`1960707` `补齐 cron 与 heartbeat 运行时语义`
  - 提交：`9e4d108` `统一 cron 与 heartbeat 命令状态输出`
  - 提交：`3ef7a1d` `补充 cron heartbeat smoke 覆盖`

- **T6.1 已完成**：
  - 已把 `framework-based-ourclaw/tasks.md` 中对应任务状态由 `[-]` 更新为 `[x]`
  - 已补任务级实现摘要、验证结果和提交哈希，便于后续模型直接续做

## 建议下一步

1. ✅ **TASK-001 已完成**：已实现更完整的 resume/continue 语义，包括执行状态检查和避免重复执行
2. ✅ **TASK-002 已完成**：WebSocket fuller control protocol（`ack / pause / resume / close reason`）已收口
3. ✅ **TASK-003 已完成**：text-delta 策略显式化 + bridge/CLI live 时间窗口 flush 调度已收口
4. ✅ **TASK-004 已完成**：loader/parser/defaults 第一版配置运行时链路已收口
5. ✅ **TASK-005 已完成**：field registry 元数据与配置覆盖面已收口第一版
6. ✅ **TASK-006 已完成**：config migration / compatibility import 第一版已收口
7. ✅ **TASK-007 已完成**：config side effect / post-write hook 第一版真实行为已收口
8. ✅ **TASK-008 已完成**：prompt assembly / system prompt / tools prompt 注入第一版已收口
9. ✅ **TASK-009 已完成**：session snapshot / compaction / summary 第一版已收口
10. ✅ **TASK-010 已完成**：最小真实 CLI channel 第一版已收口
11. ✅ **TASK-011 已完成**：bridge / HTTP 关联的 channel/runtime 语义第一版已收口
12. ✅ **TASK-012 已完成**：memory 主路线（snapshot export / migrate apply）第一版已继续收口
13. ✅ **TASK-013 已完成**：provider / tool integration 真实行为第一版已继续收口
14. ✅ **TASK-014 已完成**：skills / cron / tunnel / mcp / hardware 最小操作行为已继续深化
15. ✅ **TASK-015 已完成**：gateway/runtime host 第一版已继续收口
16. ✅ **TASK-016 已完成**：service/daemon 模型第一版已继续收口
17. ✅ **TASK-017 已完成**：event bus / observer / metrics 查询面第一版已继续收口
18. ✅ **TASK-018 已完成**：manager 前置契约清单已整理并落盘
19. ✅ **TASK-019 已完成**：ourclaw-manager 专项规划文档已落地
20. ✅ **TASK-020 已完成**：runtime_client 第一版已落地
21. ✅ **TASK-021 已完成**：manager 最小 view models 已落地
22. ✅ **TASK-022 已完成**：host / bridge / services 最小闭环已落地

## 新的下一阶段里程碑（M2）

- **里程碑名称**：M2「产品化 runtime 与真实集成第一阶段」
- **目标**：不再重做基础骨架，而是优先补齐：
  1. 流式恢复与 execution reconnect
  2. gateway / runtime / service / daemon 的真实长期运行语义
  3. 文件 + env + migration + compat import 的配置治理深化
  4. execution 级 observability 关联键
  5. prompt profile / identity-driven prompt assembly
  6. retrieval / embeddings / memory ranking
  7. 现有 provider/tool 的生产语义第一阶段

- **为什么先做这轮**：
  - 当前 `ourclaw` 已经不是 demo 骨架，而是有完整第一版主链路
  - 离 `openclaw` 的主要差距，已经不在“有没有模块”，而在“能不能长期跑、能不能恢复、能不能治理、能不能运维”
  - 因此下一轮最值钱的是产品化收口，而不是继续无边界扩更多 stub 域

- **本轮明确暂不做**：
  - 完整 GUI / product workflow
  - voice
  - 大量新 channel 扩展
  - skills / cron / mcp / tunnel / hardware 的大面积新域集成
  - 一口气追求 openclaw 全量功能平移

- **新任务入口**：
  - `ourclaw/docs/specs/framework-based-ourclaw/tasks.md` 中新增的 `M2-01` ~ `M2-10`
  - 后续执行时，应继续按“主线落点 + 参考文件 + 验证方式”推进，而不是回到旧 gap 文档重新猜测

- **M2-01 已完成（2026-03-13）**：
  - `stream_projection.zig` 已把 Bridge / WebSocket 的 replay / resume / execution attach 语义补齐到和 SSE 一致
  - Bridge 现在不再在已有执行时直接返回 `already_running` 失败，而是可以对 running execution 重附着，或按 legacy `last_event_id` 进入 replay-only
  - WebSocket 现在也支持 legacy replay-only 与 execution cursor resume
  - 已新增 bridge replay-only、bridge execution resume、ws replay-only 三条 stream projection 测试
  - 验证：`zig build test --summary all` 通过（115/115）

- **M2-02 已完成（2026-03-13）**：
  - CLI 非流式输出已统一为 protocol envelope（`ok/result/error/meta`）
  - HTTP 特殊错误路径（未知 route、WS upgrade required）已统一为 protocol error envelope，并带 `meta.requestId`
  - Bridge / HTTP / CLI 现已用测试显式校验成功响应结构的一致性
  - 验证：`zig build test --summary all` 通过（116/116）

- **M2-03 已完成（2026-03-13）**：
  - `gateway_host` 已从单纯状态计数推进到更真实的 listener 宿主：暴露 `listener_ready`、`active_connections`、`reload_count`、`last_reloaded_ms`
  - 已新增 `gateway.reload` 命令与 `/v1/gateway/reload` 路由
  - `gateway.status` 与 smoke 测试已覆盖 listener/reload 字段
  - 验证：`zig build test --summary all` 通过（117/117）

- **M2-04 已完成（2026-03-13）**：
  - `service_manager` 已从纯计数/状态推进到更接近后台宿主模型：暴露 `pid`、`lock_held`、`autostart`、`restart_budget_remaining`、`stale_process_detected`
  - `daemon.status`、`service.install/start/stop/restart/status` 已把这些字段暴露到命令层
  - 已补 `markStaleProcess()`、restart budget 与后台锁/伪 PID 语义
  - 验证：`zig build test --summary all` 通过（118/118）

- **M2-05 已完成（2026-03-13）**：
  - `framework` 配置底座已补 file/env/object/array 加载能力，不再只支持标量读取
  - `parser` 已支持 object/array，`loader` 已支持 snapshot json/file 与 env override，`ourclaw/config/runtime.zig` 已暴露对应入口
  - 验证：`zig build test --summary all` 通过（119/119）

- **M2-06 已完成（2026-03-13）**：
  - migration/compat import 已增强为 richer metadata 模式：显式 alias 元数据、`unknownPaths`、`aliasRewriteCount`
  - `compat_import` 已具备 source-aware 归一化入口，可区分 `generic/nullclaw/openclaw`
  - smoke 与单元测试已覆盖 alias rewrite、unknown paths 和 source normalization
  - 验证：`zig build test --summary all` 通过（120/120）

- **M2-07 已完成（2026-03-13）**：
  - `events.poll` / `observer.recent` 已支持 execution/session 关联过滤与字段回显
  - `events.subscribe` 已显式回显 `topicPrefix`
  - `metrics.summary` 已补 execution/session/subscription 关联视图
  - smoke 已补 execution/session 关联链路断言
  - 验证：`zig build test --summary all` 通过（120/120）

- **M2-08 已完成（2026-03-13）**：
  - prompt assembly 已从最小 system prompt 进化到 profile / identity / response mode / session snapshot 驱动
  - `agent_runtime` 已把这些上下文接入 prompt 组装阶段
  - prompt assembly 单测已覆盖 profile / identity / mode / session snapshot 文本变体
  - 验证：`zig build test --summary all` 通过（120/120）

- **M2-09 已完成（2026-03-16）**：
  - `memory_runtime.zig` 已完成 richer ranking metadata 收口：`rank / ts_unix_ms / embedding_strategy / ranking_reason / embedding_score / keyword_overlap / kind_weight` 现已稳定参与命中排序与命令输出
  - `providers/root.zig` 已新增 `EmbeddingProvider` 抽象；`ProviderRegistry` 现可作为 provider-backed embeddings 接口被业务层消费，而不是让 memory runtime 直接依赖 registry 细节
  - `memory_runtime.zig` 在保留本地 `local_bow_v1` fallback 的同时，现可通过 provider abstraction 走真实 embedding 请求路径，并把 `provider_proxy_v1` 稳定回写到 retrieval 结果
  - `config/field_registry.zig`、`config_runtime_hooks.zig`、`runtime/app_context.zig` 的 `memory.embedding_provider` / `memory.embedding_model` 接线已真正驱动 provider-backed embeddings 行为，而不再只是元数据回显
  - `providers/openai_compatible.zig`、`tests/smoke.zig` 与 `src/domain/memory_runtime.zig` 单测已覆盖 provider-backed embeddings 路径
  - 顺手修复了 `memory_runtime.zig` 中 `embedQuery` / `buildEmbedding` 的编译漂移
  - 验证：`zig build test --summary all` 通过（123/123）

- **M2-10 已完成（2026-03-16）**：
  - `providers/root.zig` 已把 provider 调用扩成带 `timeout_secs / retry_budget` 的最小生产语义请求，并补 `ProviderErrorInfo` / `mapError()` 错误分类
  - `openai_compatible.zig` 已接收 provider timeout，并补 mock timeout / retry-once 路径，确保 provider retry / timeout 回归可验证
  - `tools/root.zig` 已补 `ToolInvokePolicy`；高风险工具默认需要显式风险确认，同时新增 `TOOL_BUDGET_EXCEEDED` / `TOOL_RISK_CONFIRMATION_REQUIRED` 错误映射
  - `tool_orchestrator.zig` 已补 tool budget、risk confirmation 与 `tool.call.audit` 事件，开始把 started / denied / finished 等执行语义稳定投影到 session/stream
  - `agent_runtime.zig`、`agent_run.zig`、`agent_stream.zig` 已将 provider timeout/retry 与 tool budget/risk 参数真正接入运行链路
  - `tests/smoke.zig` 与 provider/tool/runtime 单测已覆盖 retry / timeout / denied / budget 路径
  - 验证：`zig build test --summary all` 通过（132/132）

- **任务入口已切换（2026-03-16）**：
  - 原主线 `tasks.md` 的长篇已完成任务明细已归档到 `ourclaw/docs/specs/framework-based-ourclaw/archive/completed-mainline-tasks-2026-03-16.md`
  - phase-1 baseline spec 正文已迁移到 `ourclaw/docs/backup/framework-based-ourclaw/`
  - 后续继续推进 `ourclaw` 时，应优先查看 `ourclaw/docs/specs/reference-aligned-ourclaw/`

- **B1 已完成（2026-03-16）**：
  - `runtime/stream_registry.zig` 已把 `StreamExecution.cancel_requested` 真正传入 `agent_runtime.runStream()`，execution cancel 不再只停在 projector 层
  - `agent_runtime.zig` 已把取消信号贯通到 provider/tool 调用前后；provider/tool 在感知取消后统一返回 `error.StreamCancelled`
  - `providers/root.zig`、`providers/openai_compatible.zig` 已支持 provider 级 `cancel_requested`，并补 mock provider cancel-wait 路径
  - `tools/root.zig`、`tools/http_request.zig`、`tools/shell.zig`、`tools/file_read.zig` 已支持 tool execution context / cancel signal；`compat/http_util.zig` 已补 cancellable mock wait 路径
  - `interfaces/stream_projection.zig` 现在会把 `client_closed` 一并转成 execution cancel，补齐 client disconnect → execution cancel 链
  - `stream_registry.zig` 与 provider/tool/http_util 单测已覆盖 provider cancel、tool cancel 与 execution cancel 路径
  - 验证：`zig build test --summary all` 通过（141/141）

- **B2 已完成（2026-03-16）**：
  - `providers/root.zig` 的 `chatStream()` 已改为独立 provider 原生流入口，不再从 `chatOnce()` 派生伪流式 chunk
  - `providers/openai_compatible.zig` 已支持 provider-native text delta / tool-call / done 语义，并补 malformed / upstream close / retry exhausted 回归；同时接入了一版最小真实 SSE 解析路径
  - `agent_runtime.zig` 已切到消费 `chatStream()`，并把 `provider_native` 与 `runtime_synthesized` 明确打到事件链上
  - `interfaces/stream_projection.zig` 在 text-delta 聚合后仍保留 `streamSource`，保证投影侧可以区分 provider 原生流与 runtime 合成事件
  - `tests/smoke.zig` 与 provider/runtime/projection 单测已覆盖 stream delta、tool-call mid-stream、upstream close、malformed stream、retry exhaustion
  - 验证：`zig build test --summary all` 通过（152/152）

- **B3 第一子步已完成（2026-03-16）**：
- **B3 已完成（2026-03-16）**：
  - `agent_runtime.zig` 已补 execution budget 第一版骨架：`provider_round_budget`、`provider_attempt_budget`、`tool_call_budget`、`provider_retry_budget`、`total_deadline_ms`
  - `providers/root.zig` 已支持 provider attempt budget，使 provider budget 不再只等价于 round budget 或 retry budget
  - `session_state.zig` 与 `session_get.zig` 已开始沉淀 provider/tool/deadline 预算状态，session 侧可以直接查看预算消耗与剩余
  - `agent_run.zig` / `agent_stream.zig` 已开放 budget/deadline 参数入口
  - `tests/smoke.zig` 与 runtime/provider 单测已覆盖 round budget / attempt budget / deadline / retry exhaustion 路径
  - 验证：`zig build test --summary all` 通过（157/157）

- **B5 已完成（2026-03-16）**：
  - `ourclaw/docs/contracts/manager-runtime-surface.md` 已补第一版 manager-facing 稳定字段矩阵，先锁 `gateway.status`、`service.status`、`heartbeat.status`、`session.get`
  - `ourclaw-manager/src/runtime_client/types.zig` 已新增 typed contract snapshot 与轻量 parser，manager runtime client 不再只有原始 `success_json` 壳
  - `ourclaw-manager/src/runtime_client/status_client.zig`、`memory_client.zig`、`diagnostics_client.zig`、`events_client.zig` 已新增 typed reader 入口
  - `ourclaw-manager/src/view_models/status_view_model.zig`、`diagnostics_view_model.zig`、`logs_view_model.zig` 已开始持有 typed snapshot，而不再只保留原始 JSON
  - `ourclaw-manager/docs/planning/runtime-contract-entry.md` 已把新 contract 文档纳入 manager runtime 接入入口
  - 验证：`ourclaw-manager` 执行 `zig build test --summary all` 通过（19/19）

- **B6 已完成（2026-03-16）**：
  - 已开始清理主入口与历史文档漂移：`current-task-board.md` 现在真实反映当前 backlog，而不再停留在 `B1/B2` 语境
  - `ourclaw/docs/README.md`、`ourclaw/docs/backup/planning/full-business-gap-tasks.md` 已明确历史参考定位
  - `workspace-mainline-roadmap.md`、`task-001-execution-prompt.md` 已从旧任务源切到当前 spec / backlog 入口
  - `README.md`、`WORKSPACE_CONTEXT.md`、`AGENTS.md`、`restart-handoff.md` 现已统一默认入口顺序到 `tasks.md -> next-stage-backlog.md -> current-task-board.md`
  - `next-session-handoff-2026-03-13.md` 已降级为 dated handoff 历史快照

- **B4 已完成（2026-03-16）**：
  - `domain/skills.zig` 已补 `source / last_run_status / last_error_code` 与健康计算，`skills` 域不再只是最小静态 registry
  - `skills.install / skills.run / skills.list` 现已具备来源、健康状态、错误映射与 richer operational state 输出
  - `skills.run` 现会在 entry command 缺失时返回 `SKILL_ENTRY_COMMAND_MISSING`，并把失败状态稳定回写到 skill registry
  - `ourclaw` 测试已更新并通过：`zig build test --summary all`（158/158）
  - `skills` 已经满足 B4 单域完成定义；下一步转入 `tunnel`
  - `tunnel_runtime.zig` 现已补 endpoint 探测、健康状态、最近错误与 probe 计数；`tunnel.activate / tunnel.status / tunnel.deactivate` 已具备更真实的 lifecycle / health / error 语义
  - `ourclaw` 测试已再次更新并通过：`zig build test --summary all`（159/159）
  - `tunnel` 也已满足 B4 单域完成定义；下一步转入 `mcp`
  - `mcp_runtime.zig` 现已补 transport/endpoint 探测、健康状态、最近错误与 probe 计数；`mcp.register / mcp.list` 已具备更真实的 lifecycle / health / error 语义
  - `ourclaw` 测试已再次更新并通过：`zig build test --summary all`（161/161）
  - `mcp` 已满足 B4 单域完成定义；下一步转入 `hardware / peripheral`
  - `hardware.zig` / `peripherals.zig` 现已补 kind 探测/校验、健康状态、最近错误与 probe 计数；`hardware.register / peripheral.register / hardware.list` 已具备更真实的 inventory / health / error 语义
  - `ourclaw` 测试已再次更新并通过：`zig build test --summary all`（163/163）
  - `voice_runtime.zig` 已新增 voice runtime，并补音频外设绑定、健康状态、最近错误与最小 lifecycle；`voice.attach / voice.status / voice.detach` 已接入主命令面
  - `ourclaw` 测试已再次更新并通过：`zig build test --summary all`（165/165）
  - `voice` 已满足 B4 单域完成定义；`B4` 现已整体完成

- **A1 已完成（2026-03-16）**：
  - `framework` 已新增 shared capability manifest 合同与 JSON helper，不再要求业务层手写 capability JSON 结构
  - `ourclaw/src/runtime/capability_manifest.zig` 已成为 `ourclaw` 侧唯一 capability 装配入口
  - `app.meta` 已改为消费共享 manifest，而不是在命令实现里散落维护 `adapters/providers/channels/tools/commands/supports*`
  - 验证：`framework` `zig build test --summary all` 通过（121/121），`ourclaw` `zig build test --summary all` 通过（166/166）

- **A2 已完成（2026-03-16）**：
  - `framework` 已新增共享 `stream_sink / stream_event / stream_body` runtime 合同
  - `ourclaw` 现已把 `ByteSink`、通用 JSON event renderer，以及 `StreamingBody / WebSocketBody / ClientEventHandler` 的 erased contract 回抽到 `framework`
  - `stream_projection`、`stream_registry`、`stream_output` 的业务协议与执行恢复逻辑仍保留在 `ourclaw`，没有越界把业务语义抽进 framework
  - 验证：`framework` `zig build test --summary all` 通过（124/124），`ourclaw` `zig build test --summary all` 通过（165/165）

- **B2 第二子步已完成（2026-03-16）**：
  - `memory.snapshot_export` / `memory.migrate_apply` 已补 `snapshotJson` import-ready 字段，输出面与 `memory.snapshot_import.snapshot_json` 对齐
  - `memory_runtime.zig` 已改为结构化 snapshot import，支持 nested `tool_result` 与 compact 后 `session_summary` 的 canonical roundtrip
  - `memory.summary` / `session.compact` 已修复 `summaryText` JSON escaping，summary 内容中的引号与换行不再破坏命令返回体
  - domain + smoke 已补 export -> compact -> import -> summary/retrieve 回归
  - 验证：`zig build test --summary all` 通过（169/169）

- **当前下一步（2026-03-16）**：
  - 继续评估 `B2` canonical snapshot schema 是否要稳定保留 `tsUnixMs / embeddingProvider / embeddingModel` 等 richer metadata；若不再扩 `B2`，则切到 `B3`

## 续写约定

- 当前执行状态优先更新根级 `docs/planning/current-task-board.md`
- 只要产生新的设计分析、阶段判断、阻塞结论或任务拆分，就同步写入 `docs/` 下对应 md。
- 会话级进展优先追加到本文档；专题级结论优先写入对应专题文档。
