# ourclaw 面向大模型的任务拆分

> 归档说明（2026-03-17）：本文档保留为历史的大模型任务拆分材料，但不再作为 live checklist 或默认续做入口。当前主线请优先使用：
>
> - `ourclaw/docs/specs/reference-aligned-ourclaw/requirements.md`
> - `ourclaw/docs/specs/reference-aligned-ourclaw/design.md`
> - `ourclaw/docs/specs/reference-aligned-ourclaw/tasks.md`
> - `ourclaw/docs/planning/session-resume.md`

本文档把 `ourclaw/docs/architecture/overall-design.md`、`ourclaw/docs/architecture/logging.md`、`ourclaw/docs/architecture/validation.md`、`ourclaw/docs/architecture/runtime-pipeline.md` 与 `ourclaw/docs/planning/implementation-epics.md` 转成更适合交给大模型逐步执行的任务清单。

目标不是一次性把所有代码都生成完，而是把工作拆成边界清晰、依赖明确、回归容易的小任务。

> 说明：当前工作区已拆成 `framework/` + `ourclaw/` + `ourclaw-manager/`。其中错误模型、响应封装、日志、校验、运行时主干等横切基础能力，执行时应优先映射到共享 `framework/src/*`；`ourclaw/` 主要承载业务域、compat 和 interfaces。

## 1. 使用原则

### 1.1 一次只做一个任务

建议每次只把一个任务交给大模型，最多允许把一个任务和它直接依赖的极小补丁合并。

### 1.2 任务要小而闭环

每个任务应满足：

- 修改文件范围有限
- 有明确输入和输出
- 有最小可验证结果
- 可以独立 review

### 1.3 优先骨架，再补实现

先建立：

- 类型
- 接口
- 模块边界
- 最小测试

再补功能深度，避免一开始让大模型跨太多层同时写大量逻辑。

### 1.4 严格按依赖顺序推进

例如：

- 没有 `AppError`，不要先写 CLI 输出层
- 没有 `ValidationReport`，不要先写复杂配置写回
- 没有 `CommandDispatcher`，不要先把 bridge/HTTP 接进去

### 1.5 每个任务都要附验证

即便当前还没有完整构建链，也要至少要求：

- 单元测试
- 编译通过
- 或文档中约定的接口一致性检查

## 2. 建议任务模板

每个任务都建议给大模型以下信息：

- 任务 ID
- 任务目标
- 前置依赖
- 参考文档
- 建议修改文件
- 必须遵守的约束
- 完成标准
- 建议验证命令

推荐提示词骨架：

```text
请在 `ourclaw` 工程中完成任务 <TASK_ID>。

目标：
<任务目标>

前置依赖：
<依赖项>

参考文档：
<文档路径>

建议修改文件：
<文件列表>

实现要求：
<约束和细节>

完成后请：
1. 确保实现满足完成标准
2. 运行相关测试或构建验证
3. 用简洁中文说明改动点、文件路径和验证结果
```

## 3. Epic 01：工程骨架与模块边界

## TASK-01：初始化 Zig 工程骨架

- 目标：创建 `build.zig`、`build.zig.zon`、`src/main.zig`、`src/root.zig` 和基础目录
- 前置依赖：无
- 参考文档：`ourclaw/docs/architecture/overall-design.md`
- 建议修改文件：`ourclaw/build.zig`、`ourclaw/build.zig.zon`、`ourclaw/src/main.zig`、`ourclaw/src/root.zig`
- 实现要求：先提供最小可编译骨架，不要提前塞业务逻辑
- 完成标准：工程能进行最小编译，目录结构与总体设计对齐
- 建议验证：`zig build`

## TASK-02：建立模块导出骨架

- 目标：为 `core`、`config`、`observability`、`runtime`、`app` 建立空模块文件和统一导出入口
- 前置依赖：TASK-01
- 参考文档：`ourclaw/docs/architecture/overall-design.md`
- 建议修改文件：`ourclaw/src/root.zig` 以及各模块目录下的占位文件
- 实现要求：只定义公开导出边界与最小类型，不实现复杂逻辑
- 完成标准：后续任务可以按模块独立落地，不需要重构入口
- 建议验证：`zig build`

## TASK-03：建立测试入口与测试约定

- 目标：创建 `tests/` 基础测试入口和最小 smoke test
- 前置依赖：TASK-01、TASK-02
- 参考文档：`ourclaw/docs/planning/implementation-epics.md`
- 建议修改文件：`ourclaw/build.zig`、`ourclaw/tests/` 下文件
- 实现要求：测试入口要能覆盖后续单元测试扩展，不要把测试逻辑塞进 `main.zig`
- 完成标准：可以执行最小测试命令
- 建议验证：`zig build test`

## 4. Epic 02：统一错误模型与响应封装

## TASK-04：实现 `AppError` 与错误码命名约定

- 目标：定义 `AppError`、错误码前缀和边界字段
- 前置依赖：TASK-02
- 参考文档：`ourclaw/docs/architecture/overall-design.md`
- 建议修改文件：`framework/src/core/error.zig`
- 实现要求：支持 `code`、`message`、`user_message`、`retryable`、`details`、`target`
- 完成标准：可表达配置、校验、服务、安全等不同域错误
- 建议验证：为构造与序列化添加单元测试

## TASK-05：实现统一 `Envelope` 模型

- 目标：定义成功/失败统一响应封装
- 前置依赖：TASK-04
- 参考文档：`ourclaw/docs/architecture/overall-design.md`
- 建议修改文件：`framework/src/contracts/envelope.zig`
- 实现要求：至少支持 `ok`、`result`、`error`、`meta`
- 完成标准：CLI/bridge/HTTP 将来可共用同一套内部结果模型
- 建议验证：单元测试覆盖 success/error 两种情况

## TASK-06：实现内部错误到 `AppError` 的映射函数

- 目标：提供 `ValidationError`、`MethodNotFound`、`Timeout` 等到 `AppError` 的映射
- 前置依赖：TASK-04、TASK-05
- 参考文档：`ourclaw/docs/architecture/runtime-pipeline.md`
- 建议修改文件：`framework/src/core/error.zig`
- 实现要求：先覆盖核心通用错误，不追求一次性囊括全部业务错误
- 完成标准：后续 dispatcher 可直接复用映射函数
- 建议验证：单元测试覆盖常见映射路径

## 5. Epic 03：统一日志与 Trace 主干

## TASK-07：实现日志级别与基础记录模型

- 目标：实现 `LogLevel`、`LogField`、`LogRecord`
- 前置依赖：TASK-02
- 参考文档：`ourclaw/docs/architecture/logging.md`
- 建议修改文件：`framework/src/core/logging/level.zig`、`framework/src/core/logging/record.zig`
- 实现要求：类型保持轻量，优先满足 JSONL 与 console 渲染需求
- 完成标准：日志结构可被不同 sink 共用
- 建议验证：单元测试覆盖级别比较与字段序列化

## TASK-08：实现 `MemorySink` 与基础 `Logger`

- 目标：先打通最小 logger 写入链路
- 前置依赖：TASK-07
- 参考文档：`ourclaw/docs/architecture/logging.md`
- 建议修改文件：`framework/src/core/logging/sink.zig`、`framework/src/core/logging/memory_sink.zig`、`framework/src/core/logging/logger.zig`
- 实现要求：优先让测试环境可用，不要先做复杂文件 I/O
- 完成标准：日志可写入内存 sink，支持 child subsystem logger
- 建议验证：单元测试检查写入条数、字段内容和 child subsystem 组合

## TASK-09：实现 `ConsoleSink`

- 目标：支持 pretty/compact/json 三种控制台输出模式
- 前置依赖：TASK-08
- 参考文档：`ourclaw/docs/architecture/logging.md`
- 建议修改文件：`framework/src/core/logging/console_sink.zig`
- 实现要求：控制台渲染逻辑独立，不把格式化写回 logger 主体
- 完成标准：同一条记录可按不同 style 输出
- 建议验证：测试不同 level/style 的渲染结果

## TASK-10：实现 `JsonlFileSink`

- 目标：支持目录自动创建、JSONL 追加写入和 `max_bytes` 限制
- 前置依赖：TASK-08
- 参考文档：`ourclaw/docs/architecture/logging.md`
- 建议修改文件：`framework/src/core/logging/file_sink.zig`
- 实现要求：日志失败不能抛出到主业务；先不做复杂轮转，先做大小上限和基础保留位
- 完成标准：可写文件、可限制大小、可在失败时降级
- 建议验证：临时目录集成测试

## TASK-11：实现 `MultiSink` 与 logger 多后端分发

- 目标：把 console/file/memory 串起来
- 前置依赖：TASK-09、TASK-10
- 参考文档：`ourclaw/docs/architecture/logging.md`
- 建议修改文件：`framework/src/core/logging/multi_sink.zig`、`framework/src/core/logging/logger.zig`
- 实现要求：单个 sink 失败不影响其他 sink
- 完成标准：同一条日志可同时进入多个 sink
- 建议验证：构造一个故障 sink，确认其他 sink 仍可写入

## TASK-12：实现脱敏与 trace 接口对接

- 目标：实现 `redact.zig` 并预留 logger 自动读取 trace 上下文的能力
- 前置依赖：TASK-11
- 参考文档：`ourclaw/docs/architecture/logging.md`
- 建议修改文件：`framework/src/core/logging/redact.zig`、`framework/src/core/logging/logger.zig`
- 实现要求：至少支持基于字段名的敏感信息脱敏；trace 对接先做接口，不要求完整 runtime 接线
- 完成标准：敏感字段不再原样写入日志
- 建议验证：单元测试覆盖 `api_key`、`token`、`authorization` 等场景

## 6. Epic 04：统一校验框架

## TASK-13：实现 `ValidationIssue` 与 `ValidationReport`

- 目标：建立校验结果公共模型
- 前置依赖：TASK-02
- 参考文档：`ourclaw/docs/architecture/validation.md`
- 建议修改文件：`framework/src/core/validation/issue.zig`、`framework/src/core/validation/report.zig`
- 实现要求：支持 error/warn/info 和 issue 计数汇总
- 完成标准：后续 request/config 校验共用同一模型
- 建议验证：单元测试覆盖 issue 聚合和报告状态判断

## TASK-14：实现基础规则库

- 目标：实现非空、长度、范围、布尔、枚举等基础规则
- 前置依赖：TASK-13
- 参考文档：`ourclaw/docs/architecture/validation.md`
- 建议修改文件：`framework/src/core/validation/rules_basic.zig`
- 实现要求：规则输出 `ValidationIssue`，不要直接抛错
- 完成标准：可覆盖大多数 request/config 基础校验
- 建议验证：规则级单元测试

## TASK-15：实现安全规则库

- 目标：实现路径、host、port、secret ref id、URL 协议等安全规则
- 前置依赖：TASK-14
- 参考文档：`ourclaw/docs/architecture/validation.md`
- 建议修改文件：`framework/src/core/validation/rules_security.zig`
- 实现要求：优先实现通用规则，避免耦合具体业务命令
- 完成标准：安全边界具备可复用规则集合
- 建议验证：覆盖 traversal、非法端口、非法 secret id 等测试

## TASK-16：实现 validator 执行器

- 目标：把规则执行、issue 收集和报告输出串起来
- 前置依赖：TASK-13、TASK-14、TASK-15
- 参考文档：`ourclaw/docs/architecture/validation.md`
- 建议修改文件：`framework/src/core/validation/validator.zig`
- 实现要求：支持 request 模式和 config 模式，支持 unknown field 严格检查
- 完成标准：能为命令参数和配置字段生成统一 `ValidationReport`
- 建议验证：综合单元测试

## TASK-17：收缩 `Assert` 到内部不变量用途

- 目标：定义 `assert.zig` 的有限职责，避免与 validator 重叠
- 前置依赖：TASK-16
- 参考文档：`ourclaw/docs/architecture/validation.md`
- 建议修改文件：`framework/src/core/validation/assert.zig`
- 实现要求：只保留开发态不变量检查辅助，不对外部输入返回用户 issue
- 完成标准：模块职责清晰
- 建议验证：编译与少量单元测试

## 7. Epic 05：配置系统与字段注册表

## TASK-18：实现配置字段注册表模型

- 目标：定义 `ConfigFieldDefinition`、`ValueKind`、`RiskLevel`
- 前置依赖：TASK-16
- 参考文档：`ourclaw/docs/architecture/validation.md`、`ourclaw/docs/architecture/overall-design.md`
- 建议修改文件：`ourclaw/src/config/field_registry.zig`
- 实现要求：字段元数据应能服务校验、文档、GUI、重启判断和脱敏
- 完成标准：字段注册表可查询、可枚举
- 建议验证：单元测试覆盖字段查找与元数据读取

## TASK-19：实现配置加载与解析骨架

- 目标：实现 `loader.zig`、`parser.zig`、`defaults.zig`
- 前置依赖：TASK-18
- 参考文档：`ourclaw/docs/architecture/overall-design.md`
- 建议修改文件：`ourclaw/src/config/loader.zig`、`ourclaw/src/config/parser.zig`、`ourclaw/src/config/defaults.zig`
- 实现要求：先建立独立 `~/.ourclaw` 路径约定和最小解析流程
- 完成标准：可读取缺省配置并生成默认对象
- 建议验证：临时目录集成测试

## TASK-20：实现配置交叉字段校验

- 目标：在 `config/validators.zig` 中实现对象级校验
- 前置依赖：TASK-19
- 参考文档：`ourclaw/docs/architecture/validation.md`
- 建议修改文件：`ourclaw/src/config/validators.zig`
- 实现要求：至少覆盖 gateway/logging/provider 三类典型交叉规则
- 完成标准：支持单字段规则之外的对象级检查
- 建议验证：多场景配置校验测试

## TASK-21：实现配置写回与风险确认路径

- 目标：实现受控配置写回流程
- 前置依赖：TASK-18、TASK-19、TASK-20
- 参考文档：`ourclaw/docs/architecture/validation.md`
- 建议修改文件：`ourclaw/src/config/loader.zig`、`ourclaw/src/config/validators.zig`、后续 `config_store` 相关文件
- 实现要求：写回必须经过字段注册表、规则执行、风险确认和差异判断
- 完成标准：配置不能被随意直接写文件
- 建议验证：配置写回集成测试

## TASK-22：实现配置迁移骨架

- 目标：建立 `migration.zig` 和版本化迁移入口
- 前置依赖：TASK-19
- 参考文档：`ourclaw/docs/architecture/overall-design.md`
- 建议修改文件：`ourclaw/src/config/migration.zig`
- 实现要求：先提供版本字段和空迁移链，不急于一次写完全部迁移
- 完成标准：后续兼容旧配置时有稳定落点
- 建议验证：单元测试覆盖 no-op 迁移和版本判断

## 8. Epic 06：Observer 与可观测性接入

## TASK-23：实现 `Observer` 基础抽象

- 目标：从 `nullclaw` 思路抽出 `Observer` 接口和基本事件类型
- 前置依赖：TASK-02
- 参考文档：`ourclaw/docs/architecture/overall-design.md`
- 建议修改文件：`framework/src/observability/observer.zig`
- 实现要求：先聚焦最小事件/指标抽象，避免一开始复制全部旧事件
- 完成标准：可被 runtime 和 logger 周边引用
- 建议验证：单元测试覆盖空 observer 与基本事件调用

## TASK-24：实现 `MultiObserver` 与基础 observer 实现

- 目标：实现多 observer 扇出以及最小 log/file observer 骨架
- 前置依赖：TASK-23
- 参考文档：`ourclaw/docs/architecture/overall-design.md`
- 建议修改文件：`framework/src/observability/multi_observer.zig`、`framework/src/observability/log_observer.zig`、`framework/src/observability/file_observer.zig`
- 实现要求：与日志系统关系清晰，避免 observer 与 logger 完全混同
- 完成标准：关键事件可通过 observer 机制广播
- 建议验证：单元测试覆盖扇出与单点失败隔离

## TASK-25：实现基础指标模型与 flush 生命周期

- 目标：实现 `metrics.zig` 并定义 observer flush/deinit 约定
- 前置依赖：TASK-24
- 参考文档：`ourclaw/docs/architecture/runtime-pipeline.md`
- 建议修改文件：`framework/src/observability/metrics.zig`、相关 observer 文件
- 实现要求：先覆盖请求耗时、活动任务数、队列深度等基础指标
- 完成标准：runtime 生命周期可安全 flush observer
- 建议验证：单元测试与小型集成测试

## 9. Epic 07：统一运行时与命令分发管线

## TASK-26：实现 `AppContext`

- 目标：建立运行时全局依赖容器
- 前置依赖：TASK-12、TASK-25
- 参考文档：`ourclaw/docs/architecture/runtime-pipeline.md`
- 建议修改文件：`framework/src/runtime/app_context.zig`
- 实现要求：注入 logger、observer、config、registry、task runner 等核心依赖
- 完成标准：后续 handler 不再自行组装全局依赖
- 建议验证：初始化/销毁测试

## TASK-27：实现命令注册中心

- 目标：建立 `CommandRegistry` 与命令元数据模型
- 前置依赖：TASK-26
- 参考文档：`ourclaw/docs/architecture/runtime-pipeline.md`
- 建议修改文件：`framework/src/app/command_registry.zig`
- 实现要求：支持 method、authority、execution_mode、params_schema
- 完成标准：可注册和查找命令
- 建议验证：单元测试覆盖查找、重复注册、缺失命令

## TASK-28：实现 `CommandContext`

- 目标：定义 handler 使用的执行上下文
- 前置依赖：TASK-26、TASK-27
- 参考文档：`ourclaw/docs/architecture/runtime-pipeline.md`
- 建议修改文件：`framework/src/app/command_context.zig`
- 实现要求：组合 `AppContext`、`RequestContext`、已校验参数和子系统 logger
- 完成标准：handler 不再直接感知 CLI/bridge 细节
- 建议验证：构造型单元测试

## TASK-29：实现同步 `CommandDispatcher`

- 目标：先打通 method 查找、参数校验、handler 调用和统一错误封装
- 前置依赖：TASK-06、TASK-16、TASK-27、TASK-28
- 参考文档：`ourclaw/docs/architecture/runtime-pipeline.md`
- 建议修改文件：`framework/src/app/command_dispatcher.zig`
- 实现要求：先支持同步命令；必须统一接入 trace、logger、validation、error mapping
- 完成标准：同步命令可通过 dispatcher 稳定执行
- 建议验证：dispatcher 单元测试

## TASK-30：实现 `TaskRunner` 与异步任务模式

- 目标：支持 `async_task` 命令提交、状态跟踪和取消骨架
- 前置依赖：TASK-29
- 参考文档：`ourclaw/docs/architecture/runtime-pipeline.md`
- 建议修改文件：`framework/src/runtime/task_runner.zig`
- 实现要求：先提供任务状态机和最小内存存储，不急于做复杂并发调度
- 完成标准：dispatcher 可把异步命令转成 `task_id`
- 建议验证：任务提交与状态流转测试

## TASK-31：实现 `EventBus`

- 目标：提供运行时事件发布与轮询/订阅基础能力
- 前置依赖：TASK-30
- 参考文档：`ourclaw/docs/architecture/runtime-pipeline.md`
- 建议修改文件：`ourclaw/src/runtime/event_bus.zig`
- 实现要求：先实现内存事件队列和 `seq` 递增，不急于做复杂跨线程订阅
- 完成标准：任务和配置事件可被记录和轮询
- 建议验证：事件发布/查询测试

## 10. Epic 08：配置、日志、诊断类命令落地

## TASK-32：实现 `app.meta` 与 `logs.recent`

- 目标：完成两个最小同步命令，验证 dispatcher + logger + config 基础链路
- 前置依赖：TASK-29、TASK-31
- 参考文档：`ourclaw/docs/architecture/runtime-pipeline.md`
- 建议修改文件：`ourclaw/src/commands/app_meta.zig`、`ourclaw/src/commands/logs_recent.zig`
- 实现要求：输出结构化结果，不要返回原始文本拼接
- 完成标准：命令经统一 dispatcher 执行并返回稳定 envelope
- 建议验证：命令级单元测试/集成测试

## TASK-33：实现 `config.get` 与 `config.set`

- 目标：验证配置读取、字段注册表、校验和风险确认通路
- 前置依赖：TASK-21、TASK-29
- 参考文档：`ourclaw/docs/architecture/validation.md`
- 建议修改文件：`ourclaw/src/commands/config_get.zig`、`ourclaw/src/commands/config_set.zig`
- 实现要求：所有写回都必须经过注册表和验证器
- 完成标准：支持结构化读取与写入结果返回
- 建议验证：配置命令集成测试

## TASK-34：实现 `diagnostics` 与 `service.status` 最小命令

- 目标：建立非配置型业务命令样板
- 前置依赖：TASK-29、TASK-31
- 参考文档：`ourclaw/docs/architecture/overall-design.md`
- 建议修改文件：`ourclaw/src/commands/diagnostics.zig`、`ourclaw/src/commands/service_status.zig`
- 实现要求：先输出结构化最小结果，不急于做全功能诊断
- 完成标准：命令主干可以承载后续更复杂域逻辑
- 建议验证：命令级测试

## 11. Epic 09：扩展点骨架

## TASK-35：实现 provider registry 骨架

- 目标：建立 provider 接口、注册与查找机制
- 前置依赖：TASK-26
- 参考文档：`ourclaw/docs/architecture/overall-design.md`
- 建议修改文件：`ourclaw/src/providers/` 下骨架文件
- 实现要求：先做接口层和 registry，不引入真实 provider 实现复杂度
- 完成标准：runtime 可注册最小 provider stub
- 建议验证：registry 单元测试

## TASK-36：实现 channel registry 骨架

- 目标：建立 channel 接口、注册与查找机制
- 前置依赖：TASK-26
- 参考文档：`ourclaw/docs/architecture/overall-design.md`
- 建议修改文件：`ourclaw/src/channels/` 下骨架文件
- 实现要求：先做元数据和接口，不实现完整 channel runtime
- 完成标准：可注册和枚举 channel stub
- 建议验证：registry 单元测试

## TASK-37：实现 tool registry 骨架

- 目标：建立 tool 接口、注册和调用约定
- 前置依赖：TASK-26
- 参考文档：`ourclaw/docs/architecture/overall-design.md`
- 建议修改文件：`ourclaw/src/tools/` 下骨架文件
- 实现要求：与未来 agent/tool calling 兼容，但第一阶段只做最小注册框架
- 完成标准：tool 元数据和调用签名稳定
- 建议验证：registry 单元测试

## TASK-38：实现 memory registry 骨架

- 目标：建立 memory backend 接口与 registry
- 前置依赖：TASK-26
- 参考文档：`ourclaw/docs/architecture/overall-design.md`
- 建议修改文件：`ourclaw/src/memory/` 下骨架文件
- 实现要求：先抽象 backend 接口，不实现复杂持久化后端
- 完成标准：未来 memory backend 迁移有稳定挂载点
- 建议验证：registry 单元测试

## 12. Epic 10：兼容迁移与旧能力接入

## TASK-39：实现 `nullclaw` 配置导入骨架

- 目标：建立从旧配置读取到新配置对象的基础转换入口
- 前置依赖：TASK-19、TASK-22
- 参考文档：`ourclaw/docs/architecture/overall-design.md`
- 建议修改文件：`ourclaw/src/compat/nullclaw_import.zig`
- 实现要求：先实现兼容读取和报告，不直接覆盖新配置
- 完成标准：可生成导入结果和迁移建议
- 建议验证：使用样例旧配置进行导入测试

## TASK-40：实现兼容迁移报告模型

- 目标：定义导入成功、跳过字段、风险字段、人工确认项的报告结构
- 前置依赖：TASK-39
- 参考文档：`ourclaw/docs/architecture/overall-design.md`
- 建议修改文件：`ourclaw/src/compat/nullclaw_import.zig` 或独立报告文件
- 实现要求：报告必须结构化，便于 CLI/GUI 展示
- 完成标准：导入过程可解释、可审计
- 建议验证：单元测试覆盖不同导入结果场景

## TASK-41：补充兼容层文档与迁移示例

- 目标：把兼容层使用方式补到文档中
- 前置依赖：TASK-39、TASK-40
- 参考文档：`ourclaw/docs/README.md`
- 建议修改文件：新增兼容层说明文档或更新现有 docs
- 实现要求：明确“兼容读取，独立写入”的策略
- 完成标准：后续大模型和人工开发都能按统一迁移策略推进
- 建议验证：文档检查

## 13. 建议的大模型执行顺序

建议按以下顺序投喂：

1. TASK-01 到 TASK-03
2. TASK-04 到 TASK-06
3. TASK-07 到 TASK-12
4. TASK-13 到 TASK-17
5. TASK-18 到 TASK-22
6. TASK-23 到 TASK-25
7. TASK-26 到 TASK-31
8. TASK-32 到 TASK-34
9. TASK-35 到 TASK-38
10. TASK-39 到 TASK-41

## 14. 每个任务都建议附带的固定约束

建议你在给大模型下发任务时，都额外附上这些固定要求：

- 不要跳过现有设计文档
- 不要提前实现未在当前任务范围内的大块业务
- 保持模块边界清晰
- 补上最小单元测试或集成测试
- 不要引入与当前任务无关的重构
- 最终反馈必须包含修改文件路径和验证结果

## 15. 建议的大模型回报格式

建议要求大模型按以下格式回报：

1. 改了什么
2. 改了哪些文件
3. 为什么这样改
4. 跑了什么验证
5. 还有什么未完成或后续依赖

这样后续串行推进多个任务时，可读性和可审查性都会高很多。

## 16. 结论

这份任务拆分的核心目的，是把 `ourclaw` 的建设过程变成一条可串行、可验证、可 review、可持续交给大模型执行的任务链。先把主干做稳，再逐步接业务域，是这套拆分最重要的原则。
