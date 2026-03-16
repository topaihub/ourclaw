# reference-aligned-ourclaw — Requirements

## 1. 背景

`ourclaw` 已经完成 phase-1 主线骨架与一轮产品化收口，但这不等于“已经完成 ourclaw 开发”。

当前更真实的目标是：

- 以 `framework/` 为共享 Zig 基础层
- 以 `ourclaw/` 为 assistant runtime / control-plane / extension domains 主线
- 以 `ourclaw-manager/` 为管理与配置消费层
- 以 `nullclaw` 对齐 Zig 运行时能力天花板
- 以 `openclaw` 对齐成熟产品的控制面、配置治理与运营语义

## 2. 当前基线

### 2.1 已落地共享基线

`framework/` 已具备：

- `AppContext`
- `CommandDispatcher`
- `TaskRunner`
- `EventBus`
- `Envelope / AppError`
- validation rules / reports
- config store / pipeline / parser / loader
- observer / metrics / logging sinks

### 2.2 已落地业务基线

`ourclaw/` 已具备：

- agent runtime / memory runtime / session state
- provider / tool / channel registry
- stream output / stream registry / stream projection
- gateway / runtime host / service / daemon / cron / heartbeat
- diagnostics / events / observer / metrics / logs / task 查询面
- skills / tunnel / mcp / hardware / peripheral / voice 第一版子域
- CLI / HTTP / bridge / SSE / WebSocket / CLI live 一版入口

### 2.3 基线约束

本规格不能再把上述内容当作“待从零开始实现”的工作，而必须把它们视为已落地基线，并在此基础上继续推进完整性与参考对齐。

## 3. 总体目标

新的 active spec 要推动 `ourclaw` 达成以下目标：

1. 成为一个长期运行的 Zig assistant runtime system，而非仅命令集合
2. 拥有清晰的 control-plane、session、memory、stream、provider、tool 与 service 语义
3. 拥有足够稳定的 manager-facing contract，支撑 `ourclaw-manager`
4. 拥有单一事实源的文档体系，避免 future agents 被历史文档误导

## 4. 范围

### 4.1 覆盖范围

- `framework/` 的共享基础继续演进
- `ourclaw/` 的 core runtime / control-plane / extension domains
- `ourclaw-manager/` 的 runtime contract 消费层
- `nullclaw` / `openclaw` 到主线落点的显式映射
- 后续长期任务清单

### 4.2 不覆盖范围

- 不直接修改 `nullclaw/` / `openclaw/` / `nullclaw-manager/`
- 不在本规格中展开 GUI 视觉设计
- 不要求一次性实现全部第三方渠道与节点能力

## 5. 关键需求

### R1. 三层边界必须保持稳定

- `framework/`：无业务语义、可跨应用复用
- `ourclaw/`：runtime / gateway / provider / tool / stream / service / extension domains
- `ourclaw-manager/`：runtime client / 管理 / 配置消费面

### R2. 参考映射必须显式化

每个关键能力域都必须写出：

- 当前主线落点
- `nullclaw` 参考锚点
- `openclaw` 参考锚点或公开文档锚点
- 参考目的

### R3. 文档必须明确区分基线与未来工作

active spec 必须：

- 以当前代码为 baseline
- 不重复列出已完成 phase-1 任务
- 明确未来工作与已完成基线的边界

### R4. tasks 必须可执行

每项任务至少带：

- 目标
- 依赖
- 主线落点
- 参考锚点
- failing / passing / regression test
- 完成定义

### R5. docs 体系必须可导航

必须存在清晰的：

- active spec
- baseline spec
- supporting docs
- historical planning docs

## 6. 能力域要求

### 6.1 Core Runtime

- agent runtime
- session state
- memory runtime
- provider runtime
- tool orchestration
- stream output / projection / registry

### 6.2 Control Plane

- gateway host
- runtime host
- service / daemon
- config schema / hooks / migration / import
- diagnostics / doctor / status / health

### 6.3 Manager Contract

- status snapshots
- session snapshots
- diagnostics / logs / events / task / observer snapshots
- stable/provisional contract discipline

### 6.4 Reference-Aligned Extension Domains

- channel routing / channel manager
- provider capability manifest
- capability manifest / runtime adapter shared contracts
- future node/device/control-plane growth points

## 7. 非目标

1. 不逐文件移植 `openclaw`
2. 不在本规格里完成所有 UI 产品设计
3. 不把 `framework` 变成业务语义仓库

## 8. 验收标准

1. 存在新的 active `requirements.md` / `design.md` / `tasks.md`
2. 文档能明确区分 baseline 与 future work
3. 任务清单完整覆盖后续主线，而不是零散 backlog
4. 文档入口清晰，不再需要依赖旧 planning 才能判断主线方向

## 9. 一句结论

新的规格要回答的不是“怎么搭第一版骨架”，而是：**如何基于当前已实现基线，把 `ourclaw` 推向参考对齐、控制面完整、长期可运营的 Zig assistant runtime。**
