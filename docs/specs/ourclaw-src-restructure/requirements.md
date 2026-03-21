# ourclaw-src-restructure — Requirements

## 1. 背景

`ourclaw` 当前已经具备可运行的主线基线，包括：

- `framework` 共享执行主干
- `ourclaw` 的 agent runtime / session / memory / stream / provider / tool 第一版
- gateway / service / daemon / diagnostics / config 等控制面能力

当前问题不再是“是否有能力”，而是 `ourclaw/src` 的源码结构已经开始出现以下征兆：

- `runtime` 装配过重
- `root` 文件承担过多职责
- 核心执行核与扩展域边界不清
- commands 聚合面过大，不利于持续拆分与自动化实现

因此，本专题 spec 的目标不是重新设计 `ourclaw`，而是把已经落地的主线能力收敛成更清晰、更稳定、更适合继续编码的源码结构。

## 2. 当前基线

### 2.1 已有结构基线

当前 `ourclaw/src` 已形成以下一级模块：

- `runtime/`
- `domain/`
- `providers/`
- `channels/`
- `tools/`
- `commands/`
- `interfaces/`
- `config/`
- `security/`
- `compat/`

### 2.2 已有能力基线

当前代码已包含：

- `AgentRuntime` 主循环与流式执行入口
- `SessionStore`、session snapshot、recent turns、usage 聚合
- `StreamOutput`、stream registry、SSE / WS / CLI live 投影
- `ProviderRegistry` 与 OpenAI-compatible provider 第一版
- `ToolRegistry` 与最小 builtin tools
- `gateway` / `service` / `daemon` / `heartbeat` / `cron`
- `skills` / `mcp` / `tunnel` / `voice` 等扩展域第一版

### 2.3 基线约束

本专题不得把上述内容重新描述为“待从零实现”，而必须把它们视为已存在基线，并在此基础上推进结构收敛。

## 3. 总体目标

本专题必须推动 `ourclaw/src` 达成以下目标：

1. 形成更清晰的业务主干结构，便于长期维护
2. 明确 `framework` 与 `ourclaw` 的职责边界
3. 明确 `runtime`、`domain/core`、`domain/extensions`、`providers`、`tools`、`channels`、`interfaces` 的稳定边界
4. 为后续大模型按模块推进重构与深化实现提供低歧义任务输入

## 4. 范围

### 4.1 覆盖范围

- `ourclaw/src` 内部目录与文件职责重组
- `providers/tools/channels` 的内部结构收敛
- `domain` 的核心执行层与扩展层分离
- `runtime/app_context.zig` 的装配职责拆分
- `commands` 的按子域归组

### 4.2 不覆盖范围

- 不新增全新业务能力
- 不在本专题中实现新的持久化后端
- 不一次性对标 `openclaw` 全量产品化外壳
- 不把 provider / tool / channel / session / memory / gateway 等业务语义下沉到 `framework`
- 不要求本轮完成完整插件系统、完整多通道生命周期或完整分布式控制面

## 5. 关键需求

### R1. 顶层导出必须尽量稳定

本专题必须优先采用“内部重组、外部兼容”的方式推进。以下聚合根应尽量保持稳定：

- `ourclaw/src/root.zig`
- `ourclaw/src/runtime/root.zig`
- `ourclaw/src/domain/root.zig`
- `ourclaw/src/interfaces/root.zig`

### R2. runtime 装配必须降复杂度

`runtime/app_context.zig` 不能继续作为所有业务装配逻辑的唯一承载文件。

本专题完成后：

- `AppContext` 仍作为总依赖容器存在
- 具体装配逻辑必须被拆分到更小的 bootstrap 子模块
- 控制面装配与核心执行域装配必须显式分离

### R3. domain 必须区分核心执行核与扩展域

`domain/` 必须显式区分：

- `domain/core`：agent runtime 主线相关核心执行层
- `domain/extensions`：skills / mcp / tunnel / voice / hardware / peripherals 等扩展子域

本专题完成后，不应继续让扩展子域与核心执行核在同一层级语义上并列混放。

### R4. provider / tool / channel 必须从混装 root 收敛为稳定结构

以下模块必须从“单个 root 文件承担多职责”收敛为更稳定的内部结构：

- `providers/`
- `tools/`
- `channels/`

至少应达到：

- contract 类型与 registry 分离
- 状态 / snapshot / runtime 语义不再混在一个文件里
- `root.zig` 以聚合导出职责为主，而不是继续承载主要实现

### R5. AgentRuntime 必须保持 loop 驱动中心

结构重组不能削弱以下边界：

- `AgentRuntime` 负责多轮 provider / tool loop 驱动
- `ToolOrchestrator` 只负责单次工具调用
- `SessionStore` 负责事实账本与快照，不负责策略决策
- `StreamOutput` 负责统一输出与投影接线

### R6. interfaces 必须保持薄适配层

`interfaces` 只负责：

- CLI / bridge / HTTP 请求适配
- stream 投影
- 外层协议转换

不得把业务编排、策略逻辑或 session 决策继续放入 `interfaces/`。

### R7. commands 必须可按子域拆分

`commands/root.zig` 可以继续作为统一注册入口，但命令文件布局必须支持按子域归组，例如：

- `agent/*`
- `session/*`
- `gateway/*`
- `service/*`
- `memory/*`
- `events/*`

本专题完成后，`commands` 应更适合作为后续大模型分任务实施的入口面。

## 6. 非目标

1. 不重写现有运行时主循环
2. 不在本专题中扩写更多扩展子域能力
3. 不把本专题变成“新架构从零设计”工作
4. 不要求 manager 在本轮同步大改

## 7. 验收标准

### 7.1 文档验收

必须存在以下专题文档：

- `requirements.md`
- `design.md`
- `tasks.md`

### 7.2 结构验收

必须能明确给出：

- `ourclaw/src` 目标目录树
- 每个核心文件的去向与处理策略
- 哪些文件保留、哪些拆分、哪些新建

### 7.3 执行验收

后续任务必须能够被拆解成原子工作项，并满足：

- 每项任务只改一小块结构
- 每项任务有明确主线落点
- 每项任务适合单独交给大模型执行

## 8. 一句结论

本专题要回答的不是“如何再造一个新 ourclaw”，而是：**如何基于当前已实现基线，把 `ourclaw/src` 收敛成一套边界清晰、可持续推进、适合大模型逐项完成的源码结构。**
