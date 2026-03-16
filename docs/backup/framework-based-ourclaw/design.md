# 基于 framework 完成 ourclaw 主线开发 — Design

> 使用说明（2026-03-13）：本设计文档已经和 `tasks.md` 做过一次状态对齐。文中出现“目标架构 / 能力点”时，不应默认理解为“尚未实现”，而应结合当前代码理解为“已落第一版的部分继续稳定和深化，未落地的部分再继续补齐”。
>
> 说明（2026-03-16）：本文件现在主要承担 phase-1 baseline 设计说明角色；新的 active spec 已切换到 `ourclaw/docs/specs/reference-aligned-ourclaw/`。

## 1. 设计目标

本设计的核心不是重写一份“大总体架构”，而是把现有主线仓状态、参考仓价值和未来实施顺序收口成一个可执行的落点设计。

设计回答以下问题：

1. 当前 `framework` 与 `ourclaw` 各自已经到什么阶段
2. 哪些能力属于共享层，哪些能力属于业务层
3. `nullclaw` 与 `openclaw` 分别应该被怎样参考
4. 后续能力建设应该以什么模块边界推进

## 2. 当前基线

### 2.1 framework 当前基线

`framework/` 已经具备共享运行时主干，不再是空骨架。当前重点基线包括：

- `framework/src/runtime/app_context.zig`：共享依赖装配中心
- `framework/src/app/command_dispatcher.zig`：统一命令分发主干
- `framework/src/runtime/task_runner.zig`：异步任务执行
- `framework/src/runtime/event_bus.zig`：事件总线
- `framework/src/config/pipeline.zig`：配置写回与后置钩子
- `framework/src/core/validation/*`：输入与配置校验基础能力
- `framework/src/core/error.zig`、`framework/src/contracts/envelope.zig`：统一错误与响应封装

结论：`framework` 已适合作为共享底座继续演进，但不应吸收 `ourclaw` 的业务语义。

### 2.2 ourclaw 当前基线

`ourclaw/` 已经具备业务主线第一版骨架，当前关键文件包括：

- `ourclaw/src/runtime/app_context.zig`
- `ourclaw/src/runtime/runtime_host.zig`
- `ourclaw/src/runtime/gateway_host.zig`
- `ourclaw/src/runtime/service_manager.zig`
- `ourclaw/src/runtime/daemon.zig`
- `ourclaw/src/domain/agent_runtime.zig`
- `ourclaw/src/domain/memory_runtime.zig`
- `ourclaw/src/domain/session_state.zig`
- `ourclaw/src/domain/stream_output.zig`
- `ourclaw/src/domain/tool_orchestrator.zig`
- `ourclaw/src/providers/root.zig`
- `ourclaw/src/tools/root.zig`
- `ourclaw/src/channels/root.zig`

结论：`ourclaw` 已进入“有真实业务骨架 + 局部实现”的阶段，下一步不是再写一套平行结构，而是把现有骨架收口成稳定主干。

### 2.3 当前状态校准

结合 `ourclaw/docs/planning/session-resume.md` 与当前代码，可把当前状态进一步理解为：

- **已完成第一版并适合继续稳定的能力**：
  - `framework` 共享 `AppContext` / dispatcher / task runner / event bus / error / validation / envelope / config pipeline
  - `ourclaw` 业务 `AppContext`
  - `stream_output` / `stream_registry` 统一流式输出主线
  - `memory_runtime` + `agent_runtime` 最小闭环
  - `ourclaw` gateway config + runtime hook 主线
  - CLI / Bridge / HTTP 接入统一 dispatcher
  - logs / diagnostics / events / observer / metrics 查询面

- **已落第一版但仍需继续收口的能力**：
  - `runtime_host` / `gateway_host` / `service_manager` / `daemon` 的职责边界
  - `session_state` 的结构化会话模型
  - `ToolOrchestrator` 与 `agent_runtime` 之间的多步 tool loop 职责划分
  - cron / heartbeat / background runtime 的真实长期运行语义
  - 实现日志与 spec 回写机制

- **当前不应误判的点**：
  - `ToolOrchestrator` 已承担工具执行合约，但多步 `provider → tool → provider` loop 当前主要收口在 `ourclaw/src/domain/agent_runtime.zig`
  - `framework/src/config/*` 的共享配置写回链路，与 `ourclaw/src/runtime/config_runtime_hooks.zig` 的业务 hook 链路已经分层存在，后续应避免再把两者写成同一项工作
  - `runtime_host` / `gateway_host` / `service_manager` / `daemon` / `cron` / `heartbeat` 均已有第一版骨架，不应再按“从零搭建”理解

## 3. 设计原则

1. **共享能力先进入 framework**：日志、校验、错误、事件、任务、配置写回等通用能力继续沉淀在 `framework/`。
2. **业务能力进入 ourclaw**：agent/provider/channel/tool/memory/gateway/stream/service 等都属于 `ourclaw/`。
3. **统一执行主干优先**：入口适配层不能绕过统一 dispatcher 与 runtime。
4. **参考仓只作为锚点，不作为迁移目标**：不得把 `nullclaw/` 或 `openclaw/` 当作直接落地点。
5. **设计文档必须服务后续大模型执行**：不能只写概念，要写落点、参考和验证。

## 4. 参考策略

### 4.1 nullclaw 的参考价值

`nullclaw/` 更适合作为 **Zig 结构与能力边界参考**，重点看：

- runtime 组织
- vtable / registry / observer 风格
- provider / tool / memory / streaming / service 的 Zig 侧实现边界

### 4.2 openclaw 的参考价值

`openclaw/` 更适合作为 **产品化语义与工程治理参考**，重点看：

- gateway / config / wizard / daemon / cron / control-plane 的职责拆分
- 配置治理与安全约束
- 产品化运行时组织方式

### 4.3 参考写法规则

后续所有设计点使用统一格式：

- **主线落点**：应写到哪里
- **参考文件**：看哪些文件
- **参考目的**：为什么看它

禁止只写“参考 nullclaw/openclaw 实现”。

## 5. 能力点映射表

| 能力点 | 主线落点 | 原因 | 参考锚点 |
|---|---|---|---|
| 共享 AppContext / dispatcher / task runner / event bus | `framework/src/runtime/*`、`framework/src/app/*` | 跨应用复用，不带业务语义 | `framework/src/runtime/app_context.zig`、`framework/src/app/command_dispatcher.zig` |
| 统一错误与响应 envelope | `framework/src/core/error.zig`、`framework/src/contracts/envelope.zig` | 应作为所有入口共用契约 | `openclaw/src/gateway/protocol/schema/config.ts`（协议约束思路） |
| ourclaw 业务 AppContext 装配 | `ourclaw/src/runtime/app_context.zig` | 负责把业务 registry 与 runtime 组合到主线 | `framework/src/runtime/app_context.zig`、`nullclaw/src/root.zig` |
| agent runtime 主循环 | `ourclaw/src/domain/agent_runtime.zig` | 业务核心，不应进入 framework | `nullclaw/src/streaming.zig`、`openclaw/src/auto-reply/reply/get-reply-run.ts` |
| memory runtime / session state | `ourclaw/src/domain/memory_runtime.zig`、`ourclaw/src/domain/session_state.zig` | 带会话与记忆语义 | `nullclaw/src/memory/root.zig`、`openclaw/src/gateway/session-utils.ts` |
| stream output / stream registry | `ourclaw/src/domain/stream_output.zig`、`ourclaw/src/runtime/stream_registry.zig` | 属于业务输出投影 | `nullclaw/src/streaming.zig` |
| provider registry 与 provider runtime | `ourclaw/src/providers/*`、`ourclaw/src/domain/agent_runtime.zig` | 模型能力属于业务层 | `nullclaw/src/providers/root.zig`、`openclaw/src/agents/models-config.ts` |
| tool registry 与 tool orchestration | `ourclaw/src/tools/*`、`ourclaw/src/domain/tool_orchestrator.zig` | 工具能力属于业务层 | `nullclaw/src/tools/root.zig`、`openclaw/src/agents/tools/` |
| channel registry | `ourclaw/src/channels/*` | 属于业务接入语义 | `nullclaw/src/channels/*`、`openclaw/src/channels/plugins/index.js` |
| gateway host / runtime host | `ourclaw/src/runtime/gateway_host.zig`、`ourclaw/src/runtime/runtime_host.zig` | ourclaw 对外控制平面入口 | `nullclaw/src/websocket.zig`、`openclaw/src/gateway/server.impl.ts`、`openclaw/src/gateway/server-runtime-config.ts` |
| gateway config schema / hooks / reload | `ourclaw/src/config/*` + `ourclaw/src/runtime/config_runtime_hooks.zig` | 业务级配置治理与运行时联动 | `openclaw/src/gateway/protocol/schema/config.ts`、`openclaw/src/gateway/server-runtime-config.ts`、`openclaw/src/wizard/onboarding.ts` |
| daemon / service 管理 | `ourclaw/src/runtime/service_manager.zig`、`ourclaw/src/runtime/daemon.zig` | 跨平台 runtime 宿主控制 | `nullclaw/src/service.zig`、`openclaw/src/daemon/service.ts` |
| cron / heartbeat / background runtime | `ourclaw/src/runtime/cron.zig`、`ourclaw/src/runtime/heartbeat.zig` | 长期运行能力属于业务 runtime | `openclaw/src/cron/service.ts` |
| mcp / tunnel / peripheral / hardware registry | `ourclaw/src/domain/*` | 明显属于业务扩展域 | `openclaw/src/acp/runtime/registry.ts`、`nullclaw/src/tools/root.zig` |

补充说明：其中多项能力当前已经不是“待建设”，而是“第一版已存在，后续继续稳定/扩展”。后续执行请以 `tasks.md` 中的 `[x] / [-] / [ ]` 状态为准。

## 6. 目标架构

### 6.1 framework 层职责

`framework/` 负责：

- 统一 `AppContext`
- 统一 `CommandDispatcher`
- 统一 `TaskRunner`
- 统一 `EventBus`
- 统一 `Observer`
- 统一 `ConfigWritePipeline`
- 统一错误模型与 envelope

### 6.2 ourclaw 层职责

`ourclaw/` 负责：

- 注册与装配 provider/channel/tool/memory/skill/mcp/tunnel/hardware 等业务 registry
- 提供 agent runtime 主循环
- 提供 session / stream / tool orchestration / memory runtime
- 提供 gateway / daemon / service / cron 等长期运行宿主能力
- 提供 CLI / Bridge / HTTP 等业务接口适配层

补充说明：当前这些职责大多已经有第一版落点。后续工作的重点，不是再次复制一套平行结构，而是围绕这些既有落点继续补齐更完整业务语义。

## 7. 关键数据流

目标数据流为：

1. `interfaces/*` 将外部请求转成统一请求模型
2. `framework` dispatcher 完成统一校验、authority、日志、事件、任务接线
3. `ourclaw` handler 或 agent runtime 处理业务逻辑
4. 业务运行期间通过 `stream_output`、`event_bus`、`observer` 发射结构化过程信息
5. 最终结果通过统一 envelope 或流式投影返回

当前状态说明：该数据流的最小闭环已经存在，尤其是 `agent_runtime`、`memory_runtime`、`stream_output`、`stream_registry` 与 `interfaces/stream_projection.zig` 已形成第一版联动。后续应主要补协议完整性、恢复/重连语义与更真实的业务后端集成。

## 8. 失败与安全策略

1. 所有入口禁止绕过统一校验与错误映射
2. tool 执行必须进入 `ToolOrchestrator`，不能在命令层随意直调
3. provider / gateway / service 的配置变更必须通过统一配置与 hook 链路传播
4. manager 消费面如需引入，必须另开子 spec，不应混入本 spec 主线

## 9. 验证方案

后续实现应按以下层次验证：

1. `framework` 层：共享契约、dispatcher、task runner、config pipeline 的单元与集成验证
2. `ourclaw` 层：agent runtime、session/memory/stream/tool orchestrator 的域级验证
3. 入口层：CLI / Bridge / HTTP / daemon 的统一执行主干验证
4. 文档层：每次新增任务都应能回指本 spec 的落点与参考锚点
