# ourclaw Runtime Event 契约

## 1. 目标

本文档定义 `ourclaw` 运行时事件契约，供：

- event bus
- observer
- stream output
- diagnostics
- future GUI / manager

共同复用。

## 2. 顶层事件结构

建议统一结构：

```json
{
  "seq": 12,
  "topic": "command.completed",
  "tsUnixMs": 1741687365000,
  "payload": {}
}
```

字段说明：

- `seq`：单调递增序号
- `topic`：事件主题
- `tsUnixMs`：事件时间
- `payload`：主题相关负载

## 3. 主题建议

### 3.1 command

- `command.started`
- `command.completed`
- `command.failed`
- `command.accepted`
- `command.validation_failed`

### 3.2 task

- `task.queued`
- `task.running`
- `task.succeeded`
- `task.failed`
- `task.cancelled`

### 3.3 config

- `config.changed`
- `config.validation_failed`

### 3.4 stream

- `stream.output`

### 3.5 future

- `provider.health_changed`
- `channel.started`
- `channel.stopped`
- `memory.updated`
- `diagnostics.updated`

## 4. command 负载建议

```json
{
  "method": "app.meta",
  "requestId": "req_01",
  "source": "cli",
  "authority": "admin",
  "commandId": "app.meta",
  "executionMode": "sync",
  "errorCode": null,
  "taskId": null,
  "traceId": "trc_01",
  "durationMs": 7
}
```

## 5. task 负载建议

```json
{
  "taskId": "task_000001",
  "command": "diagnostics.doctor",
  "state": "running",
  "requestId": "req_01",
  "startedAtMs": 1741687365000,
  "finishedAtMs": null,
  "durationMs": null,
  "errorCode": null,
  "result": null
}
```

## 6. config 负载建议

```json
{
  "updateCount": 2,
  "changedCount": 1,
  "requiresRestart": false,
  "sideEffectCount": 1,
  "postWriteHookCount": 1
}
```

## 7. stream.output 负载建议

```json
{
  "sessionId": "sess_01",
  "kind": "text.delta",
  "payload": {
    "text": "hello"
  }
}
```

## 8. 订阅语义

完整版建议支持两种拉取方式：

1. `pollAfter(seq)`：按全局序号拉取
2. `pollSubscription(subscription_id, limit)`：按订阅 cursor 拉取

## 9. 当前实现说明

当前共享实现已经在 `framework/src/runtime/event_bus.zig` 落地：

- `publish`
- `snapshot`
- `pollAfter`
- `subscribe`
- `pollSubscription`
- `unsubscribe`

## 10. 验收要求

1. 事件主题稳定
2. payload 字段命名稳定
3. observer / event bus / stream output 之间语义一致
