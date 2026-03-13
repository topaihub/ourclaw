# ourclaw Task State 契约

## 1. 目标

本文档定义 `ourclaw` 的异步任务状态契约，供：

- dispatcher
- task runner
- bridge / HTTP / manager
- diagnostics / logs / GUI

共同复用。

## 2. 状态集合

建议统一状态：

- `queued`
- `running`
- `succeeded`
- `failed`
- `cancelled`

其中：

- `queued`、`running` 为非终态
- `succeeded`、`failed`、`cancelled` 为终态

## 3. 任务记录结构

建议结构：

```json
{
  "id": "task_000001",
  "command": "diagnostics.doctor",
  "requestId": "req_01",
  "state": "running",
  "startedAtMs": 1741687365000,
  "finishedAtMs": null,
  "errorCode": null,
  "result": null
}
```

## 4. 状态迁移规则

| 当前状态 | 允许迁移到 |
|---|---|
| `queued` | `running` / `failed` / `cancelled` |
| `running` | `succeeded` / `failed` / `cancelled` |
| `succeeded` | 终态，不再迁移 |
| `failed` | 终态，不再迁移 |
| `cancelled` | 终态，不再迁移 |

## 5. 接受响应契约

异步命令被接受时，建议返回：

```json
{
  "accepted": true,
  "taskId": "task_000001",
  "state": "queued"
}
```

## 6. 查询契约

建议支持：

- `task.get`：按 `taskId` 查询
- `task.by_request`：按 `requestId` 查询
- `task.list_recent`：查询最近任务

## 7. 当前实现说明

当前共享实现已在 `framework/src/runtime/task_runner.zig` 落地：

- `submit`
- `submitJob`
- `markRunning`
- `markSucceeded`
- `markFailed`
- `cancel`
- `snapshotById`
- `snapshotByRequestId`
- `waitForCompletion`

## 8. 与事件系统的关系

每次任务状态变化都应对应事件：

- `task.queued`
- `task.running`
- `task.succeeded`
- `task.failed`
- `task.cancelled`

## 9. 验收要求

1. 状态集合与迁移规则稳定
2. task accepted / task query / task event 三端语义一致
3. 所有终态都可携带稳定错误码或结果摘要
