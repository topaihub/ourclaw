# ourclaw → ourclaw-manager 稳定契约面（第一版）

## 1. 目的

本文件定义 `ourclaw-manager` 在 MVP / 早期集成阶段应优先依赖的 runtime 稳定字段面。

它的作用不是替代统一 envelope 契约，而是回答：

- manager 当前可以稳定绑定哪些字段
- 哪些字段仍应视为 provisional
- 后续 `runtime_client` typed reader 应以什么为准

## 2. 使用规则

- `stable`：允许 manager 直接绑定、显示、做轻量逻辑判断
- `provisional`：允许显示或调试使用，但不要作为强耦合业务逻辑前提
- 若 runtime 需要变更 `stable` 字段，应同步更新本文档和 manager typed reader

## 3. 稳定化范围

当前已锁定并开始 typed 化的面：

1. `gateway.status`
2. `service.status`
3. `heartbeat.status`
4. `session.get`
5. `diagnostics.summary`
6. `metrics.summary`
7. `logs.recent`
8. `events.poll`
9. `task.get` / `task.by_request`
10. `observer.recent`

## 4. `gateway.status`

### stable

- `running`
- `listenerReady`
- `bindHost`
- `bindPort`
- `handlerAttached`
- `requestCount`
- `activeConnections`
- `streamSubscriptions`

### provisional

- `reloadCount`
- `lastStartedMs`
- `lastReloadedMs`
- `lastStoppedMs`

## 5. `service.status`

### stable

- `serviceState`
- `installed`
- `enabled`
- `autostart`
- `daemonState`
- `restartBudgetRemaining`
- `gatewayRunning`
- `hostRunning`
- `hostLoopActive`
- `gatewayHandlerAttached`
- `bindHost`
- `bindPort`

### provisional

- `daemonProjected`
- `pid`
- `lockHeld`
- `staleProcessDetected`
- `installCount`
- `startCount`
- `stopCount`
- `restartCount`
- `hostStartCount`
- `hostTickCount`

## 6. `heartbeat.status`

### stable

- `beatCount`
- `healthy`
- `lastBeatMs`
- `ageMs`
- `staleAfterMs`

## 7. `session.get`

### stable

- `sessionId`
- `eventCount`
- `memoryEntryCount`
- `toolTraceCount`
- `lastEventKind`
- `providerId`
- `model`
- `lastToolId`
- `toolRounds`
- `providerLatencyMs`
- `memoryEntriesUsed`
- `lastErrorCode`
- `summaryText`
- `summarySourceCount`

### provisional

- `latestSummaryEvent`
- `latestAssistantResponse`
- `latestToolResult`
- `providerRoundBudget`
- `providerRoundsRemaining`
- `providerAttemptBudget`
- `providerAttemptsRemaining`
- `toolCallBudget`
- `toolCallsRemaining`
- `providerRetryBudget`
- `totalDeadlineMs`

## 8. `diagnostics.summary`

### stable

- `providers`
- `channels`
- `tools`
- `commands`
- `configEntries`
- `sessions`
- `memoryEntries`
- `observerEvents`
- `tasks.total`
- `tasks.queued`
- `tasks.running`
- `events.latestSeq`
- `events.subscriptions`

### provisional

- `runtimeHost.*`
- `service.*`
- `metrics.*`

## 9. `metrics.summary`

### stable

- `totalEvents`
- `commandStarted`
- `commandCompleted`
- `commandFailed`
- `activeTasks`
- `queueDepth`
- `maxQueueDepth`
- `correlatedStreamEvents`
- `lastExecutionId`
- `lastSessionId`

### provisional

- `commandAccepted`
- `configChanged`
- `taskQueued`
- `taskRunning`
- `taskSucceeded`
- `taskFailed`
- `taskResultsWritten`
- `subscriptionCount`

## 10. `logs.recent`

### stable

- `count`
- `items[].level`
- `items[].subsystem`
- `items[].message`
- `items[].errorCode`

### provisional

- `limit`
- `filters`
- `items[].tsUnixMs`
- `items[].traceId`
- `items[].requestId`
- `items[].durationMs`

## 11. `events.poll`

### stable

- `subscriptionId`
- `lastSeq`
- `hasMore`
- `eventCount`
- `events[].topic`
- `events[].executionId`
- `events[].sessionId`

### provisional

- `events[].payload`

## 12. `task.get` / `task.by_request`

### stable

- `taskId`
- `command`
- `requestId`
- `state`
- `errorCode`

### provisional

- `result`

说明：`ourclaw-manager` 的 typed runtime client 不应把 `result` 纳入稳定 typed snapshot；如需显示或调试，应继续通过原始 JSON/result envelope 读取。

## 13. `observer.recent`

### stable

- `totalCount`
- `returnedCount`
- `events[].topic`
- `events[].tsUnixMs`
- `events[].executionId`
- `events[].sessionId`

### provisional

- `events[].payload`

## 14. 当前代码落点

- runtime 命令面：
  - `ourclaw/src/commands/gateway_status.zig`
  - `ourclaw/src/commands/service_status.zig`
  - `ourclaw/src/commands/heartbeat_status.zig`
  - `ourclaw/src/commands/session_get.zig`
- manager typed reader：
  - `ourclaw-manager/src/runtime_client/types.zig`
  - `ourclaw-manager/src/runtime_client/status_client.zig`
  - `ourclaw-manager/src/runtime_client/memory_client.zig`
  - `ourclaw-manager/src/runtime_client/diagnostics_client.zig`
  - `ourclaw-manager/src/runtime_client/events_client.zig`
  - `ourclaw-manager/src/view_models/status_view_model.zig`
  - `ourclaw-manager/src/view_models/diagnostics_view_model.zig`
  - `ourclaw-manager/src/view_models/logs_view_model.zig`

## 15. 当前结论

`B5` 当前已经把 **status / session / diagnostics / metrics / logs / events / task / observer** 这些 manager 常用面推进到“文档稳定矩阵 + runtime_client typed reader + 部分 view model typed 消费”三层闭环。

仍需注意：

- `status / diagnostics / logs` 已开始在 view model 中持有 typed snapshot
- `events / task / observer` 目前 typed reader 已就位，但 manager 侧消费面仍可继续深化
