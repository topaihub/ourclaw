# ourclaw 对照 nullclaw 的能力差距分析

> 使用说明（2026-03-13）：本文档主要用于保留 `nullclaw` 对照分析、能力矩阵与历史 gap 判断。当前继续推进主线开发时，请优先参考新 spec：
>
> - `ourclaw/docs/specs/framework-based-ourclaw/requirements.md`
> - `ourclaw/docs/specs/framework-based-ourclaw/design.md`
> - `ourclaw/docs/specs/framework-based-ourclaw/tasks.md`
>
> 尤其是涉及“当前状态”与“任务状态”时，应以新 spec 和最新代码为准，本文更适合作为参考背景而非唯一执行入口。

## 1. 目的

本文档用于回答两个问题：

1. `nullclaw` 现在已经具备哪些能力。
2. `ourclaw` 当前已经完成哪些，距离“接近 `nullclaw` 的完整业务版”还差哪些。

本文档同时作为后续交给大模型继续开发的任务基线。

## 2. 分析范围

- 参考实现：`nullclaw/README.md` 与 `nullclaw/src/`
- 当前目标实现：`framework/`、`ourclaw/`
- 本文只判断“结构与能力落点”，不评价性能数字与营销口径

## 3. nullclaw 模块盘点

### 3.1 核心入口与装配

- `nullclaw/src/main.zig`：CLI 主入口，覆盖 agent、gateway、service、status、doctor、cron、skills、hardware、migrate 等命令面
- `nullclaw/src/root.zig`：模块总导出，明确 provider、channel、tool、memory、security、runtime、observability、mcp、subagent、peripherals、tunnel 等一级边界
- `nullclaw/src/config.zig`、`nullclaw/src/config_parse.zig`、`nullclaw/src/config_types.zig`：统一配置系统

### 3.2 Agent / Session / 编排

- `nullclaw/src/agent/`：agent loop、prompt、memory 注入、tool dispatch、上下文压缩
- `nullclaw/src/session.zig`：会话状态持久化
- `nullclaw/src/subagent.zig`、`nullclaw/src/subagent_runner.zig`：子任务/子代理执行
- `nullclaw/src/streaming.zig`：流式输出主干

### 3.3 Provider 子系统

- `nullclaw/src/providers/root.zig`：Provider vtable 与共享类型
- `nullclaw/src/providers/factory.zig`：核心 provider 与 OpenAI-compatible provider registry
- `nullclaw/src/providers/router.zig`、`reliable.zig`、`sse.zig`：provider 路由、可靠性、流式能力

### 3.4 Channel / Gateway 子系统

- `nullclaw/src/channels/`：Telegram、Discord、Slack、Signal、WhatsApp、IRC、Email、Nostr、Line、OneBot、QQ、Mattermost、Web 等多通道
- `nullclaw/src/channel_catalog.zig`：channel 元数据
- `nullclaw/src/channel_manager.zig`、`channel_loop.zig`：channel 生命周期与监听主干
- `nullclaw/src/gateway.zig`：HTTP gateway / webhook / pairing / ingress runtime

### 3.5 Tool 子系统

- `nullclaw/src/tools/root.zig`：Tool vtable 与工具注册入口
- `nullclaw/src/tools/*.zig`：shell、file、git、web、browser、memory、cron、hardware、delegate/spawn 等丰富工具面

### 3.6 Memory 子系统

- `nullclaw/src/memory/root.zig`
- `nullclaw/src/memory/engines/registry.zig`
- `nullclaw/src/memory/retrieval/engine.zig`
- `nullclaw/src/memory/vector/*`
- `nullclaw/src/memory/lifecycle/*`

这说明 nullclaw 的 memory 不是单 backend，而是完整 retrieval + vector + lifecycle 系统。

### 3.7 Security / Runtime / Service

- `nullclaw/src/security/`：policy、pairing、secrets、sandbox、audit
- `nullclaw/src/runtime.zig`：native / docker / wasm runtime
- `nullclaw/src/service.zig`、`daemon.zig`：长期运行、服务安装、守护进程
- `nullclaw/src/tunnel.zig`：cloudflare / tailscale / ngrok / custom tunnel

### 3.8 Skills / Cron / Hardware / MCP

- `nullclaw/src/cron.zig`：定时任务与一次性任务
- `nullclaw/src/skills.zig`、`skillforge.zig`：skills 装载、安装、发现与评估
- `nullclaw/src/hardware.zig`、`peripherals.zig`：硬件与外设
- `nullclaw/src/mcp.zig`：MCP server 集成
- `nullclaw/src/voice.zig`：语音转写能力

## 4. nullclaw 功能矩阵

| 类别 | nullclaw 状态 | 结构落点 |
|---|---|---|
| CLI 命令面 | 已完整 | `src/main.zig` |
| App/Runtime 装配 | 已完整 | `src/root.zig` + config/runtime/service |
| Provider registry | 已完整 | `src/providers/*` |
| Channel registry/runtime | 已完整 | `src/channels/*` + `channel_manager.zig` |
| Tool registry/runtime | 已完整 | `src/tools/*` |
| Agent loop | 已完整 | `src/agent/*` |
| Streaming | 已完整 | `src/streaming.zig` |
| Session state | 已完整 | `src/session.zig` |
| Memory/retrieval/vector | 已完整 | `src/memory/*` |
| Gateway/Webhook | 已完整 | `src/gateway.zig` |
| Pairing/Auth/Secrets | 已完整 | `src/security/*` |
| Sandbox/Policy/Audit | 已完整 | `src/security/*` |
| Service/Daemon | 已完整 | `src/service.zig`、`src/daemon.zig` |
| Cron/Heartbeat | 已完整 | `src/cron.zig`、`src/heartbeat.zig` |
| Skills/SkillForge | 已完整 | `src/skills.zig`、`src/skillforge.zig` |
| Observability | 已完整 | `src/observability.zig` |
| Tunnel | 已完整 | `src/tunnel.zig` |
| MCP | 已完整 | `src/mcp.zig` |
| Hardware/Peripheral | 已完整 | `src/hardware.zig`、`src/peripherals.zig` |
| Voice | 已落地 | `src/voice.zig` |

## 5. ourclaw 当前完成度矩阵

状态说明：

- `已完成`：已经有可工作的最小实现
- `最小版`：已经能跑通主链路，但能力远未对齐 `nullclaw`
- `未完成`：还没有真正业务实现

| 类别 | ourclaw 当前状态 | 说明 |
|---|---|---|
| 共享错误/日志/校验/事件/任务 | 已完成 | 主要在 `framework/src/*` |
| AppContext / 统一运行时装配 | 已完成 | `framework/src/runtime/app_context.zig` + `ourclaw/src/runtime/app_context.zig` |
| Provider registry | 最小版 | 只有 builtin stub，无真实 provider 行为 |
| Channel registry | 最小版 | 只有 registry，无真实 channel runtime |
| Tool registry | 最小版 | 只有 `echo` / `clock` stub |
| CLI adapter | 最小版 | `ourclaw/src/interfaces/cli_adapter.zig` |
| Bridge adapter | 最小版 | `ourclaw/src/interfaces/bridge_adapter.zig` |
| HTTP adapter | 最小版 | `ourclaw/src/interfaces/http_adapter.zig` |
| 命令域：app.meta | 最小版 | 已可工作 |
| 命令域：config.get | 最小版 | 已可工作 |
| 命令域：config.set | 最小版 | 已可工作 |
| 命令域：logs.recent | 最小版 | 已可工作 |
| Config field registry | 最小版 | 只覆盖少量字段 |
| Security policy / secret store | 最小版 | 只覆盖少量 authority/secret 规则 |
| Session state | 最小版 | 仅最小事件存储 |
| Stream output | 最小版 | 仅最小事件投递 |
| Tool orchestration | 最小版 | 仅最小 invoke + stream output |
| Agent loop | 未完成 | 没有完整 agent runtime |
| Streaming 对话主链路 | 未完成 | 没有完整 token/step stream 协议 |
| Memory / retrieval / embeddings | 未完成 | 目前未落业务 memory 子系统 |
| Gateway | 未完成 | 只有最小 HTTP adapter，不是完整 gateway |
| Service / daemon | 未完成 | 没有 ourclaw 自己的长期运行模型 |
| Cron / heartbeat | 未完成 | 未落 ourclaw 业务层 |
| Skills | 未完成 | 未落 ourclaw 业务层 |
| Tunnel | 未完成 | 未落 ourclaw 业务层 |
| MCP | 未完成 | 未落 ourclaw 业务层 |
| Hardware / peripheral | 未完成 | 未落 ourclaw 业务层 |
| Voice | 未完成 | 未落 ourclaw 业务层 |

## 6. Gap Matrix

### 6.1 已完成项

- 共享运行时横切主干：日志、校验、错误、事件、任务、配置写回、AppContext
- ourclaw 最小业务层骨架：provider/channel/tool registry、security policy、config field registry
- 最小入口适配：CLI / bridge / HTTP
- 第一批最小命令：`app.meta`、`config.get`、`config.set`、`logs.recent`
- 最小 session / stream / tool orchestration 骨架

### 6.2 部分完成项

- provider：有 registry，没有真实 provider chat/completion/streaming
- channel：有 registry，没有真实 start/stop/listen/send runtime
- tool：有 registry，但工具能力还只是 stub，不是 nullclaw 那样的完整行动面
- config：有 field registry，但字段覆盖远小于 nullclaw
- security：有最小 authority/secret 规则，但没有 sandbox/pairing/audit/full approval flow
- interfaces：有 adapter，但不是完整协议实现

### 6.3 未完成项

- agent loop / planner / prompt / compaction
- message/session streaming 主链路
- memory backend / retrieval / embeddings / migration
- gateway / service / daemon / background runtime
- cron / heartbeat / skills / skillforge
- tunnel / mcp / peripherals / hardware / voice

## 7. 面向大模型的任务清单

### Phase A：把最小业务层从“骨架”推进到“可持续开发”

| ID | 任务 | 状态 |
|---|---|---|
| GAP-01 | 扩展 `ourclaw/src/config/field_registry.zig`，覆盖更多配置字段 | 未完成 |
| GAP-02 | 扩展 `ourclaw/src/security/policy.zig`，补 pairing / approval / sandbox policy 接口 | 未完成 |
| GAP-03 | 把 `app.meta`、`config.get`、`config.set`、`logs.recent` 从最小可用版推进到完整业务版 | 未完成 |
| GAP-04 | 细化 CLI / bridge / HTTP 的输入输出协议与错误投影 | 未完成 |

### Phase B：补全 registry 背后的真实业务能力

| ID | 任务 | 状态 |
|---|---|---|
| GAP-05 | 实现最小真实 provider（先做一个 OpenAI-compatible provider） | 未完成 |
| GAP-06 | 实现最小真实 channel（先做 CLI chat channel） | 未完成 |
| GAP-07 | 实现最小真实 tool set（file/shell/http 的安全版） | 未完成 |
| GAP-08 | 把 provider/channel/tool registry 接入真实 runtime 行为 | 未完成 |

### Phase C：补 agent 运行主链路

| ID | 任务 | 状态 |
|---|---|---|
| GAP-09 | 设计并实现 `agent-runtime`，补 request → model → tool → memory 主循环 | 未完成 |
| GAP-10 | 实现 session 生命周期与对话 state store | 部分完成 |
| GAP-11 | 实现真正的 streaming 输出协议 | 未完成 |
| GAP-12 | 实现 tool orchestration 的多步调用与失败恢复 | 部分完成 |

### Phase D：补长期运行与控制面

| ID | 任务 | 状态 |
|---|---|---|
| GAP-13 | 实现 ourclaw gateway/runtime host | 未完成 |
| GAP-14 | 实现 service/daemon 模型 | 未完成 |
| GAP-15 | 实现 task query / diagnostics / health surface | 部分完成 |
| GAP-16 | 实现 config mutation 的完整副作用与 restart lifecycle | 部分完成 |

### Phase E：补 nullclaw 的高级能力面

| ID | 任务 | 状态 |
|---|---|---|
| GAP-17 | 实现 memory backend / retrieval / embeddings | 未完成 |
| GAP-18 | 实现 cron / heartbeat | 未完成 |
| GAP-19 | 实现 skills / skillforge | 未完成 |
| GAP-20 | 实现 tunnel / mcp / peripherals / voice | 未完成 |

## 8. 推荐开发顺序

建议严格按这个顺序交给大模型推进：

1. GAP-01 ~ GAP-04
2. GAP-05 ~ GAP-08
3. GAP-09 ~ GAP-12
4. GAP-13 ~ GAP-16
5. GAP-17 ~ GAP-20

## 9. 当前结论

- `ourclaw` 现在已经拥有“共享运行时 + 最小业务层”的可运行骨架
- 这足以继续承载后续 agent 业务开发
- 但距离 `nullclaw` 的完整能力，仍然有明显差距
- 当前最现实的策略不是“直接追全功能”，而是按上述 gap tasks 分阶段推进

## 10. 给大模型的使用建议

如果后续把任务交给大模型，建议使用本文档时遵循：

1. 一次只做一个 GAP 任务或一个非常小的任务组合
2. 先补契约、类型和测试，再补深实现
3. 每完成一个阶段，都更新 `ourclaw/docs/planning/session-resume.md`
4. 所有新增设计判断必须及时写入 `docs/`，不要只留在对话上下文
