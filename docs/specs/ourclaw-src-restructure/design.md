# ourclaw-src-restructure — Design

## 1. 设计目标

本设计服务于以下目标：

1. 在不破坏现有主线的前提下重组 `ourclaw/src`
2. 让 `runtime`、`domain`、`providers`、`tools`、`channels`、`commands`、`interfaces` 的职责更清晰
3. 为后续按模块持续深化 agent runtime 与 control-plane 提供稳定源码落点

本设计强调：

- 外部导出稳定
- 内部职责收敛
- 核心执行核突出
- 扩展域后置
- 任务可拆分实施

## 2. 总体分层

建议将 `ourclaw/src` 固化为以下层次：

- `runtime/`：业务宿主与控制面编排层
- `domain/core/`：agent 核心执行层
- `domain/extensions/`：扩展子域
- `providers/`：provider contract / registry / adapter / status
- `tools/`：tool contract / registry / handlers
- `channels/`：channel contract / registry / snapshots / ingress runtime
- `commands/`：控制面命令入口
- `interfaces/`：CLI / bridge / HTTP / stream projection 适配层
- `config/`、`security/`、`compat/`：业务基础支撑层

## 3. 目标目录树

```text
ourclaw/src/
  root.zig

  runtime/
    root.zig
    app_context.zig
    bootstrap/
      core_bootstrap.zig
      domain_bootstrap.zig
      control_plane_bootstrap.zig
    runtime_host.zig
    gateway_host.zig
    service_manager.zig
    daemon.zig
    heartbeat.zig
    cron.zig
    stream_registry.zig
    channel_ingress.zig
    config_runtime_hooks.zig
    pairing_registry.zig
    capability_manifest.zig

  domain/
    root.zig
    core/
      agent_runtime.zig
      prompt_assembly.zig
      session_state.zig
      stream_output.zig
      tool_orchestrator.zig
      memory_runtime.zig
      services.zig
    extensions/
      skills.zig
      skillforge.zig
      mcp_runtime.zig
      tunnel_runtime.zig
      hardware.zig
      peripherals.zig
      voice_runtime.zig

  providers/
    root.zig
    contracts.zig
    registry.zig
    openai_compatible.zig
    status.zig

  tools/
    root.zig
    contracts.zig
    registry.zig
    file_read.zig
    shell.zig
    http_request.zig

  channels/
    root.zig
    contracts.zig
    registry.zig
    snapshots.zig
    ingress_runtime.zig

  commands/
    root.zig
    agent/
    session/
    provider/
    channel/
    gateway/
    service/
    memory/
    events/

  interfaces/
    root.zig
    cli_adapter.zig
    bridge_adapter.zig
    http_adapter.zig
    stream_projection.zig

  config/
  security/
  compat/
```

## 4. 模块职责

### 4.1 runtime

`runtime/` 负责业务宿主层与控制面编排，不直接承载具体 agent 推理语义。

职责包括：

- `AppContext` 作为总依赖容器
- `gateway` / `runtime_host` / `service_manager` / `daemon` 生命周期接线
- `heartbeat` / `cron` / `stream_registry` 等运行时设施
- config runtime hooks
- 业务子系统装配

其中 `runtime/app_context.zig` 应收缩为：

- `AppContext` 类型定义
- `init/deinit` 总调度
- bootstrap 子模块调用入口

具体装配逻辑应拆入：

- `runtime/bootstrap/core_bootstrap.zig`
- `runtime/bootstrap/domain_bootstrap.zig`
- `runtime/bootstrap/control_plane_bootstrap.zig`

### 4.2 domain/core

这是 `ourclaw` 的核心执行层，也是最接近 `nullclaw-core` 的部分。

包括：

- `agent_runtime.zig`
- `prompt_assembly.zig`
- `session_state.zig`
- `stream_output.zig`
- `tool_orchestrator.zig`
- `memory_runtime.zig`
- `services.zig`

职责边界：

- `AgentRuntime`：驱动多轮 provider / tool loop
- `PromptAssembly`：组装 prompt / messages / tool surface
- `SessionStore`：维护事实账本、快照、回放
- `StreamOutput`：统一事件输出、session/event_bus/observer/projector 接线
- `ToolOrchestrator`：单次工具调用与审计接线
- `MemoryRuntime`：recall / append / compact / snapshot 等 memory 生命周期行为

### 4.3 domain/extensions

扩展域包括：

- `skills`
- `skillforge`
- `mcp_runtime`
- `tunnel_runtime`
- `hardware`
- `peripherals`
- `voice_runtime`

这些模块继续保留，但从源码结构语义上应后置，不再与核心执行核处于同一层级中心。

### 4.4 providers

provider 模块统一采用：

- `contracts.zig`：provider request / response / stream chunk / role / model info 等类型
- `registry.zig`：`ProviderRegistry`
- `status.zig`：health / capability / model surface
- `openai_compatible.zig`：具体 adapter

规则：

- registry 管定义与查询
- adapter 管实际 provider 调用
- provider 不承担 session、tool loop 或控制面策略

### 4.5 tools

tool 模块统一采用：

- `contracts.zig`：`ToolDefinition`、`ToolRiskLevel`、`ToolExecutionContext`
- `registry.zig`：`ToolRegistry`
- handler 文件：`file_read.zig`、`shell.zig`、`http_request.zig`

规则：

- registry 管定义和执行入口
- orchestrator 管安全、审计、session/stream 回写接线
- handler 文件只做单工具逻辑

### 4.6 channels

channel 模块收敛为：

- `contracts.zig`
- `registry.zig`
- `snapshots.zig`
- `ingress_runtime.zig`

目的：

- 先把当前 registry + snapshot + telemetry 结构拆清
- 为后续 channel lifecycle/runtime host 继续深化预留稳定落点

### 4.7 commands

`commands/` 不承担业务状态，只承担 command surface。

建议按子域归组：

- `agent/*`
- `session/*`
- `provider/*`
- `channel/*`
- `gateway/*`
- `service/*`
- `memory/*`
- `events/*`

`commands/root.zig` 继续承担统一注册入口，不改变其总入口角色。

### 4.8 interfaces

`interfaces/` 继续保持薄适配层：

- `cli_adapter.zig`
- `bridge_adapter.zig`
- `http_adapter.zig`
- `stream_projection.zig`

要求：

- 只负责协议适配与流投影
- 不直接编排业务逻辑
- 不绕过统一执行主干

## 5. 依赖规则

必须遵守以下方向：

- `interfaces -> commands/runtime`
- `commands -> runtime/domain/providers/tools/channels`
- `runtime -> domain/providers/tools/channels/config/security`
- `domain/core -> providers/tools`
- `domain/extensions -> runtime/domain/core`（仅在必要时）
- `providers/tools/channels` 不反向依赖 `interfaces`

禁止：

- `interfaces -> domain/core` 直接调用
- `providers/tools/channels -> interfaces`
- 将 claw 语义下沉到 `framework`

## 6. 迁移策略

采用四步迁移：

### 6.1 第一步：先拆 `providers/tools/channels`

原因：

- root 文件职责最重
- 拆分收益明确
- 对核心执行链路侵入相对最小

### 6.2 第二步：拆 `domain/core` 与 `domain/extensions`

原因：

- 先让核心执行核边界在源码层显式化
- 降低后续 agent runtime 深化时的路径噪音

### 6.3 第三步：拆 `runtime/app_context.zig`

原因：

- 在子系统边界已经清晰后再回头收缩装配中心，风险更低

### 6.4 第四步：对子域化 `commands/`

原因：

- commands 只是入口面
- 应在底层模块边界稳定后再做按子域重组

整个迁移过程中：

- 顶层 root 导出尽量保持兼容
- 外部 import 尽量不立即变化
- 优先降低单文件职责密度，而不是追求一次性目录名完美

## 7. 验证策略

每一步都应具备：

1. 聚合导出仍可访问
2. 原有命令入口不破
3. provider/tool/channel 主链路导入不反向污染
4. 没有把业务语义误下沉到 `framework`

## 8. 一句结论

本设计的重点不是再搭骨架，而是把当前 `ourclaw/src` 收敛成：**对外兼容、对内清晰、核心执行核突出、可按模块持续演进** 的源码结构。
