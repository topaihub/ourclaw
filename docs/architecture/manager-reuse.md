# ourclaw 与 ourclaw-manager 的复用分层设计

> 使用说明（2026-03-16）：本文档是 manager 方向的 supporting doc，不再作为默认任务入口。
>
> 当前应优先参考：
>
> - `ourclaw/docs/specs/reference-aligned-ourclaw/design.md`
> - `ourclaw/docs/contracts/manager-runtime-surface.md`

## 1. 背景

当前的 `ourclaw-manager` 已经不是纯骨架，已具备一版 `runtime_client + typed contract + view model typed consumption` 基线。它会继续承担与 `nullclaw-manager` 类似的职责：

- 帮助用户配置 `ourclaw`
- 展示诊断、日志、状态和风险提示
- 管理 `ourclaw` 的服务、网关和运行状态
- 作为桌面宿主或本地控制台编排 `ourclaw`

因此，`ourclaw` 在设计时不能只考虑 CLI/runtime 自己可用，还要提前考虑未来如何被 manager 稳定复用。

这里的关键不是“让 manager 直接 import 整个 `ourclaw/src`”，而是把 `ourclaw/src` 切分成：

- 可直接代码复用的稳定层
- 只能通过命令/IPC/事件调用的运行时层

## 2. 核心结论

推荐采用 **双层复用策略**：

### 2.1 代码级复用

在当前主线里，`ourclaw-manager` 可以直接复用或稳定消费这些层：

- `framework` 中的共享 contracts / runtime 基座
- `ourclaw/docs/contracts/*` 中定义的稳定契约
- `ourclaw/src/config` 中的元数据与纯逻辑部分
- `ourclaw-manager/src/runtime_client/*` 形成的 typed consumption facade

这些模块应尽量做到：

- 无 UI 依赖
- 无进程模型依赖
- 无必须运行中的 runtime 状态依赖
- 无副作用或副作用可控

### 2.2 能力级复用

对于强运行时耦合的能力，不建议 manager 直接 import 内部实现，而应该通过稳定命令边界或 IPC/bridge 调用：

- 服务启停
- 实时状态查询
- 长任务诊断
- 运行中日志流
- provider probe
- 网关运行时状态

也就是说：

- **静态能力直接复用代码**
- **动态能力通过命令和事件复用能力**

这是未来 `ourclaw-manager` 最稳的架构方向。

## 3. 为什么不能让 manager 直接依赖全部 `ourclaw/src`

如果 future manager 随意 import `ourclaw/src` 内的任意模块，会产生几个问题：

- manager 与 runtime 内部实现强耦合
- 运行时重构会牵连 manager 大范围改动
- 很多 runtime-only 模块会被错误带入 manager 进程
- service/gateway/provider 等副作用逻辑容易越界
- 日志、状态、配置可能出现两套逻辑

所以需要明确“哪些是公共层，哪些是运行时层，哪些是 manager 边界层”。

## 4. 推荐分层

基于当前已落地主线，建议把长期复用边界理解成以下几层：

```text
L0  core/            横切基础能力，可直接复用
L1  contracts/       结构化契约，可直接复用
L2  config/          配置元数据与纯逻辑，可直接复用
L3  manager_sdk/     面向 manager 的稳定 facade，可直接复用
L4  app/             命令注册与分发，主要由 runtime 使用
L5  runtime/         生命周期、任务、事件总线，偏 runtime
L6  domain/          providers/channels/tools/memory/gateway/service
L7  interfaces/      cli/bridge/http/service 入口适配
```

分层原则：

- 越往上越稳定、越可复用
- 越往下越 runtime-specific、越不应被 manager 直接依赖

## 5. 哪些层应该被 ourclaw-manager 直接复用

## 5.1 可以直接代码复用的层

### `core`

未来 manager 应直接复用：

- `core/logging`
- `core/trace`
- `core/validation`
- `core/error`
- `core/envelope`

原因：

- manager 自己也需要日志
- manager 自己也需要校验
- manager 自己也需要统一错误模型
- manager 和 runtime 必须共享同一套结构化基础能力

### `contracts`

未来 manager 应直接复用：

- `command-envelope`
- `error-model`
- `log-record`
- `runtime-event`
- `task-state`
- `config-field-registry`

原因：

- manager 和 runtime 之间必须共用 DTO/协议模型
- 不要在 manager 里再定义第二套日志结构、事件结构、错误结构

### `config` 的纯逻辑部分

未来 manager 应直接复用：

- `field_registry`
- `defaults`
- `paths`
- `migration` 中纯数据迁移规则
- `validators` 中纯规则部分

原因：

- manager 的配置表单元数据不应重复维护
- manager 的前置校验应与 runtime 一致
- manager 的风险提示应与 runtime 一致

## 5.2 不建议直接复用实现、而应走命令边界的层

### `runtime`

`runtime` 负责：

- 生命周期
- 任务执行
- 事件总线
- 进程内状态

这层对 manager 来说太靠近运行时内部，不应成为任意可见 API。

### `domain`

例如：

- service
- gateway
- provider probe
- channels runtime

这些能力很多都有副作用，不适合让 manager 直接 import 内部逻辑后自己调用。

### `interfaces`

CLI/HTTP/bridge 是边界适配层，本身不是复用目标。manager 应复用其背后的命令契约，而不是直接复用入口代码。

## 6. 推荐新增一层：`manager_sdk`

为了避免 future manager 直接引用过多内部模块，建议在 `ourclaw/src` 内新增一层：

```text
src/manager_sdk/
  root.zig
  logging.zig
  paths.zig
  config_schema.zig
  config_service.zig
  logs_service.zig
  diagnostics_service.zig
  service_service.zig
  runtime_client.zig
  bridge_contract.zig
```

这层的目标不是重新实现业务，而是把 manager 真正需要的能力整理成稳定 facade。

## 6.1 manager_sdk 的职责

- 暴露稳定的 manager-friendly API
- 屏蔽 `ourclaw` 内部复杂实现细节
- 明确哪些能力是纯库调用，哪些能力需要 runtime client
- 让 future manager 只依赖 `manager_sdk`，而不是散乱 import `core/config/runtime/domain`

## 6.2 manager_sdk 的设计原则

- facade 只暴露 manager 需要的最小能力
- facade 不吞掉错误模型
- facade 不定义第二套 DTO
- facade 内部可以调用 `core`、`contracts`、`config`
- facade 对 runtime 状态型能力统一走 client/command 边界

## 7. 日志复用设计

你特别提到 manager 也需要日志，这块建议这样设计。

## 7.1 一套日志实现，两类日志实例

`ourclaw` 和 future `ourclaw-manager` 应共享同一套日志基础设施：

- `LogRecord`
- `Logger`
- `ConsoleSink`
- `JsonlFileSink`
- `MemorySink`
- `MultiSink`
- `redact`

但要有两类日志实例：

- runtime logger
- manager host logger

## 7.2 日志目录分离

建议目录这样拆：

```text
~/.ourclaw/logs/runtime/
~/.ourclaw/logs/manager/
```

这样有几个好处：

- 用户能区分到底是 runtime 出错还是 manager 出错
- manager 不会把自己的日志混入 runtime 主日志
- UI 可以分别展示，也可以聚合展示

## 7.3 日志结构统一

虽然目录分离，但日志结构必须统一，都使用 `LogRecord` 契约。

这样 manager UI 的日志查看器才能：

- 同时读 runtime 和 manager 两种日志
- 用同一套筛选逻辑按 `level`、`subsystem`、`trace_id` 展示

## 7.4 子系统命名建议

建议统一命名：

- runtime 侧：`runtime/...`、`config/...`、`service/...`
- manager 侧：`manager/host`、`manager/webview`、`manager/config`、`manager/runtime-client`

这样后续看日志时一眼能知道来源。

## 8. 校验复用设计

manager 最容易重复造轮子的地方就是表单校验和配置校验，所以这一层必须严格共享。

## 8.1 统一字段注册表

`config/field_registry.zig` 应成为唯一真相源。

未来 manager 的配置页不应该自己维护第二套字段定义，而应从这里获取：

- 字段路径
- 类型
- 是否敏感
- 是否需要重启
- 风险等级
- 描述
- 可选规则

## 8.2 统一规则执行器

manager 在用户点击“保存”前，应使用与 runtime 相同的 validator 做一次前置校验。

然后 runtime 在真正写入配置前，再使用同一套规则做最终校验。

这意味着：

- manager 做的是“前端/宿主预检查”
- runtime 做的是“最终权威检查”

两次检查共用同一套规则，不重复造轮子。

## 8.3 风险确认共享

比如：

- `gateway.host = 0.0.0.0`
- `gateway.require_pairing = false`
- `logging.redact.mode = off`

manager UI 只需要根据共享的风险元数据弹确认框，runtime 则根据同一元数据决定是否要求 `confirm_risk`。

## 9. 配置复用设计

未来 manager 的核心工作之一是配置 ourclaw，因此配置层需要特别规划。

## 9.1 manager 不应自己直接操作原始 JSON

建议未来 manager 不要在 UI 或 host 层直接拼装和写回 JSON，而应该复用：

- `config` 层的路径解析
- 字段注册表
- 校验器
- 写回服务
- 差异判断
- `requires_restart` 判断

## 9.2 建议暴露 manager 友好服务

例如通过 `manager_sdk/config_service.zig` 暴露：

- `load_config_snapshot()`
- `list_config_fields()`
- `validate_config_change(path, value)`
- `apply_config_change(path, value, confirm_risk)`

这样 future manager 的 host 可以直接调用，而 UI 只消费结构化结果。

## 9.3 表单元数据生成

manager UI 后续会很需要字段元数据，所以建议 `manager_sdk` 提供：

- `config.schema` 命令
- 或 `list_config_fields()` facade

避免在 Svelte/TypeScript 里再写一遍字段定义。

## 10. 运行时状态与服务控制设计

这部分不建议 manager 直接复用内部实现，而建议走 `runtime client` 模式。

## 10.1 为什么要走 runtime client

因为这些能力依赖运行中状态：

- 服务是否运行
- 当前任务队列
- 正在进行的诊断
- 实时日志流
- 实时事件

这些不适合由 manager 自己 import 内部状态对象来获取。

## 10.2 推荐模式：manager 通过命令/IPC 与 runtime 交互

建议 `ourclaw-manager` 的 host 通过以下方式之一访问 runtime：

- 调用 `ourclaw.exe` 的结构化命令
- 调用本地 JSON bridge
- 调用本地 HTTP/IPC 控制端点

推荐顺序是：

1. 本地命令/JSON bridge
2. 再考虑本地 HTTP/daemon API

## 10.3 适合走 runtime client 的能力

- `service.status`
- `service.start`
- `service.stop`
- `service.restart`
- `diagnostics.summary`
- `diagnostics.doctor`
- `logs.recent`
- `logs.export`
- `events.poll`

## 11. 推荐的 future ourclaw-manager 架构

建议 future `ourclaw-manager` 分成三层：

```text
ourclaw-manager/
  ui/                    Svelte/TypeScript
  app/
    src/
      host/              WebView/Tauri host
      bridge/            UI 与 host 的桥接
      runtime_client/    调用 ourclaw runtime 的客户端
      services/          manager 业务编排
      view_models/       UI 友好模型
```

其中：

- `runtime_client/` 通过命令/IPC 与 `ourclaw` 交互
- `services/` 直接复用 `ourclaw` 的 `manager_sdk`
- `host/` 自己的日志也使用 `ourclaw/core/logging`

## 12. 推荐的 ourclaw 源码边界调整

为了让 future manager 更容易复用，建议在 `ourclaw/src` 后续继续这样演进：

```text
src/
  core/
  contracts/
  config/
  manager_sdk/
  app/
  runtime/
  commands/
  domain/
  interfaces/
```

说明：

- `core/contracts/config/manager_sdk` 是 future manager 主要复用面
- `runtime/commands/domain/interfaces` 主要是 runtime 自己用

## 13. 推荐的稳定复用边界

未来请尽量把 manager 的依赖收敛到：

- `ourclaw/src/core/*`
- `ourclaw/src/contracts/*`
- `ourclaw/src/config/*` 中纯逻辑文件
- `ourclaw/src/manager_sdk/*`

不要让 manager 直接依赖：

- `ourclaw/src/runtime/*` 的内部状态对象
- `ourclaw/src/commands/*` 的具体 handler 实现
- `ourclaw/src/domain/*` 的副作用型内部实现

## 14. 推荐实施顺序

建议后续分 4 步推进：

### 第一步：先把 `ourclaw` 的共享层做稳

- `core`
- `contracts`
- `config`

### 第二步：增加 `manager_sdk`

先暴露：

- `paths`
- `config schema`
- `config service`
- `logging bootstrap`

### 第三步：把 runtime 控制面结构化

完成：

- `service.*`
- `diagnostics.*`
- `logs.*`
- `events.poll`

### 第四步：再建设 future `ourclaw-manager`

此时 manager 就不需要重复实现：

- 日志基础设施
- 校验规则
- 配置字段元数据
- 错误与响应模型

## 15. 最终建议

一句话总结这套复用策略：

- `ourclaw-manager` 复用 `ourclaw` 的 **共享层代码**
- `ourclaw-manager` 调用 `ourclaw` 的 **运行时能力边界**
- 不让 manager 直接侵入 runtime 内部实现

这会带来三个直接收益：

- 日志、校验、配置规则不会出现两套
- runtime 可以持续演进而不把 manager 一起拖乱
- future manager 的功能会更像“编排与配置层”，而不是“重写一套 runtime”
