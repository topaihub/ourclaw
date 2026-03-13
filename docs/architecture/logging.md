# ourclaw 日志体系详细设计

## 1. 目标与范围

本文档定义 `ourclaw` 的统一日志体系，目标是解决现有 `nullclaw` 中日志入口分散、结构不统一、文件日志能力不足、trace 无法稳定贯穿的问题，并吸收 `openclaw` 在结构化日志、子系统日志、日志容量治理上的成熟经验。

本文档覆盖：

- 日志数据模型
- logger 与 sink 抽象
- 控制台与文件日志策略
- trace/observer 集成点
- 敏感信息脱敏
- 日志配置模型
- 日志查询与导出边界
- 测试与验收策略

本文档不覆盖：

- OpenTelemetry 协议细节实现
- 远程日志采集后端实现
- GUI 最终展示样式

> 当前共享实现已先落在 `framework/src/core/logging/*`。截至 2026-03-11，`level.zig`、`record.zig`、`sink.zig`、`memory_sink.zig`、`console_sink.zig`、`file_sink.zig`、`multi_sink.zig`、`redact.zig`、`logger.zig` 已有第一版实现；`Logger` 也已补上 trace 上下文自动注入接口。

## 2. 设计目标

`ourclaw` 的日志体系必须满足以下目标：

1. 所有入口共用同一套日志主干
2. 所有日志默认结构化
3. 每条日志都可关联 `trace_id`
4. 控制台日志与文件日志来源一致，只是渲染方式不同
5. 支持子系统维度过滤、级别控制和容量治理
6. 所有敏感信息默认脱敏
7. 日志写入失败不能阻塞主业务
8. 测试环境可替换为内存 sink

## 3. 设计原则

### 3.1 单一事实来源

业务模块不直接决定最终日志格式，只负责提交结构化事件。最终格式由 logger + sink 决定。

### 3.2 结构化优先

日志必须先表达为结构化 `LogRecord`，再根据 sink 渲染为：

- pretty console
- compact console
- JSONL file
- memory buffer

### 3.3 低侵入接入

业务层只应依赖轻量 logger API，例如：

- `logger.info(...)`
- `logger.warn(...)`
- `logger.error(...)`
- `logger.child("providers/openai")`

### 3.4 不让日志失败影响主流程

任何 sink 写入失败都只能：

- 内部记录一次降级状态
- 触发计数器或告警事件
- 绝不能中断主业务 handler

### 3.5 默认可追踪

所有命令请求、服务调用、配置写入、外部适配器处理都应自动带上：

- `trace_id`
- 可选 `span_id`
- `subsystem`
- `request_id`

## 4. 模块边界

建议模块结构如下：

```text
src/core/logging/
  logger.zig
  record.zig
  level.zig
  field.zig
  sink.zig
  console_sink.zig
  file_sink.zig
  memory_sink.zig
  multi_sink.zig
  redact.zig
```

各模块职责建议如下：

- `record.zig`：定义 `LogRecord`、`LogFieldValue`、序列化辅助类型
- `level.zig`：定义日志级别与比较逻辑
- `field.zig`：定义字段编码与轻量追加辅助方法
- `sink.zig`：定义 `LogSink` 接口与公共错误处理约束
- `logger.zig`：定义 `Logger`、`SubsystemLogger`、child logger、上下文注入
- `console_sink.zig`：负责渲染 pretty/compact/json 控制台输出
- `file_sink.zig`：负责 JSONL 文件写入、轮转、大小上限、保留策略
- `memory_sink.zig`：测试与运行时缓存使用
- `multi_sink.zig`：多 sink 扇出
- `redact.zig`：字段级脱敏策略

## 5. 核心数据模型

## 5.1 日志级别

建议定义：

- `trace`
- `debug`
- `info`
- `warn`
- `error`
- `fatal`
- `silent`

比较规则：

- `trace` 最详细
- `fatal` 严重级别最高
- `silent` 表示完全关闭输出

## 5.2 LogRecord

建议定义统一的 `LogRecord`：

```zig
pub const LogRecord = struct {
    ts_unix_ms: i64,
    level: LogLevel,
    subsystem: []const u8,
    message: []const u8,
    trace_id: ?[]const u8 = null,
    span_id: ?[]const u8 = null,
    request_id: ?[]const u8 = null,
    error_code: ?[]const u8 = null,
    duration_ms: ?u64 = null,
    fields: []const LogField = &.{},
};
```

约束：

- `message` 是人可读摘要，不承载全部结构
- 结构化信息尽量放在 `fields`
- `trace_id` 和 `span_id` 是跨入口统一的链路字段
- `error_code` 对齐 `AppError.code`

## 5.3 LogField

建议定义轻量字段模型：

```zig
pub const LogField = struct {
    key: []const u8,
    value: LogFieldValue,
};

pub const LogFieldValue = union(enum) {
    string: []const u8,
    int: i64,
    uint: u64,
    float: f64,
    bool: bool,
    null: void,
};
```

说明：

- 第一阶段不强求完整 JSON value 模型
- 只保留高频基础类型，避免日志系统过重
- 复杂对象需要在业务层先展开为扁平字段

## 5.4 渲染模型

文件日志建议统一输出 JSONL，每行一个 `LogRecord` 投影对象，例如：

```json
{
  "time": "2026-03-11T10:22:45.123+08:00",
  "level": "info",
  "subsystem": "config",
  "message": "config field updated",
  "traceId": "trc_01H...",
  "spanId": "spn_01H...",
  "path": "gateway.port",
  "requiresRestart": true
}
```

控制台日志则由同一条 `LogRecord` 渲染为：

- pretty：适合交互开发
- compact：适合服务输出
- json：适合机器消费

## 6. Logger 抽象设计

## 6.1 顶层 Logger

建议 `Logger` 持有：

- 日志配置快照
- sink 实例
- 默认上下文字段
- 可选 `TraceContextProvider`

典型职责：

- 构建 `LogRecord`
- 合并上下文字段
- 进行脱敏
- 判断是否应写入对应 sink
- 分发到 sink

## 6.2 SubsystemLogger

建议对业务暴露 `SubsystemLogger`，而不是直接暴露全局 logger。

```zig
pub const SubsystemLogger = struct {
    logger: *Logger,
    subsystem: []const u8,
    default_fields: []const LogField,
};
```

建议支持：

- `child(name)`
- `withField(key, value)`
- `withFields(fields)`
- `trace/debug/info/warn/error/fatal`

`child("providers")` + `child("openai")` 应形成稳定子系统路径，例如：

- `providers/openai`
- `channels/telegram`
- `runtime/dispatch`

## 6.3 全局 logger 的生命周期

建议在 `AppContext` 初始化时构建 logger，并在运行期只传递引用，不在 handler 内临时创建 logger 实例。

好处：

- sink 生命周期清晰
- file sink 可统一管理文件句柄和缓冲
- 测试时可整体替换为 memory sink

## 7. Sink 抽象设计

## 7.1 基础接口

建议定义：

```zig
pub const LogSink = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        write: *const fn (ptr: *anyopaque, record: *const LogRecord) void,
        flush: *const fn (ptr: *anyopaque) void,
        deinit: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,
        name: *const fn (ptr: *anyopaque) []const u8,
    };
};
```

第一阶段不让 sink 向上抛错误，而是内部吞掉错误并上报降级状态。

## 7.2 ConsoleSink

`ConsoleSink` 负责：

- 日志级别过滤
- pretty/compact/json 三种样式渲染
- 根据级别写入 stdout 或 stderr
- 必要时清理活动进度行

建议配置项：

- `console.enabled`
- `console.level`
- `console.style`
- `console.timestamps`
- `console.stderr_for_warn_and_error`

## 7.3 JsonlFileSink

`JsonlFileSink` 负责：

- 创建日志目录
- 以 JSONL 追加写入
- 文件大小上限控制
- 日期或序号轮转
- 保留策略清理

建议配置项：

- `file.enabled`
- `file.path`
- `file.max_bytes`
- `file.rotate`
- `file.keep_days`
- `file.keep_files`

文件写入策略建议：

- 首版采用 append 模式
- 可在 runtime 初始化时打开文件句柄并复用
- 遇到写入失败时，仅标记 sink degraded 并输出一次 stderr 提示

## 7.4 MemorySink

`MemorySink` 用于：

- 单元测试
- 集成测试
- 最近日志缓存
- `logs.recent` 的最小实现

建议保留定长 ring buffer，避免无限增长。

## 7.5 MultiSink

`MultiSink` 负责把同一 `LogRecord` 同时分发给多个 sink。典型组合：

- console + file
- console + file + memory
- memory only

要求：

- 单个 sink 失败不影响其他 sink
- 扇出顺序固定
- flush 时逐个调用

## 8. 日志配置模型

建议配置模型如下：

```zig
pub const LoggingConfig = struct {
    level: LogLevel = .info,
    trace_enabled: bool = true,
    redact_mode: RedactMode = .safe,
    console: ConsoleLoggingConfig = .{},
    file: FileLoggingConfig = .{},
    memory: MemoryLoggingConfig = .{},
};
```

建议子配置：

- `ConsoleLoggingConfig`
- `FileLoggingConfig`
- `MemoryLoggingConfig`

推荐默认值：

- CLI 开发模式：console pretty + file jsonl + memory ring
- 服务模式：console compact + file jsonl
- 测试模式：memory only

## 9. Trace 集成

## 9.1 TraceContext 集成方式

logger 不自己生成 `trace_id`，而是从 `TraceContext` 获取当前链路上下文。

建议在 logger 写入前自动读取：

- 当前 `trace_id`
- 当前 `span_id`
- 当前 `request_id`

如果不存在则允许为空，但入口适配层应尽量保证所有请求都创建 `TraceScope`。

## 9.2 TraceSpan 的职责

建议把旧 `TraceLogger` 的思路升级为 `TraceSpan`：

- `init(name)` 时创建 span
- `end_ok()` 记录耗时
- `end_error(err)` 记录耗时和错误码
- 可自动写入一条 span 生命周期日志

`TraceSpan` 不直接写文件，而是借助 `SubsystemLogger` 产生日志记录。

## 10. Observer 集成

logger、observer、trace 之间的关系建议如下：

- logger 负责结构化日志
- observer 负责领域事件和指标
- trace 负责请求关联与耗时范围

推荐接法：

- 关键业务事件同时进入 observer 和 logger
- 日志系统可在必要时桥接一部分 observer 事件，但不让二者完全重合

当前共享实现已先落在：

- `framework/src/observability/log_observer.zig`
- `framework/src/observability/file_observer.zig`
- `framework/src/observability/metrics.zig`

也就是说第一版已经有 log/file/metrics 三类最小 observer 落点。

例如：

- `command.started` 是 observer event
- 同时生成一条 `runtime/dispatch` 的 info 日志

## 11. 敏感信息脱敏设计

## 11.1 原则

默认宁可多遮，不可漏遮。

## 11.2 脱敏范围

至少覆盖：

- API key
- bearer token
- webhook token
- pairing token
- gateway password
- secret provider 返回值
- `authorization`、`cookie` 等头字段

## 11.3 脱敏模式

建议：

- `off`：仅开发调试用，不推荐
- `safe`：默认脱敏敏感字段
- `strict`：更激进的敏感字段清洗

## 11.4 脱敏触发点

必须在 sink 写入前统一执行，不允许交给业务模块自行处理。

建议支持两类策略：

- 基于字段名的脱敏
- 基于子系统或上下文的脱敏

## 12. 日志查询与导出边界

第一阶段建议将日志查询能力限定为：

- 读取最近 N 条
- 按级别过滤
- 导出当前文件日志

对应可支持的命令：

- `logs.recent`
- `logs.export`

建议 `logs.recent` 优先从 `MemorySink` 或最近文件段读取，而不是全量扫描历史日志。

## 13. 错误与降级策略

## 13.1 文件日志失败

当 file sink 写入失败时：

- 标记 sink degraded
- 输出一次 stderr 提示
- 后续继续尝试写入，或根据策略进入短暂抑制窗口

## 13.2 控制台日志失败

控制台写入失败通常不做重试，忽略即可。

## 13.3 格式化失败

如果字段格式化失败，logger 应降级为：

- 保留基础字段
- 丢弃异常字段
- 绝不让格式化失败中断主流程

## 14. 建议 API 草案

```zig
pub fn initLogger(allocator: std.mem.Allocator, config: LoggingConfig) !Logger
pub fn deinit(self: *Logger) void
pub fn child(self: *Logger, subsystem: []const u8) SubsystemLogger

pub fn trace(self: *SubsystemLogger, message: []const u8, fields: []const LogField) void
pub fn debug(self: *SubsystemLogger, message: []const u8, fields: []const LogField) void
pub fn info(self: *SubsystemLogger, message: []const u8, fields: []const LogField) void
pub fn warn(self: *SubsystemLogger, message: []const u8, fields: []const LogField) void
pub fn error(self: *SubsystemLogger, message: []const u8, fields: []const LogField) void
pub fn fatal(self: *SubsystemLogger, message: []const u8, fields: []const LogField) void
```

首版无需过早引入过度复杂的宏式 API，优先保持简单稳定。

## 15. 测试策略

建议覆盖以下测试：

### 15.1 单元测试

- 日志级别比较
- 字段编码与 JSON 序列化
- 子系统 child logger 组合逻辑
- 脱敏规则命中与误伤控制

### 15.2 sink 测试

- console 渲染输出
- file sink 创建目录和追加写入
- max_bytes 超限抑制
- memory ring buffer 覆盖策略
- multi sink 扇出时单点失败隔离

### 15.3 集成测试

- 一个命令请求在 console/file/memory 中产出一致字段
- `trace_id` 在 handler、错误日志、span 日志中一致
- 敏感配置写入时日志不泄露真实值

## 16. 实施顺序建议

建议按以下顺序落地：

1. `level.zig` + `record.zig`
2. `sink.zig` + `memory_sink.zig`
3. `logger.zig` + `child logger`
4. `console_sink.zig`
5. `file_sink.zig`
6. `multi_sink.zig`
7. `redact.zig`
8. `trace` 集成
9. `logs.recent` / `logs.export` 适配

## 17. 验收标准

日志体系完成时，应满足：

- 任意命令请求都有 `trace_id`
- console/file 输出字段一致
- 敏感数据默认脱敏
- 文件日志支持大小上限和目录自动创建
- logger/sink 失败不会中断主业务
- 测试环境可切换到 memory sink

## 18. 结论

`ourclaw` 的日志设计不能只是把 `std.log` 包一层，而应建立一条“结构化记录 -> 脱敏 -> sink 渲染 -> 多后端分发”的统一链路。这样后续无论接 CLI、bridge、service 还是 GUI，都能共享同一套日志主干。
