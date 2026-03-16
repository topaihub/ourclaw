# ourclaw 总体设计

> 使用说明（2026-03-16）：本文档现在只承担 `ourclaw` 业务侧总体背景说明角色，不再作为默认执行入口。
>
> - `ourclaw/docs/specs/reference-aligned-ourclaw/requirements.md`
> - `ourclaw/docs/specs/reference-aligned-ourclaw/design.md`
> - `ourclaw/docs/specs/reference-aligned-ourclaw/tasks.md`
>
> 本文中的部分“阶段目标/未来结构”形成于 phase-1 之前或 phase-1 初期；阅读时应把它当成背景设计意图，而不是当前实现状态的逐行事实源。

## 1. 背景与目标

`ourclaw` 已经不是“计划使用 Zig 重建”的空项目，而是已经完成 phase-1 基线并进入 active spec 长期推进阶段的 Zig claw runtime。

本项目的核心诉求不是简单复制 `nullclaw`，而是基于现有三套代码的优点，重新建立一条更干净、更统一、更可扩展的主干：

- 从 `nullclaw-manager` 中提取可复用的基础 core 层
- 从 `nullclaw` 中吸收 runtime、observer、扩展点和 Zig 实现经验
- 从 `openclaw` 中借鉴更成熟的日志、校验、配置治理和工程化设计

第一阶段的目标不是功能全量，而是先打稳以下横切基础能力：

- 统一日志
- 统一校验
- 统一错误模型
- 统一配置模型
- 统一执行管线

只有先把这些横切能力重建完成，后续迁移 provider、channel、tool、memory、agent 等能力时，才不会把 `nullclaw` 现有的分散问题原样复制到新仓库里。

## 2. 总判断

### 2.1 工程定位判断

- `nullclaw-manager` 适合作为 GUI 编排层，不适合作为新 runtime 的宿主骨架
- `nullclaw` 适合作为 Zig 运行时和能力池参考，但不适合直接原样继承为新主干
- `openclaw` 更适合作为工程治理参考，特别是日志、校验、配置和文档化能力

因此，`ourclaw` 应独立建立为一个新的 Zig 工程，而不是直接长在 `nullclaw-manager` 里。

### 2.2 为什么需要重建而不是直接复用

`nullclaw` 目前并不是完全没有日志能力，但它的日志、校验和运行时接线并不统一：

- 模块内部大量使用 `std.log.scoped(...)`
- 存在 `observability` 抽象，但很多主链路默认接的是 `NoopObserver`
- 校验逻辑分散在配置解析、工具实现、安全模块和各业务入口中

`nullclaw-manager` 也不是不能用，但它当前 `core` 更像一组基础工具和预研骨架，还没有形成一条覆盖所有入口的统一执行主干。

因此，新工程要做的不是“继续堆功能”，而是先把主干整理出来。

## 3. 设计原则

`ourclaw` 的总体设计遵循以下原则：

1. 运行时优先
2. 横切能力先行
3. 入口统一
4. 结构化日志优先
5. 校验前置
6. 错误码稳定
7. 配置写入必须受控
8. 安全规则显式化
9. 扩展点解耦
10. GUI 与 runtime 解耦

这些原则意味着：

- CLI、bridge、HTTP、后台服务不应该各自维护一套日志和错误处理
- 所有外部输入都应先经过校验，再进入业务 handler
- 所有配置修改都必须走统一注册表和规则系统
- 所有核心行为都应具备 trace、log、issue、error 的统一表达方式

## 4. 现有仓库的提取与借鉴策略

## 4.1 从 nullclaw-manager 提取什么

建议把 `nullclaw-manager/app/src/core` 视为 `ourclaw` 的基础内核来源，但不是原样照搬。

适合提取的模块：

- `nullclaw-manager/app/src/core/logging/logger.zig`
- `nullclaw-manager/app/src/core/logging/trace_logger.zig`
- `nullclaw-manager/app/src/core/logging/trace_context.zig`
- `nullclaw-manager/app/src/core/validation/validator.zig`
- `nullclaw-manager/app/src/core/validation/assert.zig`
- `nullclaw-manager/app/src/core/responses/response.zig`

对这些模块的判断如下：

- `trace_context.zig` 适合作为请求级 trace 上下文的起点
- `trace_logger.zig` 适合保留 span/耗时/异常记录思路，但不应继续让它自行管理文件写入
- `logger.zig` 适合保留日志级别和初始化思路，但要升级为结构化日志中心
- `validator.zig` 和 `assert.zig` 适合作为校验 API 雏形，但需要补全规则系统和报告模型
- `response.zig` 适合保留响应封装思路，但需要与响应码体系彻底合并

需要特别注意的问题：

- `validator.zig` 中仍有未完成的规则实现，例如 pattern 校验还是占位状态
- `response.zig` 与 `response_codes.zig` 存在重复建模倾向
- 当前 `core` 还没有真正接管所有宿主入口和业务命令

因此，`ourclaw` 应该把它视为“基础抽取源”，而不是“最终框架”。

## 4.2 从 nullclaw 借什么

`nullclaw` 更适合贡献以下部分：

- Zig 运行时组织经验
- observer/vtable 扩展模式
- provider/channel/tool/memory 等域的结构边界
- 真实业务能力的实现经验

重点借鉴点：

- `nullclaw/src/observability.zig` 的 `Observer` 抽象
- `LogObserver`、`FileObserver`、`MultiObserver` 的分层设计
- provider、channel、tool 的可插拔接口思想

不建议直接继承的点：

- 当前 `main` 中大量默认挂载 `NoopObserver`
- 不同模块自行打印日志，缺少统一日志中心
- 校验逻辑分散，没有统一 request validation pipeline

结论：

`nullclaw` 更适合做“能力池”和“参考实现”，不适合直接作为 `ourclaw` 的主骨架。

## 4.3 从 openclaw 借什么

`openclaw` 的最大价值不是语言实现，而是工程治理方式。

建议重点借鉴：

- 文件日志与控制台日志并存
- JSONL 结构化日志
- 子系统 logger 机制
- 日志等级控制、容量上限与降级策略
- schema 校验 + 语义校验 + 交叉字段校验
- 安全规则独立建模

这些能力直接对应 `ourclaw` 当前最缺的部分。

## 5. ourclaw 的目标定位

`ourclaw` 的角色是运行时优先的 Zig 工程，其职责包括：

- CLI 主程序
- 配置系统
- 日志与可观测性系统
- 校验与错误模型
- 诊断系统
- 服务管理
- 网关与桥接接口
- provider/channel/tool/memory 的统一扩展框架

`nullclaw-manager` 的未来角色则应是：

- GUI 宿主
- runtime 管理器
- 通过桥接契约编排 `ourclaw`

二者关系应当是“manager 编排 runtime”，而不是“manager 内嵌全部 runtime 逻辑”。

## 6. 总体架构

建议将 `ourclaw` 拆成以下层次：

- `core`：横切基础能力
- `config`：配置加载、写回、迁移、规则
- `observability`：事件、指标、trace、observer
- `runtime`：生命周期、任务执行、服务管理、事件总线
- `app`：命令注册与分发
- `commands`：结构化命令处理器
- `domain`：providers/channels/tools/memory/gateway/diagnostics/logs
- `interfaces`：CLI、bridge、HTTP、服务入口
- `compat`：兼容旧配置和迁移能力

其中最关键的是：

- `core` 不放业务
- `commands` 不直接做日志格式拼接
- `interfaces` 不自己做业务校验
- `runtime` 承担统一执行管线和上下文装配

## 7. 统一执行管线

新工程最重要的设计之一，是所有入口必须走同一条执行管线。

建议执行链路如下：

1. 收到请求
2. 创建 `TraceScope`
3. 解析参数
4. 执行 schema 校验
5. 执行语义校验
6. 执行安全校验
7. 构造 command context
8. 调用 handler
9. 记录日志、事件、指标
10. 输出统一响应封装

### 7.1 为什么必须统一执行管线

如果 CLI、bridge、HTTP 各自处理：

- trace 会断裂
- 错误模型会发散
- 参数校验会重复
- 日志字段无法对齐

统一管线的价值在于：

- 所有入口天然共享 trace_id
- 所有错误都能映射到稳定错误码
- 所有 handler 都只关心业务，不关心横切能力

### 7.2 入口适配策略

建议所有入口最终都转成统一的内部调用模型，例如：

- `CommandRequest`
- `CommandContext`
- `CommandResult`

CLI、bridge、HTTP 只是 request adapter，不直接承载业务逻辑。

## 8. 日志与可观测性设计

## 8.1 设计目标

`ourclaw` 的日志体系必须解决当前 `nullclaw` 的几个问题：

- 日志入口不统一
- 结构化字段不足
- 文件日志与控制台日志关系不清晰
- trace 无法稳定贯通
- 对敏感信息缺少统一 redact 策略

## 8.2 建议日志模型

建议定义统一的 `LogRecord`：

- `ts`
- `level`
- `subsystem`
- `trace_id`
- `span_id`
- `message`
- `fields`
- `error_code`
- `duration_ms`

所有日志 sink 都只接收 `LogRecord`，不再让业务模块自行决定最终格式。

## 8.3 建议 sink 体系

首版建议至少提供：

- `ConsoleSink`
- `JsonlFileSink`
- `MemorySink`
- `MultiSink`

后续可扩展：

- `OtelSink`
- `RemoteSink`
- `RingBufferSink`

## 8.4 日志输出策略

建议默认模式：

- CLI 交互模式：pretty console + JSONL file
- 后台服务模式：compact console + JSONL file
- 测试模式：memory sink 或 noop sink

## 8.5 TraceLogger 的新角色

`TraceLogger` 在新工程里不应再是“独立写日志文件的工具”，而应该变成：

- `TraceSpan`
- `SpanLogger`
- 与统一 logger/observer 集成的范围对象

它的职责应该是：

- 记录 span 开始和结束
- 记录耗时
- 记录异常类型
- 写入 trace 相关字段到统一日志系统

## 8.6 Observer 体系

建议保留 `nullclaw` 的 observer 抽象，但要让它真正接入主链路，而不是长期默认 `NoopObserver`。

推荐关系：

- logger 负责结构化日志记录
- observer 负责领域事件和指标记录
- trace 负责请求级链路关联

三者可以共享 `trace_id` 和上下文，但职责分开。

## 8.7 敏感信息处理

必须提供统一 `redact` 机制，至少覆盖：

- API key
- access token
- secret ref resolve 后的值
- authorization header
- gateway token/password

任何日志输出前都必须先经过 `redact`。

## 9. 校验体系设计

## 9.1 设计目标

`ourclaw` 的校验体系不能再是分散式 if/else，而要具备统一的表达模型和结果模型。

目标包括：

- 输入解析层校验
- schema 层校验
- 语义层校验
- 跨字段规则校验
- 安全规则校验
- 风险确认机制

## 9.2 校验结果模型

建议统一定义：

- `ValidationIssue`
- `ValidationReport`

其中 `ValidationIssue` 至少包含：

- `path`
- `code`
- `message`
- `severity`
- `hint`
- `retryable`

这样可以同时支持：

- CLI 可读输出
- JSON/bridge 可结构化返回
- GUI 可直接展示字段级错误

## 9.3 校验层次

建议按以下顺序执行：

1. 解析层校验
2. schema 校验
3. 基础规则校验
4. 语义规则校验
5. 交叉字段校验
6. 安全规则校验
7. 风险确认校验

## 9.4 字段注册表

建议以 `nullclaw-manager/app/src/services/config_mutation.zig` 为灵感，建立正式的配置字段注册表。

每个字段定义建议至少包含：

- `path`
- `label`
- `value_kind`
- `default_value`
- `sensitive`
- `requires_restart`
- `risk_level`
- `rules`
- `description`

这样可以让配置修改、文档生成、前端表单、校验规则和错误提示共享同一份元数据。

## 9.5 Assert 的角色

`Assert` 仍然应保留，但角色必须收缩：

- 只用于内部不变量防御
- 不作为外部输入校验主工具

所有来自用户、配置文件、网络、桥接入口的输入都必须走正式 validator。

## 10. 错误与响应模型

## 10.1 基本原则

- 内部使用 Zig error union 控制流
- 边界层统一映射成 `AppError`
- 对外只暴露统一 `Envelope<T>`

## 10.2 建议错误模型

建议 `AppError` 包含：

- `code`
- `message`
- `user_message`
- `retryable`
- `details`
- `target`

其中：

- `message` 给开发与日志
- `user_message` 给 CLI/GUI 用户
- `details` 给调试和结构化展示

## 10.3 建议响应模型

建议统一：

- `ok`
- `result`
- `error`
- `meta`

无论来自 CLI、bridge 还是 HTTP，都应从同一套内部结果模型转出。

## 10.4 错误码分层

建议统一一套错误码前缀：

- `CORE_*`
- `VALIDATION_*`
- `CONFIG_*`
- `SERVICE_*`
- `PROVIDER_*`
- `CHANNEL_*`
- `TOOL_*`
- `SECURITY_*`

这样可以避免当前 `nullclaw-manager` 中响应结构和响应码定义重复的问题。

## 11. 配置与兼容策略

## 11.1 配置根目录建议

建议 `ourclaw` 使用独立配置目录，例如：

- `~/.ourclaw`

原因：

- 避免与现有 `nullclaw` 相互污染
- 便于做迁移、导入和回滚
- 便于分阶段切换运行时

## 11.2 兼容策略

建议做到：

- 尽量兼容 `nullclaw` 的主要字段路径命名
- 提供配置导入能力
- 不直接共用旧目录

推荐策略是“兼容读取，独立写入”。

## 11.3 配置写回约束

所有配置写回必须统一经过：

- 字段注册表
- 校验器
- 风险确认
- 差异比较
- 重启要求判断
- 变更日志记录

禁止业务代码直接操作原始 JSON 文件。

## 12. 建议目录结构

建议的第一版目录如下：

```text
ourclaw/
  build.zig
  build.zig.zon
  docs/
  spec/
  src/
    main.zig
    root.zig
    core/
      error.zig
      envelope.zig
      logging/
        logger.zig
        record.zig
        sink.zig
        console_sink.zig
        file_sink.zig
        redact.zig
      trace/
        trace_context.zig
        trace_span.zig
      validation/
        validator.zig
        issue.zig
        rules_basic.zig
        rules_security.zig
        assert.zig
    config/
      loader.zig
      parser.zig
      field_registry.zig
      defaults.zig
      validators.zig
      migration.zig
    observability/
      observer.zig
      log_observer.zig
      file_observer.zig
      metrics.zig
      multi_observer.zig
    runtime/
      app_context.zig
      lifecycle.zig
      task_runner.zig
      event_bus.zig
      service_manager.zig
    app/
      command_context.zig
      command_registry.zig
      command_dispatcher.zig
    commands/
      app_meta.zig
      config_get.zig
      config_set.zig
      logs_recent.zig
      diagnostics.zig
    security/
      command_guard.zig
      path_guard.zig
      secret_guard.zig
    providers/
    channels/
    tools/
    memory/
    compat/
      nullclaw_import.zig
      openclaw_contracts.zig
  tests/
```

## 13. MVP 范围

第一阶段不追求功能全量，建议只做：

- CLI 主入口
- 配置加载与修改
- 统一日志
- 统一校验
- 诊断命令
- 日志查询
- 服务状态查询
- 基础 bridge/command 契约

暂缓内容：

- provider 全量迁移
- channel 全量迁移
- tool 全量迁移
- memory 全量迁移
- agent/session/gateway 主运行链路

原因是第一阶段的目标是证明新主干成立，而不是追求能力表面数量。

## 14. 实施顺序建议

建议按以下顺序推进：

1. 先建立工程骨架和测试框架
2. 再建立错误模型与响应封装
3. 再建立日志与 trace 主干
4. 再建立 validator 和字段注册表
5. 再打通配置读写与命令分发
6. 再接入 observer 与 runtime event
7. 再补命令集和诊断/日志域
8. 最后再逐步迁移 provider/channel/tool/memory/agent

## 15. 验收重点

每一阶段都应围绕横切能力做验收，而不是只看功能是否跑通。

### 15.1 日志验收

- trace_id 是否贯穿整个请求链路
- 控制台和文件日志是否字段一致
- 敏感数据是否已统一脱敏

### 15.2 校验验收

- 非法输入是否返回稳定错误码
- 是否能返回结构化 `issues[]`
- 是否拒绝未知字段和越权输入

### 15.3 配置验收

- 是否全部经过字段注册表
- 是否能判断是否需要重启
- 是否写入变更日志

### 15.4 运行时验收

- CLI、bridge、HTTP 是否共用同一条 dispatch pipeline
- handler 是否已经摆脱各自独立的日志和错误包装逻辑

## 16. 建议后续详细设计文档

在本总体设计基础上，建议继续拆出以下文档：

- `ourclaw/docs/architecture/logging.md`
- `ourclaw/docs/architecture/validation.md`
- `ourclaw/docs/architecture/runtime-pipeline.md`
- `ourclaw/docs/contracts/error-model.md`
- `ourclaw/docs/contracts/log-record.md`
- `ourclaw/docs/contracts/command-envelope.md`
- `ourclaw/docs/contracts/config-field-registry.md`

## 17. 结论

`ourclaw` 的核心路线可以概括为一句话：

先重建横切主干，再迁移业务能力。

这条路线的关键不是“做一个 Zig 版 nullclaw”，而是做一个：

- 主干统一
- 日志统一
- 校验统一
- 配置统一
- 运行时统一
- 对 GUI 和未来扩展更友好的新 claw runtime

只有这样，后续详细设计、任务拆分和大模型协作开发才会稳定、可控、可迭代。
