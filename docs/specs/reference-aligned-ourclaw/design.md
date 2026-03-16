# reference-aligned-ourclaw — Design

## 1. 设计目标

本设计服务于两个目标：

1. 用单一 active spec 取代当前“spec + backlog + planning + architecture 混合充当主入口”的状态
2. 把 `framework / ourclaw / ourclaw-manager` 与 `nullclaw / openclaw` 的关系显式化，形成长期执行设计

## 2. 文档体系设计

### 2.1 分层

- `docs/README.md`：总入口
- `docs/specs/reference-aligned-ourclaw/`：当前 active spec
- `docs/specs/framework-based-ourclaw/`：phase-1 baseline
- `docs/architecture/`、`docs/contracts/`：supporting docs
- `docs/planning/`：恢复说明与历史参考

### 2.2 单一默认入口链

默认入口固定为：

1. `requirements.md`
2. `design.md`
3. `tasks.md`

## 3. 三层落点模型

### 3.1 framework

承载：

- dispatcher / task runner / event bus / observer
- envelope / app error / shared contracts
- validation / config pipeline / shared runtime adapter

### 3.2 ourclaw

承载：

- business runtime / gateway / service / daemon
- agent / session / memory / stream / provider / tool / channel
- skills / tunnel / mcp / hardware / peripheral / voice
- diagnostics / events / metrics / logs / tasks / observer consumption

### 3.3 ourclaw-manager

承载：

- runtime_client
- typed contract consumption
- host / services / view_models

## 4. 参考设计

### 4.1 nullclaw 参考角色

`nullclaw` 主要提供：

- Zig-first runtime 边界
- provider/channel/tool/memory/stream/security 的 vtable 风格
- session / bus / agent runtime / streaming 的运行时组织方式

### 4.2 openclaw 参考角色

`openclaw` 主要提供：

- gateway 作为统一控制平面
- 多渠道 / 多 agent / 多节点的产品语义
- config schema / reload / wizard / daemon / diagnostics / control UI 的治理思路

### 4.3 设计写法规则

每个能力域写清：

- 当前落点
- `nullclaw` 参考锚点
- `openclaw` 参考锚点
- 本阶段目标
- 非目标

## 5. 能力映射

| 能力域 | 主线落点 | nullclaw 参考 | openclaw 参考 | 目的 |
|---|---|---|---|---|
| 共享 runtime/contracts | `framework/src/*` | runtime/bus/interface 模式 | 控制面不直接落此层 | 稳定共享基础 |
| agent/session/memory | `ourclaw/src/domain/*` | agent/session/memory | session/control-plane 语义 | 深化业务核心 |
| provider/tool/stream | `ourclaw/src/providers/*` `src/tools/*` `src/domain/stream_*` | provider/tool/streaming | models/tools/control semantics | 流式与工具闭环 |
| gateway/service/control-plane | `ourclaw/src/runtime/*` `src/interfaces/http_adapter.zig` | service/runtime 思路 | gateway/server/config/operator surface | 控制面完整化 |
| diagnostics/events/metrics | `ourclaw/src/commands/*` + `framework` observer/event_bus | observability/bus | control UI / diagnostics / logs | 可运营运行时 |
| manager contract | `ourclaw/docs/contracts/*` + `ourclaw-manager/src/runtime_client/*` | 管理器只作边界参考 | control UI/runtime contract | 稳定消费契约 |

## 6. 目标态结构

### 6.1 Runtime Core

`request -> dispatcher -> domain runtime -> event/task/stream -> envelope/projection`

### 6.2 Control Plane

统一承载：

- gateway status / runtime health
- service & daemon lifecycle
- config governance & migration
- diagnostics / doctor / metrics / logs / observer / tasks

### 6.3 Extension / Surface Growth

后续增长点不再是新建平行骨架，而是在现有主线继续深化：

- channels / routing
- provider capability manifest
- richer memory/session ledger
- control-plane auth / pairing / policy

## 7. 执行与测试设计

所有任务都按以下节奏：

1. failing test / reproduction
2. implementation
3. passing test
4. regression test
5. docs status update

## 8. 文档治理设计

- active spec 只保留一套
- baseline spec 只承担历史完成记录
- architecture 解释模块，不写 live tasks
- planning 只做恢复与历史说明

## 9. 一句结论

这份设计的重点不是再搭骨架，而是把已有主线稳定成一个：**可长期执行、参考映射清晰、文档单一事实源明确** 的持续推进系统。
