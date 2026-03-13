# ourclaw Provider / Channel / Tool 详细设计

## 1. 目标与范围

本文档定义 `ourclaw` 业务域里 provider、channel、tool 三大 registry 与 runtime 能力的完整设计，目标是在保留 `framework` 共享运行时的前提下，建立接近 `nullclaw` 的业务扩展面。

> 当前最小实现已落在 `ourclaw/src/providers/root.zig`、`ourclaw/src/channels/root.zig`、`ourclaw/src/tools/root.zig`，但目前还只是 registry stub，不等于完整业务版。

## 2. 总体设计原则

1. registry 管元数据，runtime 管实际行为
2. provider/channel/tool 统一接到 `AppContext`
3. 安全规则不写死在具体实现中，而通过 security policy 统一约束
4. 入口层和命令层只能通过 registry/runtime 接口访问业务能力

## 3. Provider 设计

### 3.1 ProviderDefinition

每个 provider 至少应定义：

- `id`
- `label`
- `required_authority`
- `supports_streaming`
- `supports_native_tools`
- `supports_images`
- `supports_audio`
- `health_check`

### 3.2 ProviderRuntime

完整版建议把 provider 拆成 definition + runtime：

- definition：静态元数据
- runtime：真实请求执行

建议 provider runtime 接口：

- `chat_once`
- `chat_stream`
- `list_models`
- `health`

### 3.3 ProviderRegistry

职责：

- 注册 provider
- 根据 id 查找 provider
- 提供给 agent runtime、diagnostics、config 校验使用

当前状态：只有最小 registry，未接真实 provider 行为。

## 4. Channel 设计

### 4.1 ChannelDefinition

建议字段：

- `id`
- `transport`
- `description`
- `listener_mode`
- `required_authority`

### 4.2 ChannelRuntime

完整版 channel runtime 建议支持：

- `start`
- `stop`
- `listen`
- `send`
- `health`
- `publish_stream`

### 4.3 ChannelRegistry

职责：

- 注册 channel 元数据
- 创建 channel runtime
- 提供给 gateway/daemon/diagnostics 使用

当前状态：只有元数据 registry，未接 channel lifecycle。

## 5. Tool 设计

### 5.1 ToolDefinition

建议字段：

- `id`
- `description`
- `required_authority`
- `parameters_schema_json`
- `risk_level`
- `handler`

### 5.2 ToolRuntime 与 ToolOrchestrator

完整版 tool 执行流程：

1. 通过 registry 找到 tool
2. 通过 security policy 判断是否允许执行
3. 校验参数
4. 执行 tool
5. 记录 observer/event/log
6. 将结果投递给 stream/session

### 5.3 ToolRegistry

职责：

- 注册 tool 定义
- 查找 tool
- 调用 tool
- 暴露给 agent runtime 与 diagnostics

当前状态：已有最小 `echo` / `clock`，但距离 `nullclaw` 的行动面还差很远。

## 6. 与 Security / Config / Runtime 的关系

provider/channel/tool 不应孤立存在，它们必须共享：

- config field registry
- security policy
- logger / observer / event bus
- task runner

完整业务版中：

- provider 配置来自 config runtime
- channel lifecycle 挂在 runtime host
- tool 执行由 tool orchestrator 统一调度

## 7. 分阶段实施建议

### 第一阶段：registry 完整化

- 补齐元数据字段
- 支持 builtin 注册
- 接入 diagnostics / health query

### 第二阶段：最小真实实现

- 先做一个 OpenAI-compatible provider
- 先做一个 CLI channel
- 先做 file/shell/http 三个最小真实 tool

### 第三阶段：接入完整 runtime

- provider 接到 agent runtime
- channel 接到 gateway/daemon
- tool 接到 streaming/session loop

## 8. 当前差距

- provider：无真实模型调用
- channel：无真实 runtime host
- tool：无真实高价值工具集
- diagnostics/health：未基于 registry 全面接线

## 9. 验收标准

完整版至少应满足：

1. 至少一个真实 provider 可用
2. 至少一个真实 channel 可收发
3. 至少三个真实 tool 可安全执行
4. registry 可被命令域、runtime、diagnostics、config 共用
