# 基于 framework 完成 ourclaw 主线开发 — Tasks

> 说明：以下任务面向未来大模型执行。每项任务都给出主线目标、前置依赖、目标落点、参考文件与完成定义。参考仓只用于理解设计意图，不是实现落点。
>
> 状态校准（2026-03-13）：本任务表已经按当前 `framework/`、`ourclaw/` 与 `ourclaw/docs/planning/session-resume.md` 做过一次现实校准。不要把所有任务都当成“未开始”。当前状态分为：
>
> - `[x]`：第一版已落地，后续如需继续推进，应按“稳定 / 扩展 / 完善”理解
> - `[-]`：第一版已落地，但仍需继续收口、补语义或补真实后端行为
> - `[ ]`：真正未开始

## 阶段 0：对齐主线边界与文档基线

- [x] **T0.1 固化 spec 入口与引用规则**
  - 目标：让后续实现统一引用本 spec，而不是继续散落在多份 planning 文档里。
  - 主线落点：`ourclaw/docs/specs/framework-based-ourclaw/*`
  - 前置依赖：无
  - 参考文件：
    - `README.md`
    - `WORKSPACE_CONTEXT.md`
    - `ourclaw/docs/architecture/overall-design.md`
  - 参考目的：确认主线目录、已有架构判断与文档边界
  - 完成定义：后续任务都能回指本 spec；不再出现“能力该进 framework 还是 ourclaw”这种未决问题
  - 验证：人工检查任务描述是否都带主线落点与参考锚点

## 阶段 1：固化 framework 共享底座

- [x] **T1.1 稳定共享 AppContext 与 dispatcher 能力边界**
  - 目标：确保统一执行主干继续收口在 `framework/`，而不是在 `ourclaw/` 平行复制。
  - 主线落点：
    - `framework/src/runtime/app_context.zig`
    - `framework/src/app/command_dispatcher.zig`
    - `framework/src/runtime/task_runner.zig`
    - `framework/src/runtime/event_bus.zig`
  - 前置依赖：T0.1
  - 参考文件：
    - `framework/src/runtime/app_context.zig`
    - `framework/src/app/command_dispatcher.zig`
    - `openclaw/src/gateway/server.impl.ts`
  - 参考目的：前两者用于延续主线共享实现；后者用于观察产品化 runtime 如何把大量子系统挂到统一网关主干
  - 完成定义：共享 dispatcher / task / event / observer / config hook 的职责边界在代码与文档中保持一致
  - 验证：相关共享模块的接口关系清晰，未引入 claw 业务语义

- [x] **T1.2 稳定并按需扩展共享错误、校验、envelope 契约**
  - 目标：让所有入口与业务命令依赖稳定契约输出。
  - 主线落点：
    - `framework/src/core/error.zig`
    - `framework/src/core/validation/*`
    - `framework/src/contracts/envelope.zig`
  - 前置依赖：T1.1
  - 参考文件：
    - `openclaw/src/gateway/protocol/schema/config.ts`
    - `openclaw/src/gateway/server-runtime-config.ts`
  - 参考目的：看协议模式、字段约束与安全前置检查思路
  - 完成定义：共享错误、响应与输入校验能被 `ourclaw` 命令域直接复用
  - 验证：新增或调整的共享契约能被现有命令与配置链路消费

- [x] **T1.3 稳定共享配置写回与 post-write hook 链路**
  - 目标：让运行时配置修改能稳定向业务层传播，而不是分散写配置。
  - 主线落点：
    - `framework/src/config/pipeline.zig`
    - `framework/src/config/*`
  - 前置依赖：T1.2
  - 参考文件：
    - `openclaw/src/wizard/onboarding.ts`
    - `openclaw/src/gateway/server-runtime-config.ts`
  - 参考目的：看配置变更如何影响运行时启动与网关安全策略
  - 完成定义：共享配置写回接口可稳定支撑 `ourclaw` 运行时 hooks
  - 验证：配置修改后可触发可预期 side-effect 记录

## 阶段 2：收口 ourclaw 业务 AppContext 与 runtime 主干

- [x] **T2.1 稳定 ourclaw 业务 AppContext 装配中心**
  - 目标：把现有 registry、runtime host、service、session、stream、tool orchestration 的装配关系稳定下来。
  - 主线落点：`ourclaw/src/runtime/app_context.zig`
  - 前置依赖：T1.1、T1.3
  - 参考文件：
    - `framework/src/runtime/app_context.zig`
    - `nullclaw/src/root.zig`
    - `openclaw/src/gateway/server.impl.ts`
  - 参考目的：分别参考共享装配模式、Zig 能力总装配方式、产品化 runtime 子系统接线方式
  - 完成定义：`ourclaw` 的业务 registry 与 runtime 依赖关系清晰，可支撑后续 agent/gateway/service 接入
  - 验证：`ourclaw/src/runtime/app_context.zig` 不再承担共享底座职责，只负责业务装配

- [x] **T2.2 固化 runtime host / gateway host / service manager / daemon 边界**
  - 目标：明确长期运行宿主的职责拆分，避免 host、service、daemon 逻辑缠绕。
  - 主线落点：
    - `ourclaw/src/runtime/runtime_host.zig`
    - `ourclaw/src/runtime/gateway_host.zig`
    - `ourclaw/src/runtime/service_manager.zig`
    - `ourclaw/src/runtime/daemon.zig`
  - 前置依赖：T2.1
  - 参考文件：
    - `nullclaw/src/service.zig`
    - `openclaw/src/daemon/service.ts`
    - `openclaw/src/gateway/server.impl.ts`
  - 参考目的：对照 Zig 平台服务管理与产品级 gateway/service 宿主职责拆分
  - 完成定义：运行宿主边界清晰，gateway 与 service 管理不再互相侵入
  - 验证：文档与代码中的职责描述一致
  - 本轮实现（2026-03-13）：
    - `src/runtime/daemon.zig` 收紧为 `service_manager` 的只读投影视图，不再参与生命周期写操作
    - `src/commands/service_install.zig` 去掉重复 install 调用，`service.status` 明确输出 `daemonProjected`
    - `tests/smoke.zig` 补 service/gateway 状态一致性断言
    - 验证：`zig build test --summary all` 通过（107/107）
    - 提交：`7c850af` `固化 runtime 与 daemon 边界`

## 阶段 3：完成 agent runtime 主循环的核心闭环

- [x] **T3.1 扩展 session state 为可支撑 agent turn 的会话模型**
  - 主线落点：`ourclaw/src/domain/session_state.zig`
  - 前置依赖：T2.1
  - 参考文件：
    - `nullclaw/src/memory/root.zig`
    - `openclaw/src/auto-reply/reply/get-reply-run.ts`
    - `openclaw/src/gateway/session-utils.ts`
  - 参考目的：理解会话存储、轮次驱动与产品侧 session 处理语义
  - 完成定义：session 能承载 snapshot / event / summary / usage / tool trace 等最小能力
  - 验证：`session.get` / `session.compact` 相关命令语义更稳定
  - 本轮实现（2026-03-13）：
    - `src/domain/session_state.zig` 新增 provider/model/tool/usage/error 等 turn 级快照字段
    - `src/domain/agent_runtime.zig` 写回 `session.turn.completed`
    - `src/commands/session_get.zig` 直接暴露 richer session snapshot
    - `tests/smoke.zig` 补 session.get 对 provider/tool/latency 的断言
    - 验证：`zig build test --summary all` 通过（108/108）
    - 提交：`47fbc77` `扩展 session turn 快照模型`

- [x] **T3.2 稳定 stream output / stream registry 的统一输出模型**
  - 主线落点：
    - `ourclaw/src/domain/stream_output.zig`
    - `ourclaw/src/runtime/stream_registry.zig`
    - `ourclaw/src/interfaces/stream_projection.zig`
  - 前置依赖：T3.1
  - 参考文件：
    - `nullclaw/src/streaming.zig`
  - 参考目的：参考 Zig 流式事件抽象与过滤/转发方式
  - 完成定义：text/tool/status/error/final 事件具有稳定事件种类与投影路径
  - 验证：stream 事件可同时支撑 session 写入、event bus 广播和接口投影

- [x] **T3.3 稳定 ToolOrchestrator 合约，并补齐 agent runtime 的多步 tool loop**
  - 主线落点：
    - `ourclaw/src/domain/tool_orchestrator.zig`
    - `ourclaw/src/domain/agent_runtime.zig`
    - `ourclaw/src/tools/*`
  - 前置依赖：T3.2
  - 参考文件：
    - `nullclaw/src/tools/root.zig`
    - `openclaw/src/agents/tools/`
  - 参考目的：看 Zig vtable/tool schema 设计与产品化工具治理思路
  - 完成定义：`ToolOrchestrator` 稳定承担工具查找、参数校验、权限检查、执行、结果写回、错误映射；多步 provider → tool → provider loop 明确由 `agent_runtime` 收口，而不是把循环编排职责再次塞回 orchestrator
  - 验证：工具执行不再散落在命令层直调，多步循环职责边界清晰
  - 本轮实现（2026-03-13）：
    - `src/domain/tool_orchestrator.zig` 引入 `SingleInvokeRequest` / `invokeSingle()`，显式标记 `single_invocation` 契约
    - `src/domain/agent_runtime.zig` 抽出 `executeToolRound()`，把多轮 loop、失败写回和 session 快照对齐集中到 runtime
    - 验证：`zig build test --summary all` 通过（109/109）
    - 提交：`0e07cda` `收口工具调用与 agent loop 边界`

- [x] **T3.4 稳固 memory runtime 与 agent runtime 基础闭环**
  - 主线落点：
    - `ourclaw/src/domain/memory_runtime.zig`
    - `ourclaw/src/domain/agent_runtime.zig`
    - `ourclaw/src/providers/*`
  - 前置依赖：T3.1、T3.3
  - 参考文件：
    - `nullclaw/src/memory/root.zig`
    - `nullclaw/src/providers/root.zig`
    - `openclaw/src/auto-reply/reply/get-reply-run.ts`
  - 参考目的：看 Zig memory/provider 边界与产品化 agent 执行主循环
  - 完成定义：形成 request → session → provider → tool → memory → result 的最小闭环
  - 验证：`agent.run` / `agent.stream` 的内部链路语义清晰且可扩展

## 阶段 4：收口 gateway / config / service / cron 等控制平面能力

- [x] **T4.1 稳定 ourclaw gateway 配置与 runtime hook 主线**
  - 主线落点：
    - `ourclaw/src/config/*`
    - `ourclaw/src/runtime/config_runtime_hooks.zig`
    - `ourclaw/src/runtime/gateway_host.zig`
  - 前置依赖：T1.3、T2.2
  - 参考文件：
    - `openclaw/src/gateway/server-runtime-config.ts`
    - `openclaw/src/gateway/protocol/schema/config.ts`
    - `openclaw/src/wizard/onboarding.ts`
  - 参考目的：看 gateway 配置约束、启动前检查与 onboarding 写入逻辑
  - 完成定义：gateway 相关配置具备清晰 schema、运行时解析与 hook 传播路径；与 `T1.3` 的共享配置写回链路保持清晰边界：`T1.3` 负责 `framework/src/config/*`，本任务负责 `ourclaw` 业务 hook
  - 验证：配置变更可映射到 gateway host 状态变化

- [x] **T4.2 完善 daemon / service 生命周期控制**
  - 主线落点：
    - `ourclaw/src/runtime/service_manager.zig`
    - `ourclaw/src/runtime/daemon.zig`
    - `ourclaw/src/commands/service_*`
  - 前置依赖：T2.2
  - 参考文件：
    - `nullclaw/src/service.zig`
    - `openclaw/src/daemon/service.ts`
  - 参考目的：对照 Zig 与 Node 两种平台服务管理职责模型
  - 完成定义：service install/start/stop/restart/status 生命周期接口统一
  - 验证：service 命令族与 runtime host / daemon 语义一致
  - 本轮实现（2026-03-13）：
    - `src/runtime/service_manager.zig` 把 install/start/stop/restart 收口为有返回值的幂等生命周期动作
    - `src/commands/service_*.zig` 增加 `changed` / `stopApplied` / `startApplied` 等可观察字段
    - `tests/smoke.zig` 覆盖重复 install/start/stop 与 restart 语义
    - 验证：`zig build test --summary all` 通过（110/110）
    - 提交：`521dfbe` `完善 service manager 生命周期语义`
    - 提交：`8e32bc6` `统一 service 生命周期命令输出`
    - 提交：`5a6c795` `补充 service lifecycle smoke 覆盖`

- [x] **T4.3 补齐 cron / heartbeat / background runtime 基础语义**
  - 主线落点：
    - `ourclaw/src/runtime/cron.zig`
    - `ourclaw/src/runtime/heartbeat.zig`
    - `ourclaw/src/commands/cron_*`
  - 前置依赖：T2.2、T3.4
  - 参考文件：
    - `openclaw/src/cron/service.ts`
  - 参考目的：理解长期调度服务与运行时状态联动方式
  - 完成定义：cron / heartbeat 不再只是占位结构，而具备明确状态、调度与观测语义
  - 验证：相关命令的状态输出与 runtime 内部对象一致
  - 本轮实现（2026-03-13）：
    - `src/runtime/heartbeat.zig` 基于 stale window 判断健康，而不是只看是否 beat 过
    - `src/runtime/cron.zig` 区分 tick 次数与实际执行 job 次数，并加入最小 schedule 间隔判断
    - `src/commands/cron_tick.zig` 去掉重复 heartbeat 计数，`cron.list` / `heartbeat.status` 输出更多运行态字段
    - `tests/smoke.zig` 覆盖 tickCount / heartbeatBeatCount / staleAfterMs 等字段
    - 验证：`zig build test --summary all` 通过（112/112）
    - 提交：`1960707` `补齐 cron 与 heartbeat 运行时语义`
    - 提交：`9e4d108` `统一 cron 与 heartbeat 命令状态输出`
    - 提交：`3ef7a1d` `补充 cron heartbeat smoke 覆盖`

## 阶段 5：完成入口适配与统一执行闭环

- [x] **T5.1 保持 CLI / Bridge / HTTP 入口收口到统一 dispatcher，并补齐剩余协议差异**
  - 主线落点：
    - `ourclaw/src/interfaces/cli_adapter.zig`
    - `ourclaw/src/interfaces/bridge_adapter.zig`
    - `ourclaw/src/interfaces/http_adapter.zig`
  - 前置依赖：T1.1、T3.4、T4.1
  - 参考文件：
    - `ourclaw/docs/architecture/runtime-pipeline.md`
    - `openclaw/src/gateway/server.impl.ts`
    - `nullclaw/src/websocket.zig`
  - 参考目的：对齐统一执行主干、gateway 入口处理和 Zig websocket 边界
  - 完成定义：接口层不再各自维护一套业务处理主链路
  - 验证：入口适配层只负责 request translation / projection，不直接承担业务逻辑

- [x] **T5.2 扩展并稳定观测、日志、诊断与事件投影**
  - 主线落点：
    - `framework/src/observability/*`
    - `ourclaw/src/commands/logs_recent.zig`
    - `ourclaw/src/commands/diagnostics_*`
    - `ourclaw/src/commands/events_*`
  - 前置依赖：T5.1
  - 参考文件：
    - `nullclaw/src/observability.zig`
    - `openclaw/src/logging/`
    - `openclaw/src/gateway/ws-log.ts`
  - 参考目的：对齐观察者、结构化日志和 gateway 日志投影思路
  - 完成定义：日志、事件、诊断路径形成统一运行时观测面
  - 验证：logs / diagnostics / events 命令族可以回溯统一运行时主干信息

## 阶段 6：回归整理与文档回写

- [x] **T6.1 为每个阶段回填实现日志与落点回写**
  - 目标：避免未来模型重复实现同一能力。
  - 主线落点：
    - `ourclaw/docs/specs/framework-based-ourclaw/*`
    - 相关实现文档与实现日志
  - 前置依赖：任一阶段完成后执行
  - 参考文件：本 spec 三件套
  - 参考目的：保证实现与规格保持双向映射
  - 完成定义：每个已完成任务都能回写“改了哪些文件、为什么、如何验证、参考了什么”
  - 验证：后续模型只看 spec 与实现日志即可快速定位上下文
  - 本轮回写（2026-03-13）：
    - 已把 `T2.2 / T3.1 / T3.3 / T4.2 / T4.3` 的真实状态改为 `[x]`
    - 已补每个任务的实现摘要、关键文件、验证结果与提交哈希
    - 已同步把本轮进展写回 `ourclaw/docs/planning/session-resume.md`

## 下一里程碑：M2 产品化 runtime 与真实集成第一阶段

> 里程碑目标：当前 `ourclaw` 已完成一版可运行主干。M2 不再重做基础架构，而是优先补齐**可恢复流式协议、真实长期运行宿主、可运维配置治理、以及更接近产品级的 agent/provider/tool 语义**，以缩短与 `openclaw` 的实际产品能力差距。
>
> 里程碑边界：
>
> - **应做**：协议恢复、长期运行宿主、配置加载/迁移/compat import 深化、execution 级观测关联、prompt/profile/session/memory 真实语义、现有 provider/tool 生产化收口
> - **暂不做**：完整 GUI/product workflow、voice、大量新 channel 扩展、skills/mcp/tunnel/hardware 的大面积新域集成、以及把 `openclaw` 全量功能一口气平移

### 阶段 M2-A：协议恢复与长期运行宿主

- [x] **M2-01 收口 execution reconnect / resume**
  - 目标：让 SSE / WebSocket / bridge 的重连能重新附着同一 `execution_id`，而不是重复触发新的 agent run。
  - 主线落点：
    - `ourclaw/src/interfaces/stream_projection.zig`
    - `ourclaw/src/runtime/stream_registry.zig`
    - `ourclaw/src/domain/session_state.zig`
    - `ourclaw/src/domain/agent_runtime.zig`
  - 前置依赖：当前 T0-T6 已完成
  - 参考文件：
    - `openclaw/src/gateway/server-ws-runtime.ts`
    - `openclaw/src/gateway/server.agent.gateway-server-agent-a.test.ts`
    - `openclaw/src/gateway/session-utils.ts`
    - `nullclaw/src/streaming.zig`
  - 参考目的：看 execution attach/reconnect、session 恢复、流式 replay / runtime cursor 的产品化处理方式
  - 完成定义：同一执行可被 replay / resume / reconnect 附着，且不会重复触发 provider/tool 执行
  - 验证：`zig build test --summary all`；补 happy-path / invalid attach / disconnect-resume 三类测试
  - 本轮实现（2026-03-13）：
    - `src/interfaces/stream_projection.zig` 已把 Bridge / WebSocket 的 reconnect 语义补齐到与 SSE 对齐
    - Bridge 现在支持：`replay_only`、`execution_id:after_seq` 形式的 execution cursor resume、以及对 running execution 的重附着
    - WebSocket 现在支持：legacy `last_event_id` replay-only、running execution resume、以及 execution cursor resume
    - 已新增 stream projection 级测试，覆盖 bridge replay-only、bridge execution resume、ws replay-only
    - 验证：`zig build test --summary all` 通过（115/115）

- [x] **M2-02 统一 CLI / Bridge / HTTP 的 auth / route / error 映射表**
  - 目标：保证同一命令跨入口的 authority、accepted/error/success 语义一致，减少入口层协议漂移。
  - 主线落点：
    - `ourclaw/src/interfaces/cli_adapter.zig`
    - `ourclaw/src/interfaces/bridge_adapter.zig`
    - `ourclaw/src/interfaces/http_adapter.zig`
    - `framework/src/contracts/envelope.zig`
  - 前置依赖：M2-01
  - 参考文件：
    - `openclaw/src/gateway/server.impl.ts`
    - `openclaw/src/gateway/test-http-response.ts`
    - `openclaw/src/gateway/server.auth.shared.ts`
  - 参考目的：看统一网关入口如何把权限、错误、accepted/result 做成稳定契约
  - 完成定义：跨入口的 accepted / success / app_error / HTTP status / bridge envelope 规则一致
  - 验证：`zig build test --summary all`；补每种入口一条 happy-path 和一条 failure-path 对照测试
  - 本轮实现（2026-03-13）：
    - `src/interfaces/cli_adapter.zig` 的非流式输出已改为统一 protocol envelope（`ok/result/error/meta`），不再走更旧的裸 JSON 成功体
    - `src/interfaces/bridge_adapter.zig` 已补 bridge 成功路径对 `ok/result/meta` 结构的断言，确认和 CLI / HTTP 对齐
    - `src/interfaces/http_adapter.zig` 已把 `/v1/agent/stream/ws` 的 upgrade required 与未知 route 的 404 错误改成统一 protocol error envelope，并带 `meta.requestId`
    - 已新增/更新 adapter 测试，覆盖 CLI / Bridge / HTTP 的 protocol envelope 一致性与 HTTP 特殊错误路径
    - 验证：`zig build test --summary all` 通过（116/116）

- [x] **M2-03 让 gateway_host 成为真实 listener 宿主**
  - 目标：让 `gateway_host` 不只是状态骨架，而是真正持有监听端口、启动/停止/reload 与 listener 状态。
  - 主线落点：
    - `ourclaw/src/runtime/gateway_host.zig`
    - `ourclaw/src/runtime/runtime_host.zig`
    - `ourclaw/src/commands/gateway_*`
  - 前置依赖：M2-02
  - 参考文件：
    - `openclaw/src/gateway/server.impl.ts`
    - `openclaw/src/gateway/server-runtime-state.ts`
    - `openclaw/src/gateway/server.reload.test.ts`
    - `nullclaw/src/websocket.zig`
  - 参考目的：看 listener 托管、runtime state、reload 与 Zig transport 边界
  - 完成定义：gateway.start/stop/status/reload 反映真实 listener 运行态，而非仅计数变化
  - 验证：`zig build test --summary all`；补 listener lifecycle 与 reload 测试
  - 本轮实现（2026-03-13）：
    - `src/runtime/gateway_host.zig` 已补 `listener_ready`、`active_connections`、`reload_count`、`last_reloaded_ms`
    - `gateway_host` 已新增 `reload()`，并在 listener bind 成功后标记 `listener_ready`
    - `src/runtime/runtime_host.zig` 已新增 `reloadGateway()`，并把 `gateway_listener_ready` 暴露到 runtime status
    - 已新增 `src/commands/gateway_reload.zig`，并在 `root.zig` / `http_adapter.zig` 注册 `gateway.reload`
    - `gateway.status` 与 smoke 测试已补 listener/reload 字段断言
    - 验证：`zig build test --summary all` 通过（117/117）

- [ ] **M2-04 把 service_manager / daemon 推进到后台运行模型**
  - 目标：让 install/start/stop/restart/status 能表达后台运行态、锁/PID、autostart/restart budget 等更接近真实宿主的语义。
  - 主线落点：
    - `ourclaw/src/runtime/service_manager.zig`
    - `ourclaw/src/runtime/daemon.zig`
    - `ourclaw/src/commands/service_*`
  - 前置依赖：M2-03
  - 参考文件：
    - `openclaw/src/daemon/service.ts`
    - `openclaw/README.md`
    - `nullclaw/src/service.zig`
  - 参考目的：看前台/后台 service 模式、守护状态与可运维生命周期模型
  - 完成定义：service/daemon status 可反映真实后台运行模型，而不只是启动计数器
  - 验证：`zig build test --summary all`；补 install/start/stop/restart/status + stale-process/failure-path 测试

### 阶段 M2-B：配置治理与 execution 级观测

- [ ] **M2-05 补共享配置加载栈（文件 + env + object/array）**
  - 目标：把配置从“命令可写”推进到“产品可运营”，支持文件加载、环境变量覆盖、复杂对象与数组解析。
  - 主线落点：
    - `framework/src/config/loader.zig`
    - `framework/src/config/parser.zig`
    - `framework/src/config/defaults.zig`
    - `ourclaw/src/config/runtime.zig`
  - 前置依赖：M2-04
  - 参考文件：
    - `openclaw/src/gateway/server-runtime-config.ts`
    - `openclaw/src/gateway/server.config-apply.test.ts`
    - `openclaw/src/wizard/onboarding.gateway-config.ts`
    - `nullclaw/README.md`
  - 参考目的：看 runtime config 的应用、bootstrap defaults、环境覆盖与 onboarding 写回落地方式
  - 完成定义：可从文件/环境稳定构造 runtime snapshot，并支持复杂字段解析
  - 验证：`zig build test --summary all`；补 file/env/object/array 的 happy-path 与 invalid config 测试

- [ ] **M2-06 深化 field registry / migration / compat import**
  - 目标：补 `schema versioning`、`migration_aliases`、source-specific importer 与更完整 change log/post-write summary。
  - 主线落点：
    - `ourclaw/src/config/field_registry.zig`
    - `ourclaw/src/config/migration.zig`
    - `ourclaw/src/compat/config_import.zig`
    - `ourclaw/src/runtime/config_runtime_hooks.zig`
  - 前置依赖：M2-05
  - 参考文件：
    - `openclaw/src/gateway/server.legacy-migration.test.ts`
    - `openclaw/src/wizard/onboarding.finalize.ts`
    - `nullclaw/README.md`
  - 参考目的：看版本迁移、向后兼容导入与最终写回摘要模型
  - 完成定义：compat import / migration preview / apply / post-write summary 更接近真实产品流程
  - 验证：`zig build test --summary all`；补 migration alias / compat import / regression 测试

- [ ] **M2-07 打通 execution 级 observability 关联键**
  - 目标：让 `execution_id / session_id / subscription_id` 能贯通日志、事件、metrics 与 replay cursor。
  - 主线落点：
    - `framework/src/observability/*`
    - `ourclaw/src/commands/events_*`
    - `ourclaw/src/commands/observer_*`
    - `ourclaw/src/commands/metrics_*`
    - `ourclaw/src/interfaces/stream_projection.zig`
  - 前置依赖：M2-06
  - 参考文件：
    - `openclaw/src/gateway/ws-log.ts`
    - `openclaw/src/gateway/server-startup-log.ts`
    - `nullclaw/src/observability.zig`
  - 参考目的：看 execution/session/subscription 级日志和事件如何贯通控制面
  - 完成定义：logs / events / metrics / observer 能围绕同一个 execution 追踪完整链路
  - 验证：`zig build test --summary all`；补 one-execution correlation 测试

### 阶段 M2-C：agent / memory / provider-tool 产品语义

- [ ] **M2-08 实现 prompt profile / identity-driven prompt assembly**
  - 目标：让 system prompt 不再只是固定拼接，而是受 channel、identity、session snapshot、response mode 共同驱动。
  - 主线落点：
    - `ourclaw/src/domain/prompt_assembly.zig`
    - `ourclaw/src/domain/agent_runtime.zig`
    - `ourclaw/src/channels/root.zig`
  - 前置依赖：M2-07
  - 参考文件：
    - `openclaw/README.md`
    - `openclaw/src/gateway/sessions-patch.ts`
    - `openclaw/src/gateway/session-utils.ts`
    - `nullclaw/README.md`
  - 参考目的：看 session patch / identity / mode 如何影响 agent prompt 与响应语义
  - 完成定义：prompt profile / identity / session mode 会真实改变 provider 请求内容
  - 验证：`zig build test --summary all`；补多 profile / 多 identity / mode regression 测试

- [ ] **M2-09 收口 retrieval / embeddings / memory ranking**
  - 目标：让 memory recall 不再只是最小 summary/retrieve，而具备 embeddings 抽象、检索排序、迁移与写回闭环。
  - 主线落点：
    - `ourclaw/src/domain/memory_runtime.zig`
    - `ourclaw/src/providers/*`
    - `ourclaw/src/config/*`
  - 前置依赖：M2-08
  - 参考文件：
    - `openclaw/README.md`
    - `openclaw/src/gateway/server-startup-memory.ts`
    - `nullclaw/src/memory/root.zig`
  - 参考目的：看 memory 启动、embedding/retrieval 语义与 Zig 侧 memory 抽象边界
  - 完成定义：recall 具备排名、embedding provider 接线与更稳定写回闭环
  - 验证：`zig build test --summary all`；补 retrieval ranking / migration / append-recall 回归测试

- [ ] **M2-10 把现有 provider/tool 做到生产语义第一阶段**
  - 目标：优先深化现有 provider/tool，而不是继续扩更多新域；补 timeout / cancel / retry / budget / risk gating / streaming failure 映射 / audit 事件。
  - 主线落点：
    - `ourclaw/src/providers/*`
    - `ourclaw/src/tools/*`
    - `ourclaw/src/domain/tool_orchestrator.zig`
    - `ourclaw/src/domain/agent_runtime.zig`
  - 前置依赖：M2-09
  - 参考文件：
    - `openclaw/src/gateway/tools-invoke-http.ts`
    - `openclaw/src/gateway/tools-invoke-http.test.ts`
    - `openclaw/src/gateway/system-run-approval-binding.test.ts`
    - `nullclaw/src/tools/root.zig`
    - `nullclaw/src/providers/root.zig`
  - 参考目的：看工具调用、审批绑定、provider/tool 错误映射与 Zig 合约边界
  - 完成定义：现有 provider/tool 具备更接近生产的超时、取消、预算、审计和错误语义
  - 验证：`zig build test --summary all`；补 timeout / cancel / denied / retry / budget 回归测试
