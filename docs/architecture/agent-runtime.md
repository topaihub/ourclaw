# ourclaw Agent Runtime 详细设计

## 1. 目标与范围

本文档定义 `ourclaw` 面向完整业务版的 agent runtime 主链路，目标是把当前已经存在的共享运行时骨架、最小命令域、最小 session/stream/tool orchestration，继续收口成一个真正可执行的 agent 系统。

本文档覆盖：

- agent 运行时核心对象
- request → session → prompt → provider → tool → memory 主循环
- 流式输出与会话状态接线
- tool orchestration 与安全边界
- 同步/异步命令与 agent loop 的关系
- 故障、取消、超时与恢复策略

> 当前已落实现入口主要在 `framework/src/runtime/app_context.zig`、`framework/src/app/command_dispatcher.zig`、`framework/src/runtime/task_runner.zig`、`ourclaw/src/runtime/app_context.zig`、`ourclaw/src/domain/session_state.zig`、`ourclaw/src/domain/stream_output.zig`、`ourclaw/src/domain/tool_orchestrator.zig`。截至 2026-03-11，这些实现还只是第一版骨架，不等于完整 agent runtime。

## 2. 设计目标

完整业务版的 agent runtime 必须满足：

1. 命令入口、长期运行入口、channel 入口都能汇聚到统一 agent 主循环
2. session state、stream output、tool 调用、provider 输出可在同一条链路中追踪
3. agent loop 可被取消、超时、中断、恢复
4. 工具调用、memory 写回、事件广播、日志、metrics 都是主循环内建能力，不是外围补丁
5. handler 与 agent loop 可以共存：命令域命令走 dispatcher，面向自然语言的 agent turn 走 agent runtime

## 3. 核心对象

### 3.1 AppContext

完整业务版中，`AppContext` 不只是运行时依赖容器，还应成为业务容器。建议最终持有：

- allocator
- logger / observer / event_bus / metrics
- task_runner
- command_registry
- config_store / config_change_log / config hooks
- security_policy / secret_store
- provider_registry
- channel_registry
- tool_registry
- memory_runtime
- session_store
- stream_output
- tool_orchestrator
- agent_runtime

当前状态：

- `framework/src/runtime/app_context.zig` 已装配共享运行时依赖
- `ourclaw/src/runtime/app_context.zig` 已装配业务 registry、session、stream、tool orchestrator 与最小命令域
- 尚未装配 memory runtime、真实 provider/channel/tool 实现、长期运行 host

### 3.2 RequestContext

每次 agent 请求都应具备：

- `request_id`
- `trace_id`
- `span_id`
- `source`
- `authority`
- `timeout_ms`
- `session_id`
- `channel_id`
- `user_id`

对于命令请求，`session_id` 可以为空；对于 channel / agent 对话请求，`session_id` 必须稳定。

### 3.3 SessionContext

`SessionContext` 是 agent 主循环的会话态对象，建议包含：

- `session_id`
- `history` 摘要
- `memory_refs`
- `channel_id`
- `user_identity`
- `active_provider`
- `stream_state`

当前 `ourclaw/src/domain/session_state.zig` 只具备最小事件存储，完整版需要扩展为会话快照与增量写回模型。

### 3.4 AgentTurnContext

每一轮 agent turn 建议构造成专用上下文：

- `app`
- `request`
- `session`
- `logger`
- `provider`
- `tool_orchestrator`
- `memory_runtime`
- `stream_output`

它应是 provider 调用、tool loop、memory 读写、事件发射的最小执行边界。

## 4. 完整 agent 主循环

建议完整链路如下：

1. 入口 adapter 解析用户输入
2. 生成 `RequestContext`
3. 解析/创建 `SessionContext`
4. 加载 memory 与会话摘要
5. 组装 prompt / messages / tools / response mode
6. 选择 provider
7. 发起 provider 调用（同步或流式）
8. 处理 provider 输出
9. 若 provider 产生 tool calls，则进入 tool orchestration loop
10. 将 tool 结果写回 session 与 stream
11. 必要时继续下一轮 provider 调用
12. 结束后写入 memory / diagnostics / usage / event
13. 返回最终结果或 task acceptance

## 5. Provider 调用模型

完整业务版建议 provider 调用统一落在 `providers/` registry 后的 runtime abstraction，而不是在命令层直接拼 JSON 请求。

建议 provider runtime 能力分层：

- `chat_once`
- `chat_stream`
- `supports_native_tools`
- `supports_images`
- `supports_audio`
- `health_check`

完整版 provider 输出需要统一映射为：

- text delta
- tool call delta
- tool call closed
- final response
- usage summary
- error

## 6. Tool Orchestration 设计

完整业务版的 `ToolOrchestrator` 不应只做“invoke 一次工具然后写 stream”，而应支持：

- tool lookup
- authority / security policy 检查
- 参数 schema 校验
- sync / async tool 执行
- tool 生命周期事件
- tool 结果写入 session state
- tool 错误映射到 `AppError`
- 多步 tool loop

建议执行顺序：

1. 校验 tool id 是否注册
2. 校验 authority / policy
3. 校验参数结构
4. 执行 tool
5. 记录 observer/event/log
6. 将结果追加到 session 与 stream
7. 返回给 agent loop 继续推理

## 7. Stream Output 设计

`StreamOutput` 应成为完整 agent runtime 的标准输出面，而不是仅供某个 adapter 使用。

建议统一事件种类：

- `text.delta`
- `text.done`
- `tool.call.started`
- `tool.call.delta`
- `tool.call.finished`
- `tool.result`
- `status.update`
- `error`
- `final.result`

完整版要求：

- stream 事件必须写入 `session_store`
- 同时可发到 `event_bus`
- 同时可进入 observer
- adapter 可按需投影成 CLI、bridge、HTTP 流式格式

## 8. Session State 设计

当前 `SessionStore` 只有事件列表。完整版建议补：

- session metadata
- last provider/model
- token/usage summary
- compacted summary
- tool execution trace
- memory refs
- last_error

建议区分：

- `SessionSnapshot`
- `SessionEvent`
- `SessionMutation`

当前第一版已经落地：

- `session_state.zig` 已新增 `SessionSnapshot` 与 `snapshotMeta()`
- `session.get` 可联合返回 session event 数、最近 summary event、memory entry 数与 summary 文本
- `session.compact` 可触发 memory compaction，并把 summary 同步回 session event

## 9. Memory Runtime 设计

完整业务版的 agent runtime 必须引入 memory 子系统，但应保持与 `framework` 解耦。

建议 `ourclaw` 的 memory runtime 至少支持：

- `recall_for_turn`
- `append_turn`
- `append_tool_result`
- `compact_session`
- `export_snapshot`

当前状态：尚未落地。

## 10. 失败、超时、取消

完整版 agent runtime 必须统一处理：

- request timeout
- provider timeout
- tool timeout
- task cancellation
- session write failure
- stream sink failure

原则：

- 日志与 observer 失败不阻断主流程
- session/memory 写回失败要被记录并明确暴露
- 对外失败统一映射到 `AppError`

## 11. 与命令域的关系

完整版里，命令域不应消失，而应承担两类职责：

1. 系统命令：`app.meta`、`config.*`、`logs.*`、`diagnostics.*`
2. agent 控制命令：如 `agent.run`、`agent.stream`、`task.get`、`session.get`

也就是说，完整 agent runtime 仍然通过 command dispatcher 暴露，而不是绕开现有运行时主干。

## 12. 当前实现与完整版差距

当前已完成：

- AppContext 最小业务装配
- session event 存储
- stream output 最小事件投递
- tool orchestrator 最小 invoke

当前缺口：

- agent loop
- provider runtime 真实实现
- session snapshot / summary / compaction
- memory runtime
- 真正流式 provider 输出投影
- 多步 tool orchestration

## 13. Prompt Assembly 当前状态

当前第一版已经落地：

- `ourclaw/src/domain/prompt_assembly.zig` 会统一构造 `ProviderMessage[]`
- 当前已注入的消息层包括：
  - `system prompt`
  - `tools prompt`
  - `memory recall`
  - `user prompt`
  - `tool result`

当前仍未完成的是：

- 可配置的 prompt template / prompt profile
- channel / user identity / session snapshot 驱动的更丰富 system prompt
- 更接近生产级的 tool schema prompt 注入与 response mode 约束

## 13. 验收标准

完整业务版的 agent runtime 至少应满足：

1. 能从 CLI 或 HTTP 发起一次 agent 请求
2. 能按 session_id 追踪上下文
3. 能加载 provider 并进行至少一次真实调用
4. 能执行至少一个工具并将结果回写 session
5. 能输出结构化 stream 事件
6. 能在 observer/event bus/log 中看到完整链路
7. 能在失败时给出稳定 `AppError`
