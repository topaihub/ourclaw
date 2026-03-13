# ourclaw 命令信封契约

## 1. 目标

本文档定义 `ourclaw` 的统一请求/响应信封契约，供 CLI 适配层、bridge、HTTP 与未来 manager 集成复用。

## 2. 内部请求模型

建议统一内部请求模型：

```zig
pub const CommandRequest = struct {
    request_id: []const u8,
    method: []const u8,
    params_json: []const u8,
    source: RequestSource,
    timeout_ms: ?u32 = null,
};
```

建议 `RequestSource` 包含：

- `cli`
- `bridge`
- `http`
- `service`
- `test`

当前共享实现已先落在 `framework/src/contracts/envelope.zig`。

由于 Zig 中 `error` 是关键字，内部 `Envelope<T>` 结构字段当前使用 `app_error` 表示失败分支；在 CLI/bridge/HTTP 的外部投影中，仍应保持本文档约定的 `error` 字段名。

## 3. 外部成功响应契约

建议统一成功响应：

```json
{
  "ok": true,
  "result": {},
  "meta": {
    "requestId": "req_01...",
    "traceId": "trc_01...",
    "durationMs": 42
  }
}
```

## 4. 外部失败响应契约

建议统一失败响应：

```json
{
  "ok": false,
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "request validation failed",
    "userMessage": "输入参数不符合要求"
  },
  "meta": {
    "requestId": "req_01...",
    "traceId": "trc_01...",
    "durationMs": 7
  }
}
```

## 5. 异步任务接受响应

对于异步命令，建议返回：

```json
{
  "ok": true,
  "result": {
    "accepted": true,
    "taskId": "task_01...",
    "state": "queued"
  },
  "meta": {
    "requestId": "req_01...",
    "traceId": "trc_01...",
    "durationMs": 3
  }
}
```

## 6. 命名与约束

- `method` 使用 `domain.action` 风格
- `params` 必须是对象语义
- 未知字段默认拒绝
- 所有请求都应有 `request_id`

## 7. Meta 契约

建议 `meta` 至少支持：

- `requestId`
- `traceId`
- `durationMs`

后续可扩展：

- `taskId`
- `warnings`
- `version`

## 8. 与 CLI/bridge/HTTP 的关系

- CLI 可以在边界层把 `Envelope` 渲染为文本
- bridge 应尽量原样返回 JSON envelope
- HTTP 应返回等价 JSON body

它们不能各自发明不同的业务响应结构。

## 9. 验收要求

- 同一命令经不同入口调用，结构化结果语义一致
- success/error/task accepted 三种路径格式稳定
- `meta` 中的 request/trace 信息可追踪
