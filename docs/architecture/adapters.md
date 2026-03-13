# ourclaw 入口适配层详细设计

## 1. 目标与范围

本文档定义 `ourclaw` 的入口适配层设计。这里的 adapter 指：

- CLI adapter
- bridge adapter
- HTTP adapter
- future service / manager adapter

其共同目标是：把不同入口协议转成统一内部请求，再交给 `AppContext + CommandDispatcher`。

> 当前最小实现已经落在 `ourclaw/src/interfaces/cli_adapter.zig`、`ourclaw/src/interfaces/bridge_adapter.zig`、`ourclaw/src/interfaces/http_adapter.zig`。截至 2026-03-11，这些仍然属于最小可用版，而不是完整协议版。

## 2. 设计原则

1. adapter 只做协议适配，不做业务逻辑
2. adapter 不直接访问 provider/channel/tool 实现
3. adapter 最终都要转成 `CommandRequest`
4. 输出统一来自 `CommandEnvelope`
5. 流式输出由统一 stream runtime 投影，而不是各入口各写一套

## 3. 适配层职责与非职责

### 3.1 adapter 负责

- 解析外部协议
- 生成 `request_id`
- 标记 `source`
- 附带 authority / caller identity
- 调用 dispatcher
- 将 envelope 投影回入口协议

### 3.2 adapter 不负责

- 参数业务校验
- 权限决策主体逻辑
- provider/tool/channel 直接调用
- 最终业务文本组装

## 4. CLI Adapter

CLI adapter 的职责：

- 把 argv 解析成内部命令请求
- 为本地交互默认附带更高 authority
- 把 `CommandEnvelope` 渲染成 JSON 或人类可读文本

完整版建议支持：

- `ourclaw app.meta`
- `ourclaw config get <path>`
- `ourclaw config set <path> <value>`
- `ourclaw logs recent --limit 20`
- `ourclaw agent run --message "..."`
- `ourclaw agent stream --message "..."`

当前最小实现：

- 已支持 `app.meta`
- 已支持 `config.get`
- 已支持 `config.set`
- 已支持 `logs.recent`

## 5. Bridge Adapter

bridge adapter 的目标是给 GUI / manager / local orchestrator 一个稳定的结构化调用面。

建议输入模型：

```json
{
  "requestId": "req_01",
  "method": "config.get",
  "params": {
    "path": "gateway.port"
  },
  "authority": "operator"
}
```

建议输出保持接近内部 envelope：

```json
{
  "ok": true,
  "result": {},
  "meta": {}
}
```

bridge adapter 完整版还应支持：

- async task accepted
- stream subscription
- session query
- diagnostics / logs / config events

## 6. HTTP Adapter

HTTP adapter 的职责不是自己实现业务 API，而是把路由映射到 command method。

建议映射方式：

- `/v1/app/meta` -> `app.meta`
- `/v1/config/get` -> `config.get`
- `/v1/config/set` -> `config.set`
- `/v1/logs/recent` -> `logs.recent`
- `/v1/agent/run` -> `agent.run`
- `/v1/agent/stream` -> `agent.stream`

完整版还应支持：

- bearer token / pairing token / local token
- 请求体 JSON 解析
- status code 与 `AppError` 的稳定映射
- SSE / WebSocket 流式输出

当前第一版补充：

- `HTTP adapter` 已新增 `/v1/agent/stream/sse`
- 该路由当前会把 `agent.stream` 的结果投影成 `text/event-stream`
- 当前事件序列包含 `meta`、来自 `stream.output` 的 runtime event、`result`、`done`
- 通过 gateway listener 进入时，已可按事件增量 flush，不再要求等整次 agent run 完成后统一返回
- adapter 内部仍保留一个 buffered SSE 渲染路径，主要用于测试和非 socket 场景
- gateway listener 也已新增 `/v1/agent/stream/ws`，当前会把同一批结构化事件按 WebSocket text frame 连续写出
- CLI 当前已支持 `agent.stream --live`，会按 NDJSON 连续写事件
- 当前 live 投影已带最小 `cancel_after_events` / `max_total_bytes` / `max_event_bytes` 语义，用于 cancel/backpressure 第一版保护
- SSE / WebSocket / bridge NDJSON 现在也可直接从 request params 读取 `cancel_after_events`、`max_total_bytes`、`max_event_bytes`
- `text.delta` coalescing/throttle 策略已显式化到 policy：`text_delta_coalesce_event_limit`、`text_delta_coalesce_byte_limit`、`text_delta_throttle_window_ms`
- `done` 终态事件现在会带 `terminalCode`、`terminalReason`、`emittedEvents`、`emittedBytes`，便于上层识别 cancel/backpressure 收口原因
- transport write 失败会优先映射成 `client_disconnect`，不再在已断开的链路上强行回写 error/done
- gateway WebSocket 现在会读取客户端 text / close frame；text 中的 `cancel` 控制消息会映射成流式取消信号，close frame 会映射成 client disconnect
- SSE 现在已补第一版 `Last-Event-ID` 语义：会按 session 回放该序号之后已缓存在 event bus 里的 `stream.output` 事件，并以 replay-only 模式结束，避免重复执行同一轮 agent/tool side effect
- `text.delta` 投影现在已补一版小粒度 coalescing，并支持时间窗口 flush 调度；bridge/CLI live 也已对齐 SSE/WebSocket 的窗口排水行为

### 6.1 WebSocket 入站控制协议（TASK-002）

当前 `gateway_host + http_adapter + stream_projection` 已补齐 WebSocket 控制消息第一版完整语义：

- 支持 `ack / pause / resume / cancel`
- 保持 legacy plain `cancel` 向后兼容
- malformed/unknown payload 不触发控制状态变化

入站控制消息 schema：

```json
{"type":"ack","ackedSeq":7}
{"type":"pause"}
{"type":"resume","resumeFromSeq":5}
{"type":"cancel"}
```

兼容形式：

- 纯文本：`cancel`

不再支持旧的宽松子串匹配（如 `hello cancel world`）；这类 payload 会被忽略。

### 6.2 WebSocket close 语义

- server 侧已支持带 close code/reason 的 close frame 写出
- gateway 读取 client close frame 时会解析 payload（code + optional reason）
- **raw client close code/reason 会在 gateway callback 边界保留并透传**
- 进入 runtime/projection 终态映射时仍归一为 `client_disconnect`（不改变统一终态语义）

### 6.3 CLI / bridge / SSE / WebSocket 对比

| 入口 | 方向性 | 入站控制 | 典型终态收口 |
| --- | --- | --- | --- |
| CLI live | 单向（客户端读） | 无（本地参数控制） | done/error 输出 |
| bridge NDJSON | 单向（客户端读） | 无（当前未定义反向控制） | done/error 行 |
| HTTP SSE | 单向（服务端推） | 无（`Last-Event-ID` 仅重放定位） | done/error event |
| WebSocket | **双向** | `ack/pause/resume/cancel` + close frame | `control.close` + WS close frame |

补充说明：

- SSE / WebSocket / bridge / CLI live 当前都走同一批 text-delta coalescing + time-window flush 策略
- transport 差异主要保留在“是否支持双向控制”（仅 WebSocket）与“终态承载形式”（SSE event / WS frame / NDJSON line）

## 7. Service / Manager Adapter

未来 `ourclaw-manager` 不应直接内嵌全部业务逻辑，而是通过 adapter 协议去驱动 `ourclaw` runtime。

建议 manager adapter 支持：

- command invoke
- config diff / preview
- task subscribe
- stream subscribe
- logs recent / diagnostics / health query

## 8. 输出投影策略

完整业务版建议保持三层：

1. 内部结果：`CommandEnvelope`
2. 入口投影：CLI / bridge / HTTP
3. UI/用户展示层：由入口自己决定样式

示例：

- CLI：可把 `Envelope.success_json` 直接打印，或投影成人类可读文本
- bridge：尽量原样返回 JSON
- HTTP：返回稳定 JSON body + HTTP status

## 9. 流式输出接线

完整版 adapter 需要消费统一 `stream.output` 事件，而不是从 provider 直接读流。

建议：

- CLI：订阅 event bus，增量打印 `text.delta`
- bridge：把 stream event 转成 GUI/manager 可消费的结构
- HTTP：通过 SSE 或 WebSocket 转发

## 10. 当前实现与完整版差距

当前已完成：

- 三类最小 adapter 文件已落地
- 可以驱动最小命令域
- HTTP 已有第一版 `agent.stream` SSE 投影
- bridge 已有第一版 `agent.stream` NDJSON 持续投影
- gateway 已有第一版 `agent.stream` WebSocket 投影
- CLI 已有第一版 `agent.stream --live` 持续订阅投影

当前缺口：

- 没有完整 auth model
- 没有完整 route/method registry
- 没有完整错误状态码映射表
- `stream subscription` 现已补到 HTTP SSE 增量 flush + WebSocket + bridge NDJSON + CLI live 第一版，并已补 request->policy、terminal->client 元数据回传、WebSocket 入站 `ack/pause/resume/cancel/close`、SSE `Last-Event-ID` replay-only、以及 text-delta coalescing + time-window flush；但仍缺真正可恢复继续执行的 reconnect
- 没有 manager/service adapter

## 11. 验收标准

完整版 adapter 至少应满足：

1. 同一命令经 CLI/bridge/HTTP 调用时语义一致
2. error/task accepted/success 三条路径结构稳定
3. 能承载 stream output
4. 不在 adapter 内部复制业务逻辑
