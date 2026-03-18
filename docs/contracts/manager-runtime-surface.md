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
2. `gateway.auth.status`
3. `gateway.remote.status`
4. `gateway.remote.policy.status`
5. `service.status`
6. `heartbeat.status`
7. `status.all`
8. `session.get`
9. `diagnostics.summary`
10. `diagnostics.remediate_preview` / `diagnostics.remediate_apply`
11. `metrics.summary`
12. `logs.recent`
13. `events.poll`
14. `devices.list`
15. `onboard.summary`
16. `node.list` / `node.describe` / `node.invoke`
17. `task.get` / `task.by_request`
18. `observer.recent`

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

## 5.1 `gateway.auth.status`

### stable

- `requirePairing`
- `pendingPairings`
- `approvedPairings`
- `sharedTokenSupported`
- `sharedTokenConfigured`
- `tokenLifecycleAvailable`
- `passwordSupported`
- `passwordConfigured`
- `remoteAccessSupported`
- `bindHost`
- `bindPort`
- `gatewayRunning`
- `nextAction`

## 5.2 `gateway.remote.status`

### stable

- `tunnelActive`
- `tunnelKind`
- `tunnelEndpoint`
- `tunnelHealthState`
- `tunnelHealthMessage`
- `sharedTokenConfigured`
- `localAccessUrl`
- `nextAction`

## 5.3 `gateway.remote.policy.status`

### stable

- `remoteEnabled`
- `defaultEndpoint`
- `revokeTokenOnDisable`

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

说明：`ourclaw-manager` 的 typed runtime client 应优先只绑定以上 stable 字段；这些 provisional 字段可继续通过原始 JSON / 调试路径使用，但不应纳入稳定 typed snapshot。

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

## 8.1 `diagnostics.remediate_preview` / `diagnostics.remediate_apply`

### stable

- `action`
- `wouldChange` (`preview`)
- `requiresRestart` (`preview`)
- `summary` (`preview`)
- `applied` (`apply`)

### provisional

- `changed`
- `installed`
- `active`
- `endpoint`
- `gatewayRequirePairing`
- `token`
- `errorCode`

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

## 12.1 `devices.list`

### stable

- `requirePairing`
- `pairing.total`
- `pairing.pending`
- `pairing.approved`
- `nodes.total`
- `nodes.ready`
- `nodes.broken`
- `peripherals.total`
- `peripherals.ready`
- `peripherals.broken`

## 12.2 `onboard.summary`

### stable

- `readyCount`
- `totalChecks`
- `secretsConfigured`
- `providersAvailable`
- `gatewayPairingEnabled`
- `serviceInstalled`
- `devicesReady`
- `pendingPairingCount`
- `nextStep`

## 12.3 `node.list` / `node.describe` / `node.invoke`

### stable

- `id`
- `label`
- `kind`
- `healthState`
- `healthMessage`
- `probeCount`
- `lastCheckedMs`
- `lastErrorCode`

### provisional

- `registeredAtMs`
- `approvedPairingCount`
- `action` (`node.invoke`)

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
  - `ourclaw/src/commands/gateway_auth_status.zig`
  - `ourclaw/src/commands/gateway_remote_status.zig`
  - `ourclaw/src/commands/gateway_remote_policy_status.zig`
  - `ourclaw/src/commands/service_status.zig`
  - `ourclaw/src/commands/heartbeat_status.zig`
  - `ourclaw/src/commands/status_all.zig`
  - `ourclaw/src/commands/session_get.zig`
  - `ourclaw/src/commands/diagnostics_remediate_preview.zig`
  - `ourclaw/src/commands/diagnostics_remediate_apply.zig`
  - `ourclaw/src/commands/devices_list.zig`
  - `ourclaw/src/commands/onboard_summary.zig`
  - `ourclaw/src/commands/node_list.zig`
  - `ourclaw/src/commands/node_describe.zig`
  - `ourclaw/src/commands/node_invoke.zig`
- manager typed reader：
  - `ourclaw-manager/src/runtime_client/types.zig`
  - `ourclaw-manager/src/runtime_client/status_client.zig`
  - `ourclaw-manager/src/runtime_client/node_client.zig`
  - `ourclaw-manager/src/runtime_client/memory_client.zig`
  - `ourclaw-manager/src/runtime_client/diagnostics_client.zig`
  - `ourclaw-manager/src/runtime_client/events_client.zig`
  - `ourclaw-manager/src/runtime_client/onboard_client.zig`
  - `ourclaw-manager/src/runtime_client/devices_client.zig`
  - `ourclaw-manager/src/view_models/status_view_model.zig`
  - `ourclaw-manager/src/view_models/diagnostics_view_model.zig`
  - `ourclaw-manager/src/view_models/logs_view_model.zig`
  - `ourclaw-manager/src/view_models/onboard_view_model.zig`
  - `ourclaw-manager/src/view_models/devices_view_model.zig`
  - `ourclaw-manager/src/view_models/nodes_view_model.zig`

## 15. 当前结论

当前已经把 **status / session / diagnostics / metrics / logs / events / task / observer / devices / onboarding / gateway auth / gateway remote / nodes** 这些 manager 常用面推进到“文档稳定矩阵 + runtime_client typed reader + 部分 view model typed 消费”三层闭环。

仍需注意：

- `status / diagnostics / logs` 已开始在 view model 中持有 typed snapshot
- `events / task / observer` 目前 typed reader 已就位，但 manager 侧消费面仍可继续深化
