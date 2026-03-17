# ourclaw 日志记录契约

## 1. 目标

本文档定义 `ourclaw` 的统一日志记录契约，作为 `logger`、`sink`、`logs.recent`、`logs.export`、trace 集成与后续 GUI 展示的共同基础。

当前共享实现已先落在：

- `framework/src/core/logging/level.zig`
- `framework/src/core/logging/record.zig`
- `framework/src/core/logging/sink.zig`
- `framework/src/core/logging/memory_sink.zig`
- `framework/src/core/logging/console_sink.zig`
- `framework/src/core/logging/file_sink.zig`
- `framework/src/core/logging/multi_sink.zig`
- `framework/src/core/logging/redact.zig`
- `framework/src/core/logging/logger.zig`

## 2. 核心结构

建议统一记录结构：

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

## 3. 字段要求

- `ts_unix_ms`：必填，毫秒时间戳
- `level`：必填，日志级别
- `subsystem`：必填，来源子系统，例如 `config`、`runtime/dispatch`
- `message`：必填，人类可读摘要
- `trace_id`：建议在请求链路中始终存在
- `span_id`：有 span 时附带
- `request_id`：适配器层生成
- `error_code`：失败日志建议附带
- `duration_ms`：耗时日志建议附带
- `fields`：附加结构化字段

## 4. LogField 契约

建议：

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

## 5. JSONL 投影格式

文件日志建议使用每行一个 JSON 对象，例如：

```json
{
  "time": "2026-03-11T10:22:45.123+08:00",
  "level": "info",
  "subsystem": "runtime/dispatch",
  "message": "command completed",
  "traceId": "trc_01...",
  "requestId": "req_01...",
  "durationMs": 42,
  "method": "config.set"
}
```

## 6. 子系统命名规则

建议使用小写路径风格：

- `config`
- `runtime/dispatch`
- `providers/openai`
- `channels/telegram`

禁止随意使用不稳定的动态前缀。

## 7. 脱敏要求

在 sink 写入前必须统一执行脱敏，特别是：

- `api_key`
- `token`
- `authorization`
- `cookie`
- 其他敏感 secret 值

## 8. 查询与导出要求

- `logs.recent` 应返回 `LogRecord` 的稳定子集或等价结构
- `logs.export` 应导出 JSONL，不改变基础字段语义

## 8.1 请求级日志约定

截至 2026-03-17，`ourclaw` 的 HTTP / bridge / CLI 已开始统一接入请求级 trace。对这类 started/completed 日志，建议至少稳定包含：

- `trace_id`
- `request_id`
- `source`
- `method`
- `path`
- `query`（可选）
- `status`（completed 时）
- `duration_ms`（completed 时）

建议消息：

- `Request started`
- `Request completed`

## 8.2 步骤级日志约定

截至 2026-03-17，系统也已开始接入步骤级 `StepTrace`。这类日志建议至少包含：

- `step`
- `duration_ms`
- `threshold_ms`（可选）
- `beyond_threshold`
- `error_code`（可选）

建议消息：

- `Step started`
- `Step completed`

## 9. 验收要求

- console/file/memory 输出基于同一 `LogRecord`
- trace 相关字段能稳定贯穿
- 敏感字段默认脱敏
