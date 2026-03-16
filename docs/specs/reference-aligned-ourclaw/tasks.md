# reference-aligned-ourclaw — Tasks

> 说明：
>
> - 这份任务表只描述 phase-1 之后仍需继续推进的工作
> - 已完成的一阶段与 B1~B6 不再重复列为 active tasks

## 1. Active Work Waves

### Wave A — framework 继续抽共享基座

- [x] **A1. 提炼 shared capability manifest 到 framework**
  - 主线落点：`framework/src/contracts/*`、`framework/src/runtime/*`、`ourclaw/src/commands/app_meta.zig`
  - 参考：`nullclaw` capability/runtime exposure，`openclaw` control-plane capability surface
  - Failing test：新增 capability manifest 测试后运行 `zig build test --summary all`（`framework`）
  - Passing test：`framework` 单测通过，`ourclaw` status/capability 输出仍通过回归
  - Regression：`framework` `zig build test --summary all` + `ourclaw` `zig build test --summary all`
  - 完成定义：共享 capability 描述不再散落在业务层拼装
  - 本轮实现（2026-03-16）：
    - `framework/src/contracts/capability_manifest.zig` 已新增 `CapabilityManifest / CapabilityGroup / CapabilityFlag`
    - `framework/src/runtime/capability_manifest.zig` 已新增共享 JSON helper
    - `ourclaw/src/runtime/capability_manifest.zig` 已新增业务侧唯一装配入口
    - `ourclaw/src/commands/app_meta.zig` 已改为消费共享 manifest，而不是在命令里手拼 capability JSON
    - 验证：`framework` `zig build test --summary all` 通过（121/121），`ourclaw` `zig build test --summary all` 通过（166/166）

- [x] **A2. 提炼 shared runtime adapter / stream sink 合同到 framework**
  - 主线落点：`framework/src/runtime/*`、`ourclaw/src/interfaces/*`、`ourclaw/src/domain/stream_output.zig`
  - 参考：`nullclaw` streaming/runtime adapter
  - 完成定义：ourclaw 入口适配层的共享协议部分回抽到 `framework`
  - 本轮实现（2026-03-16）：
    - `framework/src/runtime/stream_sink.zig` 已承接 `ByteSink / ArrayListSink / fileSink / netStreamSink`
    - `framework/src/runtime/stream_event.zig` 已新增共享 `renderJsonEvent(...)`
    - `framework/src/runtime/stream_body.zig` 已新增 `StreamingBody / WebSocketBody / ClientEventHandler` 合同
    - `ourclaw/src/interfaces/stream_sink.zig` 已降为 framework shim；`stream_projection.zig` 已改用 shared event renderer；`gateway_host.zig` 已改用 shared body contract
    - 验证：`framework` `zig build test --summary all` 通过（124/124），`ourclaw` `zig build test --summary all` 通过（165/165）

### Wave B — session / memory / agent runtime 深化

- [x] **B1. 完成 session ledger / replay / usage 结构化模型**
  - 主线落点：`ourclaw/src/domain/session_state.zig`、`src/commands/session_get.zig`
  - 参考：`nullclaw` session manager、`openclaw` session/control semantics
  - 验证：domain tests + smoke
  - 完成定义：session snapshot 足以支撑 manager 与恢复场景
  - 当前进展（2026-03-16）：
    - 已完成第一子步：`session_state.zig` 现已补 `seq / stream_seq / execution_id / ts_unix_ms` 的 ledger header；`session.get` 已新增 `counts / replay / latestTurn` 结构化块
    - 已完成第二子步：provider `promptTokens / completionTokens / totalTokens` 已接入 `session.turn.completed` 与 `session.get`
    - 已完成第三子步：`session_state.snapshotMeta()` 已开始聚合累计 `prompt/completion/total tokens`；`session.get` 已新增 `usage` 结构化块；`session_state.zig` 与 `tests/smoke.zig` 已补累计 usage 回归；`ourclaw` `zig build test --summary all -j1` 通过（173/173）
    - 已完成第四子步：`session_state.recentTurns()` 已补最近 turn 结构化提取；`session.get` 已新增 `recentTurns` 与 `recovery.executionCursor`；`ourclaw` `zig build test --summary all -j1` 通过（174/174）
    - 完成判断：当前 session snapshot 已具备 ledger header、累计 usage、recent turns、replay 范围与恢复 cursor，足以支撑 manager / resume 场景

- [x] **B2. 深化 memory 生命周期能力**
  - 主线落点：`ourclaw/src/domain/memory_runtime.zig`、`src/commands/memory_*`
  - 参考：`nullclaw/src/memory/*`
  - 验证：domain tests + migration roundtrip + smoke
  - 完成定义：summary / compact / migrate / retrieval / semantic layer 形成更清晰分层
  - 当前进展（2026-03-16）：
    - 已完成第一子步：`compactSession` 已升级为 `CompactionResult`；`memory.snapshot_export` / `memory.migrate_apply` 已输出更清晰 lifecycle 结果；新增 `memory.snapshot_import`
    - 已完成第二子步：`memory.snapshot_export` / `memory.migrate_apply` 已补 `snapshotJson` import-ready 字段；`memory_runtime.zig` 已改为结构化 snapshot import，支持 nested `tool_result` 与 compact 后 `session_summary` 的 canonical roundtrip；`memory.summary` / `session.compact` 已修复 `summaryText` JSON 转义
    - 已完成第三子步：canonical snapshot schema 已稳定保留 `tsUnixMs / embeddingProvider / embeddingModel` 等 richer metadata；`memory_runtime.zig` domain tests 与 `tests/smoke.zig` roundtrip 已覆盖 richer metadata 保真
    - 完成判断：summary / compact / migrate / snapshot export/import / retrieval richer metadata 已形成稳定闭环

- [x] **B3. 深化 agent runtime 策略面**
  - 主线落点：`ourclaw/src/domain/agent_runtime.zig`、`prompt_assembly.zig`
  - 参考：`nullclaw` agent runtime、`openclaw` 路由与控制语义
  - 验证：agent domain tests + smoke
  - 完成定义：provider/tool/memory/session 策略与压缩/路由边界清晰可测
  - 当前进展（2026-03-16）：
    - 已完成第一子步：`session.compact` 产生的 compacted summary 现已通过 `session.summary` / `snapshot.latest_summary_text` 优先注入 `prompt_assembly`，不再与 raw memory recall 混为一块
    - `memory_runtime.recallForTurn()` 现已拆分 `compacted_summary_text` 与 `Recent Memory Recall`，避免 compacted summary 在 prompt 中重复展开
    - `prompt_assembly.zig`、`agent_runtime.zig` 与 `tests/smoke.zig` 已补 summary-first 回归；`ourclaw` `zig build test --summary all -j1` 通过（172/172）
    - 已完成第二子步：`max_tool_rounds` 已从 `agent.run` / `agent.stream` command surface 透传到 runtime，并写入 `session.turn.completed.maxToolRounds`；`session.get` 的 `latestTurn` / `recentTurns` 已对外暴露该字段；`ourclaw` `zig build test --summary all -j1` 通过（175/175）
    - 已完成第三子步：`allow_provider_tools / prompt_profile / response_mode` 已从 `agent.run` / `agent.stream` command surface 进入 runtime，并写入 `session.turn.completed`；`session.get` 的顶层字段、`latestTurn` 与 `recentTurns` 已对外暴露这组策略面；`ourclaw` `zig build test --summary all -j1` 通过（175/175）
    - 已完成第四子步：`prompt_assembly` 已新增 `Execution Strategy JSON` system message；runtime 的 budgets / `max_tool_rounds` / `allow_provider_tools` / `prompt_profile` / `response_mode` 现已显式进入 provider prompt；`openai_compatible` probe 与 smoke 已把该链路纳入回归
    - 完成判断：当前 provider/tool/memory/session 策略与压缩边界已具备 command surface、session surface、prompt surface 与 smoke/domain 回归，B3 可视为收口

### Wave C — gateway / control-plane 对齐 openclaw

- [x] **C1. 统一 gateway control-plane contract**
  - 主线落点：`ourclaw/src/runtime/gateway_host.zig`、`src/interfaces/http_adapter.zig`、`src/commands/gateway_*`
  - 参考：openclaw gateway/server/runtime-config
  - 验证：gateway tests + HTTP smoke
  - 完成定义：gateway 状态、reload、stream subscribe、health 字段面稳定
  - 当前进展（2026-03-16）：
    - 已完成第一子步：`gateway.status` / `gateway.reload` / `gateway.stream_subscribe` 已复用统一 gateway snapshot contract；`gateway.start` / `gateway.stop` 也已切到一致返回结构
    - 已完成第二子步：`gateway_host` 的 `/health` 与 `/ready` 已从固定字面量改为真实状态投影
    - 已完成第三子步：`http_adapter.zig` 已补 gateway control-plane route smoke，覆盖 `/v1/gateway/status`、`/v1/gateway/reload`、`/v1/gateway/stream-subscribe`
    - 完成判断：gateway 状态、reload、stream subscribe 与 health/readiness 字段面已形成统一 contract，并具备 gateway tests + HTTP smoke

- [x] **C2. 深化 service / daemon 恢复与运行策略**
  - 主线落点：`ourclaw/src/runtime/service_manager.zig`、`daemon.zig`、`runtime_host.zig`
  - 参考：`nullclaw` service/runtime，openclaw daemon/service
  - 验证：runtime tests
  - 完成定义：service/daemon 不只是 lifecycle，而有恢复、预算、健康策略
  - 当前进展（2026-03-16）：
    - 已完成第一子步：`service.install/start/stop/restart/status` 已统一到同一份 service snapshot contract，恢复/host/gateway 运行字段面一致
    - 已完成第二子步：`restart_budget_remaining` 已从静态字段升级为真实阻断行为；预算耗尽后 `service.restart` 会显式返回 `budgetExhausted`
    - 已完成第三子步：`heartbeatHealthy / heartbeatAgeMs / heartbeatStaleAfterMs` 已并入 service contract，不再只通过 `heartbeat.status` 独立暴露
    - 已完成第四子步：stale 进程已形成显式恢复策略投影，`recoveryEligible / recoveryAction` 进入 runtime 与 service contract
    - 完成判断：service/daemon 当前已具备恢复、预算、健康三类策略面，并通过 runtime tests + smoke 验证

- [x] **C3. 完成 config schema / migration / import 产品化治理**
  - 主线落点：`ourclaw/src/config/*`、`src/runtime/config_runtime_hooks.zig`
  - 参考：openclaw config schema / reload / onboarding
  - 验证：config tests + smoke
  - 完成定义：配置治理成为 control-plane 核心，而不是附属功能
  - 当前进展（2026-03-16）：
    - 已完成第一子步：`config.migrate_apply` / `config.compat_import` 的 apply 返回面已补齐 `from/to version`、`unknownCount`、`requiresRestart` 等治理摘要
    - 已完成第二子步：`config_runtime_hooks` 已把 `gateway.require_pairing` 与 `runtime.max_tool_rounds` 从 schema 侧 `notify_runtime` 真正对齐到运行态
    - 已完成第三子步：`app.meta` 与 `agent.run` / `agent.stream` 默认值现已消费 runtime config effective 值；smoke 已覆盖配置变更对运行态与 agent 默认行为的影响
    - 完成判断：schema、migration、compat import、runtime notify 与 apply governance 当前已形成闭环，C3 可视为收口

### Wave D — 流协议与入口适配统一

- [x] **D1. 深化 SSE / WS / bridge / CLI live 控制语义**
  - 主线落点：`ourclaw/src/interfaces/stream_projection.zig`、`stream_websocket.zig`、`cli_adapter.zig`
  - 参考：nullclaw streaming 与 openclaw gateway live 语义
  - 验证：projection tests + smoke
  - 完成定义：ack / pause / resume / backpressure / disconnect / reconnect 更一致
  - 当前进展（2026-03-16）：
    - 已完成第一子步：WebSocket `control.close` 现已优先回显客户端最新 `ackedSeq`，`ack` 不再只是被动记录
    - 已完成第二子步：CLI live 已补 `--last-event-id`，能够复用既有 `replay_only` / execution-cursor resume 语义
    - 完成判断：SSE / WS / bridge / CLI 当前已形成更一致的 live control 语义；更细的参数面对齐转入 D2 处理

- [x] **D2. 完成 CLI / HTTP / bridge 命令参数面对齐**
  - 主线落点：`ourclaw/src/interfaces/*`
  - 完成定义：主要命令在三个入口的参数支持一致
  - 当前进展（2026-03-16）：
    - 已完成第一子步：CLI 已补齐 `agent.run` / `agent.stream` 的策略参数（`prompt_profile`、`response_mode`、`max_tool_rounds`、`allow_provider_tools` 等）
    - 已完成第二子步：CLI 已补齐 `memory.summary` / `session.get` 的可选参数（`max_items`、`summary_items`、`recent_turns_limit`）
    - 已完成第三子步：CLI 已补齐 `events.subscribe --after-seq`、`events.poll --execution-id/--session-id`、`observer.recent --execution-id/--session-id`
    - 完成判断：HTTP / bridge 的通用透传与 CLI 的关键缺口当前已收口，D2 可视为完成

### Wave E — Manager contract 深化

- [ ] **E1. 把 stable/provisional 从文档推进到类型和 API 约束**
  - 主线落点：`ourclaw/docs/contracts/*`、`ourclaw-manager/src/runtime_client/*`
  - 完成定义：manager typed client 对稳定字段形成更强约束

- [ ] **E2. 扩展 manager 对 runtime 的 typed 消费面**
  - 主线落点：`ourclaw-manager/src/view_models/*`
  - 完成定义：主要 view model 不再以原始 JSON 作为主数据源

### Wave F — 渠道与产品表面对齐

- [ ] **F1. 深化 channel routing / channel manager 模型**
  - 主线落点：`ourclaw/src/channels/*`、`runtime/app_context.zig`
  - 参考：`nullclaw` channel manager、openclaw channel routing
  - 完成定义：channel 不再只是 registry，而具备更明确的路由和健康治理

- [ ] **F2. 深化 provider capability / model surface**
  - 主线落点：`ourclaw/src/providers/*`
  - 参考：`nullclaw` provider contract、openclaw models/config
  - 完成定义：provider 能力、模型、健康与控制面输出更完整

## 2. Docs Governance Tasks

- [ ] **G1. 精简 docs 首页导航**
  - 主线落点：`ourclaw/docs/README.md`
  - 完成定义：主页只保留 `active spec / baseline / supporting / historical` 四层导航

- [ ] **G2. 给 `architecture/` 与 `planning/` 增加索引页**
  - 主线落点：`ourclaw/docs/architecture/README.md`、`ourclaw/docs/planning/README.md`
  - 完成定义：目录层级可一眼理解，无需翻长列表

- [ ] **G3. 持续归档仍带任务语义的旧 planning 文档**
  - 主线落点：`ourclaw/docs/planning/*`
  - 完成定义：旧 planning 不再像 active task source

## 3. 执行约定

- 每项任务开始前先更新 `docs/planning/current-task-board.md`
- 每项任务结束后同步更新：
  - `docs/planning/current-task-board.md`
  - `ourclaw/docs/planning/session-resume.md`
  - 对应 spec 状态
- 优先跑相邻测试，再跑仓库全量测试

## 4. 一句结论

这份任务表的目标不是“补一批零散功能”，而是把 `ourclaw` 系统性推进到：**参考对齐、控制面完整、可长期运营、且文档单一事实源明确** 的完成态。
