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

- [-] **T2.2 固化 runtime host / gateway host / service manager / daemon 边界**
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

## 阶段 3：完成 agent runtime 主循环的核心闭环

- [-] **T3.1 扩展 session state 为可支撑 agent turn 的会话模型**
  - 主线落点：`ourclaw/src/domain/session_state.zig`
  - 前置依赖：T2.1
  - 参考文件：
    - `nullclaw/src/memory/root.zig`
    - `openclaw/src/auto-reply/reply/get-reply-run.ts`
    - `openclaw/src/gateway/session-utils.ts`
  - 参考目的：理解会话存储、轮次驱动与产品侧 session 处理语义
  - 完成定义：session 能承载 snapshot / event / summary / usage / tool trace 等最小能力
  - 验证：`session.get` / `session.compact` 相关命令语义更稳定

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

- [-] **T3.3 稳定 ToolOrchestrator 合约，并补齐 agent runtime 的多步 tool loop**
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

- [-] **T4.2 完善 daemon / service 生命周期控制**
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

- [-] **T4.3 补齐 cron / heartbeat / background runtime 基础语义**
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

- [-] **T6.1 为每个阶段回填实现日志与落点回写**
  - 目标：避免未来模型重复实现同一能力。
  - 主线落点：
    - `ourclaw/docs/specs/framework-based-ourclaw/*`
    - 相关实现文档与实现日志
  - 前置依赖：任一阶段完成后执行
  - 参考文件：本 spec 三件套
  - 参考目的：保证实现与规格保持双向映射
  - 完成定义：每个已完成任务都能回写“改了哪些文件、为什么、如何验证、参考了什么”
  - 验证：后续模型只看 spec 与实现日志即可快速定位上下文
