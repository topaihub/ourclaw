# reference-aligned-ourclaw — Tasks

> 说明：
>
> - 这份任务表只描述 phase-1 之后仍需继续推进的工作
> - 已完成的一阶段与 B1~B6 不再重复列为 active tasks

## 1. Active Work Waves

### Wave A — framework 继续抽共享基座

- [ ] **A1. 提炼 shared capability manifest 到 framework**
  - 主线落点：`framework/src/contracts/*`、`framework/src/runtime/*`、`ourclaw/src/commands/app_meta.zig`
  - 参考：`nullclaw` capability/runtime exposure，`openclaw` control-plane capability surface
  - Failing test：新增 capability manifest 测试后运行 `zig build test --summary all`（`framework`）
  - Passing test：`framework` 单测通过，`ourclaw` status/capability 输出仍通过回归
  - Regression：`framework` `zig build test --summary all` + `ourclaw` `zig build test --summary all`
  - 完成定义：共享 capability 描述不再散落在业务层拼装

- [ ] **A2. 提炼 shared runtime adapter / stream sink 合同到 framework**
  - 主线落点：`framework/src/runtime/*`、`ourclaw/src/interfaces/*`、`ourclaw/src/domain/stream_output.zig`
  - 参考：`nullclaw` streaming/runtime adapter
  - 完成定义：ourclaw 入口适配层的共享协议部分回抽到 `framework`

### Wave B — session / memory / agent runtime 深化

- [ ] **B1. 完成 session ledger / replay / usage 结构化模型**
  - 主线落点：`ourclaw/src/domain/session_state.zig`、`src/commands/session_get.zig`
  - 参考：`nullclaw` session manager、`openclaw` session/control semantics
  - 验证：domain tests + smoke
  - 完成定义：session snapshot 足以支撑 manager 与恢复场景

- [ ] **B2. 深化 memory 生命周期能力**
  - 主线落点：`ourclaw/src/domain/memory_runtime.zig`、`src/commands/memory_*`
  - 参考：`nullclaw/src/memory/*`
  - 验证：domain tests + migration roundtrip + smoke
  - 完成定义：summary / compact / migrate / retrieval / semantic layer 形成更清晰分层

- [ ] **B3. 深化 agent runtime 策略面**
  - 主线落点：`ourclaw/src/domain/agent_runtime.zig`、`prompt_assembly.zig`
  - 参考：`nullclaw` agent runtime、`openclaw` 路由与控制语义
  - 验证：agent domain tests + smoke
  - 完成定义：provider/tool/memory/session 策略与压缩/路由边界清晰可测

### Wave C — gateway / control-plane 对齐 openclaw

- [ ] **C1. 统一 gateway control-plane contract**
  - 主线落点：`ourclaw/src/runtime/gateway_host.zig`、`src/interfaces/http_adapter.zig`、`src/commands/gateway_*`
  - 参考：openclaw gateway/server/runtime-config
  - 验证：gateway tests + HTTP smoke
  - 完成定义：gateway 状态、reload、stream subscribe、health 字段面稳定

- [ ] **C2. 深化 service / daemon 恢复与运行策略**
  - 主线落点：`ourclaw/src/runtime/service_manager.zig`、`daemon.zig`、`runtime_host.zig`
  - 参考：`nullclaw` service/runtime，openclaw daemon/service
  - 验证：runtime tests
  - 完成定义：service/daemon 不只是 lifecycle，而有恢复、预算、健康策略

- [ ] **C3. 完成 config schema / migration / import 产品化治理**
  - 主线落点：`ourclaw/src/config/*`、`src/runtime/config_runtime_hooks.zig`
  - 参考：openclaw config schema / reload / onboarding
  - 验证：config tests + smoke
  - 完成定义：配置治理成为 control-plane 核心，而不是附属功能

### Wave D — 流协议与入口适配统一

- [ ] **D1. 深化 SSE / WS / bridge / CLI live 控制语义**
  - 主线落点：`ourclaw/src/interfaces/stream_projection.zig`、`stream_websocket.zig`、`cli_adapter.zig`
  - 参考：nullclaw streaming 与 openclaw gateway live 语义
  - 验证：projection tests + smoke
  - 完成定义：ack / pause / resume / backpressure / disconnect / reconnect 更一致

- [ ] **D2. 完成 CLI / HTTP / bridge 命令参数面对齐**
  - 主线落点：`ourclaw/src/interfaces/*`
  - 完成定义：主要命令在三个入口的参数支持一致

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
