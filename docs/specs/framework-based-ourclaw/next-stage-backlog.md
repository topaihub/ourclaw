# ourclaw 下一阶段 backlog（2026-03-16）

> 用途：承接 `framework-based-ourclaw` 主线 spec 在 `M2-10` 完成后的下一阶段任务池。
>
> 这些任务不是“当前 spec 的未完成项”，而是基于现状建议优先继续推进的后续 backlog。

## 1. 当前判断

- `framework + ourclaw` 主线第一阶段已经收口完成
- 下一阶段不再优先扩更多横向域，而是优先把现有 runtime / provider / tool / stream 语义做深
- 第二优先级是把已经有最小操作面的扩展域推进到更真实的后端语义
- 第三优先级是做文档与 backlog 治理，降低新会话误判成本

## 2. 建议优先级

### B1：打通 provider / tool 的真实取消链

- 状态：`done`
- 目标：把当前流层 `cancel` 真正传到 provider HTTP 请求和 tool 执行链，而不只是停止投影输出
- 主线落点：
  - `ourclaw/src/providers/*`
  - `ourclaw/src/tools/*`
  - `ourclaw/src/domain/agent_runtime.zig`
  - `ourclaw/src/domain/tool_orchestrator.zig`
  - `ourclaw/src/interfaces/http_adapter.zig`
  - `ourclaw/src/interfaces/stream_projection.zig`
- 完成定义：
  - provider/tool 执行都能接收 cancel 信号
  - 取消后的错误码、事件和 terminal reason 有稳定映射
  - `agent.stream` / SSE / WebSocket / CLI live 的取消语义一致
- 验证：补 provider cancel / tool cancel / client disconnect / repeated cancel 回归测试
 - 本轮实现（2026-03-16）：
   - `runtime/stream_registry.zig` 已把 `StreamExecution.cancel_requested` 真正传入 `agent_runtime.runStream()`，而不再只停留在 projector 层
   - `domain/agent_runtime.zig` 已把取消信号接到 provider/tool 调用前后，并在运行中统一返回 `error.StreamCancelled`
   - `providers/root.zig`、`providers/openai_compatible.zig` 已支持 provider request 级 `cancel_requested`，并补 mock provider cancel-wait 路径
   - `tools/root.zig`、`tools/http_request.zig`、`tools/shell.zig`、`tools/file_read.zig` 已支持 tool execution context / cancel signal；`compat/http_util.zig` 已补 cancellable mock wait 路径
   - `interfaces/stream_projection.zig` 现在会把 `client_closed` 也同步转成 execution cancel，补齐 client disconnect → execution cancel 链
   - 验证：`zig build test --summary all` 通过（141/141）

### B2：把 provider streaming 从模拟投影推进到真实原生流

- 状态：`done`
- 目标：让 `chatStream()` 不再只是 `chatOnce()` 派生，而是真正承载 provider 原生流式 token / tool-call / finish / failure 语义
- 主线落点：
  - `ourclaw/src/providers/root.zig`
  - `ourclaw/src/providers/openai_compatible.zig`
  - `ourclaw/src/domain/agent_runtime.zig`
  - `ourclaw/src/domain/stream_output.zig`
- 完成定义：
  - provider 原生流式 chunk 可进入统一 stream output
  - finish reason / upstream failure / retry exhaustion 有稳定投影
  - `agent.stream` 返回的事件链能区分 provider 原生流与 runtime 合成事件
- 验证：补 stream delta / tool-call mid-stream / upstream close / malformed stream 回归测试
 - 本轮实现（2026-03-16）：
   - `src/providers/root.zig` 的 `chatStream()` 已不再由 `chatOnce()` 派生，而是独立委托 provider 原生流路径
   - `src/providers/openai_compatible.zig` 已补最小原生 chunk 语义、tool-call mid-stream、malformed/upstream-close/retry-exhausted mock 路径，以及一版最小真实 SSE 解析路径
   - `src/domain/agent_runtime.zig` 已改为消费 `chatStream()`，将 provider 原生 chunk 直接投影为 `text.delta` / `provider.tool.call` / `provider.round.completed`
   - `src/interfaces/stream_projection.zig` 已在 text-delta 聚合后保留 `streamSource`，可稳定区分 `provider_native` 与 `runtime_synthesized`
   - `tests/smoke.zig` 与 provider/runtime/projection 单测已覆盖 stream delta、tool-call mid-stream、upstream close、malformed stream、retry exhaustion
   - 验证：`zig build test --summary all` 通过（152/152）

### B3：深化 budget / deadline / retry 策略模型

- 状态：`done`
- 目标：把当前第一阶段的 `retry_budget` / `tool_call_budget` 推进成可组合的 execution budget 模型
- 主线落点：
  - `ourclaw/src/domain/agent_runtime.zig`
  - `ourclaw/src/domain/tool_orchestrator.zig`
  - `ourclaw/src/providers/*`
  - `ourclaw/src/tools/*`
  - `ourclaw/src/contracts/*`
- 完成定义：
  - 区分 total deadline、provider budget、tool budget、round budget
  - session / stream / observer 能暴露 budget 消耗和耗尽原因
  - 拒绝、超时、重试耗尽的错误码不会混淆
- 验证：补 budget exhausted / deadline exceeded / retry exhausted / nested tool loop 回归测试
 - 本轮实现（2026-03-16，第一子步）：
   - `src/domain/agent_runtime.zig` 已补 `provider_round_budget`、`provider_attempt_budget`、`tool_call_budget`、`provider_retry_budget`、`total_deadline_ms` 的第一版 execution budget 收口
   - 已新增 `PROVIDER_ROUND_BUDGET_EXCEEDED`、`PROVIDER_ATTEMPT_BUDGET_EXCEEDED`、`EXECUTION_DEADLINE_EXCEEDED` 等更清晰的预算/时限错误语义
   - `src/providers/root.zig` 现已支持独立于 round 的 `remaining_attempt_budget`，把 provider 尝试次数预算与 retry/round 区分开
   - `src/domain/session_state.zig` 与 `src/commands/session_get.zig` 已开始暴露 provider/tool/deadline 预算字段，session 视图不再只剩 toolRounds 和 lastErrorCode
   - `src/commands/agent_run.zig`、`src/commands/agent_stream.zig` 已接入新预算参数，`tests/smoke.zig` 与 runtime/provider 单测已覆盖 retry / round budget / attempt budget / deadline 路径
   - 验证：`zig build test --summary all` 通过（157/157）
 - 结项说明：
   - 现在已满足 B3 的完成定义：`total deadline / provider budget / tool budget / round budget` 已分离；`session / stream / observer` 都能暴露预算字段或耗尽原因；错误码不再混淆
   - 非阻塞说明：失败 turn 的 `session.get` 更偏向通过 `lastErrorCode` 暴露耗尽原因，而成功 turn 会额外带出更完整的 remaining snapshot

### B4：把 skills / tunnel / mcp / hardware 从“可操作第一版”推进到真实后端语义

- 状态：`done`
- 目标：不要继续停留在最小操作状态输出，而是逐域补真实注册、健康检查、生命周期或外部集成
- 建议顺序：
  1. `skills`
  2. `tunnel`
  3. `mcp`
  4. `hardware / peripheral`
  5. `voice`
- 主线落点：
  - `ourclaw/src/domain/*`
  - `ourclaw/src/commands/*`
  - `ourclaw/src/runtime/*`
- 完成定义：每个域至少具备一种“真实后端行为 + 健康状态 + 错误映射 + smoke 覆盖”
- 验证：按域补独立 smoke / 单测，不并发铺开全部域
 - 本轮实现（2026-03-16，skills 子域已完成）：
   - `src/domain/skills.zig` 已补 skill `source / last_run_status / last_error_code` 与健康计算，不再只记录安装时间和运行次数
   - `src/commands/skills_install.zig` 已在安装返回里暴露 `source / healthState / healthMessage`
   - `src/commands/skills_run.zig` 已补 entry command 缺失校验、失败错误码回写和健康状态投影
   - `src/commands/skills_list.zig` 已补 `source / healthState / healthMessage / lastRunStatus / lastErrorCode`
   - `tests/smoke.zig` 与 `src/domain/skills.zig` 单测已覆盖 richer skill state；验证：`ourclaw` 执行 `zig build test --summary all` 通过（158/158）
 - 当前子域进度：
   - `skills`：`done`
   - `tunnel`：`done`
   - `mcp`：`done`
   - `hardware / peripheral`：`done`
    - `voice`：`done`
 - 本轮实现（2026-03-16，tunnel 第一子域）：
   - `src/domain/tunnel_runtime.zig` 已补 endpoint 探测、健康状态、最近错误、probe 计数与最近探测时间，不再只是内存开关
   - `src/commands/tunnel_activate.zig` 现会对 endpoint 做真实校验/探测；失败时稳定返回 `TunnelInvalidEndpoint` / `TunnelEndpointUnreachable` 相关状态投影
   - `src/commands/tunnel_status.zig` 已补 `healthState / healthMessage / lastErrorCode / probeCount / lastProbeMs / lastProbeStatusCode`
   - `src/commands/tunnel_deactivate.zig` 已补 `inactive/deactivated` 生命周期语义输出
   - `tests/smoke.zig` 与 `src/domain/tunnel_runtime.zig` 单测已覆盖成功激活与失败探测；验证：`ourclaw` 执行 `zig build test --summary all` 通过（159/159）
 - 本轮实现（2026-03-16，mcp 第一子域）：
    - `src/domain/mcp_runtime.zig` 已补 transport/endpoint 探测、健康状态、最近错误、probe 计数与最近检查时间
    - `src/commands/mcp_register.zig` 现支持 `endpoint`，注册时会做真实探测并返回 `healthState / healthMessage / probeCount`
    - `src/commands/mcp_list.zig` 已补 `endpoint / healthState / healthMessage / lastErrorCode / probeCount / lastCheckedMs / lastConnectedMs`
    - `tests/smoke.zig` 与 `src/domain/mcp_runtime.zig` 单测已覆盖成功注册与失败探测；验证：`ourclaw` 执行 `zig build test --summary all` 通过（161/161）
  - 本轮实现（2026-03-16，hardware / peripheral 第一子域）：
   - `src/domain/hardware.zig` 已补 kind 探测、健康状态、最近错误、probe 计数与最近检查时间
   - `src/domain/peripherals.zig` 已补 kind 支持校验、健康状态、最近错误、probe 计数与最近检查时间
    - `src/commands/hardware_register.zig`、`src/commands/peripheral_register.zig` 现会返回 `healthState / healthMessage / probeCount`
    - `src/commands/hardware_list.zig` 已补 richer hardware/peripheral inventory，统一暴露 `healthState / healthMessage / lastErrorCode / probeCount / lastCheckedMs`
    - `tests/smoke.zig` 与 domain 单测已覆盖成功注册、失败探测与 richer inventory；验证：`ourclaw` 执行 `zig build test --summary all` 通过（163/163）
 - 本轮实现（2026-03-16，voice 第一子域）：
   - `src/domain/voice_runtime.zig` 已新增 voice runtime，并补音频外设绑定、健康状态、最近错误与最小 lifecycle
   - `src/commands/voice_attach.zig`、`src/commands/voice_status.zig`、`src/commands/voice_detach.zig` 已接入主命令面
   - `src/runtime/app_context.zig`、`src/domain/services.zig`、`src/interfaces/http_adapter.zig`、`src/interfaces/cli_adapter.zig` 已完成 voice 接线
   - `tests/smoke.zig` 与 `src/domain/voice_runtime.zig` 单测已覆盖成功绑定、失败绑定与状态查询；验证：`ourclaw` 执行 `zig build test --summary all` 通过（165/165）
 - 结项说明：
   - `skills / tunnel / mcp / hardware-peripheral / voice` 五个子域均已满足 B4 的单域完成定义
   - `B4` 至此整体完成
 - 本轮实现（2026-03-16，voice 第一子域）：
   - `src/domain/voice_runtime.zig` 已新增 voice runtime，并补音频外设绑定、健康状态、最近错误与最小 lifecycle
   - `src/commands/voice_attach.zig`、`src/commands/voice_status.zig`、`src/commands/voice_detach.zig` 已接入主命令面
   - `src/runtime/app_context.zig`、`src/domain/services.zig`、`src/interfaces/http_adapter.zig`、`src/interfaces/cli_adapter.zig` 已完成 voice 接线
   - `tests/smoke.zig` 与 `src/domain/voice_runtime.zig` 单测已覆盖成功绑定、失败绑定与状态查询；验证：`ourclaw` 执行 `zig build test --summary all` 通过（165/165）

### B5：为 manager 消费面补稳定 contract layer

- 状态：`done`
- 目标：把已经成熟的 session / event / diagnostics / service / provider/tool 事件面整理成 manager 更容易绑定的稳定契约
- 主线落点：
  - `ourclaw/docs/contracts/*`
  - `ourclaw/src/commands/*`
  - `ourclaw/src/domain/session_state.zig`
  - `ourclaw-manager/src/runtime_client/*`
- 完成定义：manager 依赖的字段分出 stable / provisional，减少 UI 提前绑定演进中的字段
- 验证：文档与 runtime_client 一致，必要时补契约快照测试
 - 本轮实现（2026-03-16，第一子步）：
   - `ourclaw/docs/contracts/manager-runtime-surface.md` 已新增 manager-facing 稳定字段矩阵，第一版锁定 `gateway.status`、`service.status`、`heartbeat.status`、`session.get`
   - `ourclaw-manager/src/runtime_client/types.zig` 已新增四个 contract snapshot 结构与轻量 typed parser，不再只有 `success_json/app_error` 原始壳
   - `ourclaw-manager/src/runtime_client/status_client.zig` 与 `memory_client.zig` 已新增 typed reader 入口，开始为 manager 建立稳定消费层
   - `ourclaw-manager/docs/planning/runtime-contract-entry.md` 已把新契约文档接入 manager runtime 接入入口
   - 后续补强（2026-03-16，同轮追加）：
     - `ourclaw-manager/src/runtime_client/diagnostics_client.zig`、`events_client.zig` 已补 `diagnostics / metrics / logs / events.poll / task.*` typed reader
     - `ourclaw-manager/src/view_models/diagnostics_view_model.zig`、`logs_view_model.zig` 已开始持有 typed snapshot，而不再只保留原始 JSON
     - `ourclaw-manager/src/view_models/status_view_model.zig` 已补 `gateway/service/heartbeat` typed snapshot；`observer.recent` 也已纳入 typed contract 闭环
   - 验证：`ourclaw-manager` 执行 `zig build test --summary all` 通过（19/19）
 - 结项说明：
   - manager 常用面已形成“契约文档 + runtime_client typed reader + view model 开始 typed 消费”的稳定闭环
   - 非阻塞说明：`stable / provisional` 目前仍主要靠文档约束，而不是完全靠类型隔离；后续 manager 侧仍应避免把 provisional 字段做强绑定逻辑

### B6：清理旧 planning 文档与新 spec 的映射

- 状态：`done`
- 目标：减少 `planning/` 历史文档、handoff 和新 spec 之间的状态漂移
- 主线落点：
  - `ourclaw/docs/README.md`
  - `ourclaw/docs/planning/*`
  - `docs/planning/*`
- 完成定义：
  - 每份仍保留的历史文档都明确“用途 / 时效 / 主入口”
  - 新会话不再容易把过期 handoff 当成当前任务表
- 验证：人工检查文档入口是否单一且无明显冲突说明
 - 本轮实现（2026-03-16）：
   - `docs/planning/current-task-board.md` 已改为真实反映当前 backlog（不再停留在 `B1/B2` 语境）
   - `README.md`、`WORKSPACE_CONTEXT.md`、`AGENTS.md`、`restart-handoff.md` 已统一默认入口顺序到 `tasks.md -> next-stage-backlog.md -> current-task-board.md`
   - `ourclaw/docs/README.md`、`ourclaw/docs/planning/full-business-gap-tasks.md` 已明确“历史参考，不作为当前主入口”
   - `docs/planning/workspace-mainline-roadmap.md`、`docs/planning/task-001-execution-prompt.md` 已从旧 `full-business-gap-tasks.md` 入口切到新 spec / backlog 入口
   - `ourclaw/docs/planning/next-session-handoff-2026-03-13.md` 已降级为 dated handoff 历史快照，并清理旧默认续做顺序
 - 结项说明：
   - 仍保留的历史文档现在都已明确“用途 / 时效 / 主入口”
   - 新会话默认入口链已单一，不再容易把过期 handoff / 旧任务表当成当前任务源

## 3. 推荐执行顺序

建议下一阶段按以下顺序推进：

1. `B1` provider/tool 真实取消链
2. `B2` provider 原生 streaming 语义
3. `B3` budget / deadline / retry 深化
4. `B5` manager 稳定 contract layer
5. `B4` skills / tunnel / mcp / hardware / voice 分域推进
6. `B6` 文档治理与历史映射清理

## 4. 一句结论

下一阶段最值得做的，不是再横向加更多壳，而是先把 **provider / tool / stream 的生产语义从“第一阶段可用”推进到“更真实可治理”**。
