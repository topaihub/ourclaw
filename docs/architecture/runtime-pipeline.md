# ourclaw 统一运行时与执行管线详细设计

## 1. 目标与范围

本文档定义 `ourclaw` 的统一运行时执行管线，目标是让 CLI、bridge、HTTP、后台服务入口共享同一条请求处理主干，从而统一：

- trace
- 日志
- 校验
- 权限与安全检查
- 错误映射
- 事件与指标

本文档覆盖：

- 运行时核心组件
- 统一请求模型
- 分发与 handler 执行顺序
- 同步与异步任务接线
- 事件总线与 observer 集成
- 入口适配策略
- 取消、超时、错误和输出模型

> 当前共享实现已先落在 `framework/src/app/command_types.zig`、`framework/src/app/command_context.zig`、`framework/src/app/command_registry.zig`、`framework/src/app/command_dispatcher.zig`、`framework/src/runtime/app_context.zig`、`framework/src/runtime/task_runner.zig`、`framework/src/runtime/event_bus.zig`、`framework/src/observability/observer.zig`、`framework/src/observability/multi_observer.zig`、`framework/src/observability/log_observer.zig`、`framework/src/observability/file_observer.zig`、`framework/src/observability/metrics.zig`、`framework/src/config/store.zig` 与 `framework/src/config/pipeline.zig`。截至 2026-03-11，它们已经开始复用 `framework/src/core/validation/*` 与 `framework/src/core/error.zig`，并支持 AppContext 级依赖装配、authority 校验、最小同步 handler dispatch、真正 async job 执行、任务状态流转/查询接口、observer/event bus 事件接线、subscription cursor 轮询语义、post-write hook 以及最小 config store 写回链路；但还没有进入更完整的 provider/channel/tool registry、入口适配与业务命令域阶段。

## 2. 核心问题

如果没有统一执行管线，通常会出现这些问题：

- CLI 单独解析错误
- bridge 单独包装错误 JSON
- HTTP 单独做超时和取消
- 业务 handler 里夹带日志、权限校验、配置读取和输出格式化

这会导致：

- trace 无法贯穿
- 错误码不稳定
- 日志字段不一致
- 相同规则在多个入口重复实现

因此，`ourclaw` 必须让所有入口最终都汇聚到同一条 dispatch pipeline。

## 3. 设计目标

统一运行时与执行管线必须满足：

1. 所有入口共用同一套分发逻辑
2. 所有请求都拥有一致的上下文对象
3. 业务 handler 只做业务，不负责横切能力
4. 支持同步命令和异步任务两种执行模式
5. 支持超时、取消和任务状态跟踪
6. 支持统一事件推送与日志记录
7. 支持未来 GUI/manager 和 service 模式扩展

## 4. 总体分层

建议分层如下：

- `interfaces`：CLI、bridge、HTTP、service adapters
- `app`：命令注册、命令元数据、分发器
- `runtime`：上下文、任务执行、生命周期、事件总线
- `core`：日志、trace、校验、错误、响应封装
- `domain`：provider/channel/config/logs/diagnostics 等业务模块

约束如下：

- `interfaces` 不能直接调用 `domain` handler
- 所有入口必须经过 `command_dispatcher`
- `runtime` 不直接渲染最终用户文本，而输出结构化结果

## 5. 核心组件设计

## 5.1 AppContext

`AppContext` 是运行时的全局依赖容器，建议持有：

- allocator
- config store / config snapshot
- logger
- observer
- event bus
- task runner
- command registry
- security policy
- service manager
- provider/channel/tool registries

建议定义：

```zig
pub const AppContext = struct {
    allocator: std.mem.Allocator,
    logger: *Logger,
    observer: Observer,
    event_bus: *EventBus,
    task_runner: *TaskRunner,
    command_registry: *CommandRegistry,
    config_store: *ConfigStore,
    security_policy: *SecurityPolicy,
};
```

## 5.2 RequestContext

每次请求都应生成独立 `RequestContext`，建议包含：

- `request_id`
- `trace_id`
- `span_id`
- 调用来源，例如 `cli`、`bridge`、`http`
- 请求时间
- timeout
- cancellation token
- authority / caller identity

## 5.3 CommandContext

`CommandContext` 是 handler 可见的执行上下文，应基于 `AppContext + RequestContext` 组合而成。

建议包含：

- `app`
- `request`
- `logger`
- `command_meta`
- `validated_params`

业务 handler 只依赖 `CommandContext`，不直接感知 CLI 或 bridge 细节。

## 5.4 CommandRegistry

命令注册中心负责管理：

- 命令 id / method
- 参数定义
- authority
- 执行模式
- handler 指针

建议命令元数据包含：

- `id`
- `method`
- `description`
- `authority`
- `execution_mode`
- `params_schema`

其中 `execution_mode` 建议支持：

- `sync`
- `async_task`

## 5.5 CommandDispatcher

`CommandDispatcher` 是统一执行管线核心，负责：

1. 查找命令
2. 创建 trace scope
3. 参数解析与校验
4. 权限检查
5. 构造 `CommandContext`
6. 调用 handler 或提交 task
7. 记录日志、事件、指标
8. 封装统一结果

## 5.6 TaskRunner

`TaskRunner` 用于异步任务模式，适用于：

- 诊断扫描
- 服务安装/重启
- 大体量日志导出
- 未来 provider health check

建议功能：

- 提交任务
- 查询状态
- 取消任务
- 写入生命周期事件
- 记录任务日志

## 5.7 EventBus

`EventBus` 负责在运行时内部和外部订阅者之间传递事件。

建议事件类型包括：

- `task.started`
- `task.progress`
- `task.finished`
- `config.changed`
- `service.changed`
- `logs.append`
- `diagnostics.updated`

其职责是事件广播，不负责持久化日志。

## 6. 统一请求模型

## 6.1 内部请求模型

建议定义：

```zig
pub const CommandRequest = struct {
    request_id: []const u8,
    method: []const u8,
    params_json: []const u8,
    source: RequestSource,
    timeout_ms: ?u32 = null,
};
```

`RequestSource` 建议定义：

- `cli`
- `bridge`
- `http`
- `service`
- `test`

## 6.2 内部结果模型

建议定义：

```zig
pub const CommandExecutionResult = union(enum) {
    success: []const u8,
    task_accepted: TaskAcceptedResult,
};
```

边界层再根据需要转成：

- CLI 文本或 JSON
- bridge response envelope
- HTTP response body

## 7. 执行管线详细步骤

建议统一执行顺序如下。

## 7.1 Adapter 组装请求

CLI/bridge/HTTP 先把原始输入转成 `CommandRequest`，不在 adapter 内做业务判断。

适配层只负责：

- 解析最外层协议
- 填充 `request_id`
- 标记 `source`
- 传递 `timeout_ms`

## 7.2 Dispatcher 解析命令

分发器首先：

- 根据 `method` 查找命令注册信息
- 若不存在则返回 `METHOD_NOT_FOUND`
- 若存在但来源不允许或 authority 不足，则返回 `METHOD_NOT_ALLOWED`

## 7.3 创建 TraceScope

在执行任何业务逻辑前先创建 `TraceScope`，并把：

- `request_id`
- `method`
- `source`

写入上下文与首条日志。

## 7.4 参数解析与校验

顺序建议：

1. `params_json` 解析为对象
2. 基于命令 schema 做严格校验
3. 执行安全规则
4. 生成 `ValidationReport`
5. 失败则映射统一错误返回

## 7.5 CommandContext 构造

校验通过后，构造 `CommandContext`，并注入：

- 带 trace 的子系统 logger
- observer
- command meta
- validated params
- cancellation token

## 7.6 执行模式分支

若命令为 `sync`：

- 直接调用 handler

若命令为 `async_task`：

- 提交到 `TaskRunner`
- 返回 `task_id`
- 由后续事件或查询接口跟踪状态

## 7.7 结果封装

handler 返回结构化结果后，由 dispatcher 统一封装为：

- success envelope
- error envelope
- task accepted envelope

## 7.8 记录日志、事件与指标

每次请求至少记录以下生命周期：

- `command.received`
- `command.validated`
- `command.completed` 或 `command.failed`

同时记录：

- 请求耗时
- 错误码
- 是否异步任务

## 8. 同步与异步任务模型

## 8.1 同步命令

适合：

- `app.meta`
- `config.get`
- `logs.recent`
- `service.status`

要求：

- 响应快速
- 可以直接返回结构化结果

## 8.2 异步任务命令

适合：

- `diagnostics.doctor`
- `service.install`
- `service.restart`
- `logs.export`

建议任务状态：

- `queued`
- `running`
- `succeeded`
- `failed`
- `cancelled`

建议任务模型：

```zig
pub const TaskRecord = struct {
    id: []const u8,
    command: []const u8,
    state: TaskState,
    started_at_ms: ?i64,
    finished_at_ms: ?i64,
    error_code: ?[]const u8,
};
```

## 9. 入口适配策略

## 9.1 CLI 入口

CLI adapter 负责：

- 解析 argv
- 映射到 `method + params`
- 调用 dispatcher
- 把结构化结果渲染为 CLI 输出

CLI adapter 不负责：

- 校验业务字段
- 自己定义错误码
- 自己做 trace/logging 逻辑

## 9.2 Bridge 入口

bridge adapter 负责：

- 解析桥接请求 envelope
- 调用 dispatcher
- 输出统一 JSON envelope
- 订阅 event bus 并推送 runtime event

它不应自己维护另一套业务命令实现。

## 9.3 HTTP 入口

HTTP adapter 负责：

- 将 route 映射到 method
- 提取 body/query 为 params
- 调用 dispatcher
- 输出 HTTP response

它不应在 controller 中直接耦合业务模块。

## 10. 权限与安全接线

权限与安全检查应位于 dispatcher 中，而不是散落在 handler 中。

建议顺序：

1. 查命令 authority
2. 基于 source 判断入口是否允许
3. 基于 caller identity 判断是否授权
4. 执行参数级安全规则

这样可以避免：

- bridge 可以调用 CLI 专属命令
- 某些高风险命令绕过统一检查

## 11. 错误路径设计

统一错误路径建议如下：

1. 记录错误日志
2. observer 记录失败事件
3. trace span 结束并带错误码
4. 把内部错误映射为 `AppError`
5. 输出统一 envelope

边界层不直接输出裸 Zig error 名称给最终用户。

## 12. 超时与取消

## 12.1 timeout

`RequestContext` 中应允许携带 `timeout_ms`。dispatcher 或 task runner 根据需要：

- 在超时后标记任务失败
- 停止后续等待
- 返回 `TIMEOUT`

## 12.2 cancellation

对于异步任务，建议提供取消令牌与任务取消接口。典型适用：

- 诊断扫描
- 长日志导出
- 长时间 provider 探测

## 13. 状态与生命周期管理

建议 `runtime/lifecycle.zig` 管理：

- app init
- subsystem init
- graceful shutdown
- sink flush
- task drain
- event bus close

关闭时建议顺序：

1. 拒绝新请求
2. 等待或取消进行中任务
3. flush logs
4. flush observer
5. 回收资源

## 14. 事件模型建议

建议定义统一 runtime event 结构：

```zig
pub const RuntimeEvent = struct {
    seq: u64,
    topic: []const u8,
    ts_unix_ms: i64,
    payload_json: []const u8,
};
```

说明：

- `seq` 便于 `events.poll`
- `topic` 便于 GUI 订阅
- `payload_json` 保持跨边界传输灵活性

## 15. 建议 API 草案

```zig
pub fn initAppContext(allocator: std.mem.Allocator, config: AppBootstrapConfig) !AppContext
pub fn deinit(self: *AppContext) void

pub fn dispatch(
    dispatcher: *CommandDispatcher,
    req: CommandRequest,
) !CommandExecutionResult

pub fn submitTask(
    runner: *TaskRunner,
    ctx: CommandContext,
    handler: CommandHandler,
) !TaskAcceptedResult
```

## 16. 典型流程示例

## 16.1 `config.set`

1. CLI/bridge 组装请求
2. dispatcher 查命令注册表
3. 创建 trace scope
4. 参数解析与校验
5. 配置字段注册表校验
6. 构造 `CommandContext`
7. 调用 `config.set` handler
8. 写入配置
9. 记录 `config.changed` 事件
10. 返回结构化结果

## 16.2 `diagnostics.doctor`

1. adapter 组装请求
2. dispatcher 校验与授权
3. 发现命令为 `async_task`
4. 提交给 `TaskRunner`
5. 立即返回 `task_id`
6. 后续通过 event bus 推送任务状态

## 17. 测试策略

建议覆盖以下测试：

### 17.1 dispatcher 单元测试

- method not found
- invalid params
- authority denied
- sync handler success
- sync handler failure
- async task accepted

### 17.2 adapter 测试

- CLI argv 到 `CommandRequest` 映射
- bridge request 到 `CommandRequest` 映射
- HTTP route 到 `CommandRequest` 映射

### 17.3 集成测试

- 同一命令经 CLI 和 bridge 调用，结果字段一致
- 错误场景下 trace/log/observer 都被记录
- 异步任务状态能被查询与订阅

## 18. 实施顺序建议

建议顺序：

1. `AppContext`
2. `CommandRegistry`
3. `CommandDispatcher`
4. `CommandContext`
5. `TaskRunner`
6. `EventBus`
7. CLI adapter
8. bridge adapter
9. HTTP adapter

## 19. 验收标准

统一运行时与执行管线完成时，应满足：

- CLI、bridge、HTTP 不直接调用业务 handler
- 所有请求都拥有 `trace_id`
- 校验、日志、错误映射都由 dispatcher 统一处理
- 支持同步命令和异步任务
- 支持事件推送与任务状态跟踪
- 运行时可优雅关闭并 flush 日志

## 20. 结论

`ourclaw` 的运行时设计核心不是“再写一个入口层”，而是建立一条稳定统一的执行主干。后续不管接 manager、service 还是纯 CLI，都应复用这条主干，而不是再复制一套 handler 编排逻辑。
