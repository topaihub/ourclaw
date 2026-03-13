# ourclaw 实施 Epic 拆分

本文档用于把总体设计转成后续可继续细化的实施阶段。

> 说明：工作区当前已拆为 `framework/`、`ourclaw/`、`ourclaw-manager/` 三条主线；其中错误模型、响应封装、日志、校验等横切基础能力优先落在共享 `framework/src/*`，`ourclaw/` 主要承载业务域与接口层。

## Epic 01：工程骨架与模块边界

### 目标

初始化 `ourclaw` 的 Zig 工程结构、模块边界和测试入口。

### 主要产出

- `build.zig`
- `build.zig.zon`
- `src/root.zig`
- `src/main.zig`
- `tests/` 基础测试入口
- 基础目录骨架

### 完成标准

- 可以成功执行基础构建
- 模块引用关系清晰
- 文档中的目录结构已有基本落位

## Epic 02：统一错误模型与响应封装

### 目标

建立 `AppError`、`Envelope<T>` 和错误码体系。

### 主要产出

- `framework/src/core/error.zig`
- `framework/src/contracts/envelope.zig`
- 错误码命名约定
- 边界层错误映射函数

### 完成标准

- 内部 error union 可映射到稳定外部错误码
- CLI/bridge/HTTP 可共用同一套响应封装

## Epic 03：统一日志与 Trace 主干

### 目标

建立结构化日志中心和请求级 trace 能力。

### 主要产出

- `framework/src/core/logging/*`
- `framework/src/core/trace/*`
- `ConsoleSink`
- `JsonlFileSink`
- `MultiSink`

### 完成标准

- 每个请求都有 trace_id
- 控制台和文件日志结构统一
- 支持日志级别、文件大小限制和脱敏

## Epic 04：统一校验框架

### 目标

建立正式的 validator、issue/report 模型和基础规则库。

### 主要产出

- `framework/src/core/validation/issue.zig`
- `framework/src/core/validation/report.zig`
- `framework/src/core/validation/validator.zig`
- `framework/src/core/validation/rules_basic.zig`
- `framework/src/core/validation/rules_security.zig`
- `framework/src/core/validation/assert.zig`

### 完成标准

- 能返回结构化 `ValidationReport`
- 能区分 schema、语义、安全和风险确认问题
- 外部输入不再直接依赖 assert

## Epic 05：配置系统与字段注册表

### 目标

建立配置读取、默认值、字段注册表、迁移和写回主干。

### 主要产出

- `src/config/loader.zig`
- `src/config/parser.zig`
- `src/config/field_registry.zig`
- `src/config/defaults.zig`
- `src/config/migration.zig`
- `src/config/validators.zig`

### 完成标准

- 所有配置写回都走注册表
- 支持 `requires_restart`、`sensitive`、`risk_level`
- 支持兼容读取旧配置和独立写入新配置

## Epic 06：Observer 与可观测性接入

### 目标

让 observer 真正接入主执行链路，统一事件和指标记录。

### 主要产出

- `src/observability/observer.zig`
- `src/observability/log_observer.zig`
- `src/observability/file_observer.zig`
- `src/observability/multi_observer.zig`
- `src/observability/metrics.zig`

### 完成标准

- 主执行链路不再默认长期依赖 `NoopObserver`
- 关键事件和指标可被记录和查询

## Epic 07：统一运行时与命令分发管线

### 目标

建立所有入口共用的 dispatch pipeline。

### 主要产出

- `src/runtime/app_context.zig`
- `src/runtime/lifecycle.zig`
- `src/runtime/task_runner.zig`
- `src/runtime/event_bus.zig`
- `src/app/command_context.zig`
- `src/app/command_registry.zig`
- `src/app/command_dispatcher.zig`

### 完成标准

- CLI、bridge、HTTP 最终都走同一条 handler 调度链
- 日志、错误、校验、trace 已统一接入

## Epic 08：配置、日志、诊断类命令落地

### 目标

优先实现最能验证主干设计价值的命令。

### 主要产出

- `commands/app_meta.zig`
- `commands/config_get.zig`
- `commands/config_set.zig`
- `commands/logs_recent.zig`
- `commands/diagnostics.zig`

### 完成标准

- 可以完整验证统一日志、统一校验和统一错误模型
- 命令结果已是结构化输出，而不是原始文本拼接

## Epic 09：扩展点骨架

### 目标

建立 provider/channel/tool/memory 的可插拔接口与 registry。

### 主要产出

- provider registry
- channel registry
- tool registry
- memory registry

### 完成标准

- 可以注册最小实现
- 可以在 runtime 中通过接口访问，而不是强耦合模块调用

## Epic 10：兼容迁移与旧能力接入

### 目标

逐步对接 `nullclaw` 的旧配置和能力。

### 主要产出

- `src/compat/nullclaw_import.zig`
- 配置导入器
- 基础兼容层
- 后续迁移路线说明

### 完成标准

- 可以导入旧配置
- 不污染 `nullclaw` 原目录
- 后续迁移 provider/channel/tool/agent 有清晰入口

## 建议的拆分顺序

建议严格按顺序推进：

1. Epic 01
2. Epic 02
3. Epic 03
4. Epic 04
5. Epic 05
6. Epic 06
7. Epic 07
8. Epic 08
9. Epic 09
10. Epic 10

## 每个 Epic 的统一验收问题

每个 Epic 完成时，建议都回答以下问题：

1. 是否复用了统一错误模型？
2. 是否复用了统一日志系统？
3. 是否复用了统一校验系统？
4. 是否接入了 trace/observer？
5. 是否保持了与后续 GUI/bridge 对接的稳定边界？

## 下一步建议

在继续拆成大模型任务之前，建议先为以下 3 份文档做详细设计：

- logging
- validation
- runtime pipeline

这三份文档会直接决定后续任务拆分是否稳定。
