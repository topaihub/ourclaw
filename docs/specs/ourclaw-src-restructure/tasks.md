# ourclaw-src-restructure — Tasks

> 说明：
>
> - 本任务表聚焦 `ourclaw/src` 结构收敛
> - 目标是让后续实现可以按原子任务交给大模型推进
> - 任务顺序遵循“先降单文件职责，再收敛核心边界，最后重组入口面”

## 1. Wave A — 拆分高耦合 root 文件

- [x] **A1. 为 `providers/root.zig` 建立 `contracts.zig` 落点**
  - 主线落点：`ourclaw/src/providers/contracts.zig`
  - 目标：先建立 provider contract 的独立文件落点，不在这一步处理 registry 与 status
  - 完成定义：`providers/contracts.zig` 已创建，`root.zig` 中 contract 相关结构已有明确迁移目标

- [x] **A2. 将 provider contracts 从 `providers/root.zig` 移入 `providers/contracts.zig`**
  - 主线落点：`ourclaw/src/providers/contracts.zig`
  - 目标：只搬运 contract 相关类型与导出，不顺手重组其他职责
  - 完成定义：provider contract 不再直接定义在 `providers/root.zig`

- [x] **A3. 为 `providers/root.zig` 建立 `status.zig` 落点并迁移状态相关类型**
  - 主线落点：`ourclaw/src/providers/status.zig`
  - 目标：将 health、model、capability 一类状态与能力描述从 root 中拆出
  - 完成定义：`providers/status.zig` 承载 provider status 语义，`root.zig` 不再混放这部分类型

- [x] **A4. 为 `providers/root.zig` 建立 `registry.zig` 落点并迁移 `ProviderRegistry` 结构骨架**
  - 主线落点：`ourclaw/src/providers/registry.zig`
  - 目标：先抽出 `ProviderRegistry` 结构、字段与最基础的查找/注册壳，不在这一步迁移 provider 调用、embedding、health、observability 与 error mapping 细节
  - 完成定义：`ProviderRegistry` 已有独立文件落点，且基础 registry 壳不再定义在 `providers/root.zig`

- [x] **A5. 迁移 `ProviderRegistry` 的基础注册与查询逻辑**
  - 主线落点：`ourclaw/src/providers/registry.zig`
  - 目标：迁移 `init/deinit/register/find/registerBuiltins` 一类基础逻辑，不在这一步处理调用与状态投影
  - 完成定义：provider registry 的基础注册与查询逻辑已脱离 `root.zig`

- [x] **A6. 迁移 `ProviderRegistry` 的状态与能力查询逻辑**
  - 主线落点：`ourclaw/src/providers/registry.zig`、`ourclaw/src/providers/status.zig`
  - 目标：迁移 health/models/supports* 等状态与能力查询逻辑
  - 完成定义：provider 状态面与 registry 查询逻辑已不再混放于 `root.zig`

- [x] **A7. 迁移 `ProviderRegistry` 的 provider 调用与 embedding 相关逻辑**
  - 主线落点：`ourclaw/src/providers/registry.zig`
  - 目标：迁移 chat/stream/embed 等 provider runtime 相关逻辑与其直接依赖
  - 完成定义：provider runtime 相关逻辑已移动到 registry 落点或其直接依赖文件

- [x] **A8. 更新 `providers/*` 导入并回收 `providers/root.zig` 为聚合根**
  - 主线落点：`ourclaw/src/providers/root.zig`
  - 目标：改为由 `root.zig` 统一聚合 `contracts.zig`、`status.zig`、`registry.zig`
  - 完成定义：`providers/root.zig` 主要承担聚合导出职责，外部访问方式尽量不变

- [x] **A9. 对 `providers` 拆分执行定向验证**
  - 主线落点：`ourclaw/src/providers/*`
  - 目标：只验证 providers 相关 import、导出与编译面是否仍稳定
  - 完成定义：providers 拆分后没有新增断裂导入，聚合根仍可访问既有能力

- [x] **A10. 为 `tools/root.zig` 建立 `contracts.zig` 落点**
  - 主线落点：`ourclaw/src/tools/contracts.zig`
  - 目标：先把 tool contract 的独立文件落位，保持具体 handler 文件不动
  - 完成定义：`tools/contracts.zig` 已创建，contract 迁移边界清晰

- [x] **A11. 将 tool contracts 从 `tools/root.zig` 移入 `tools/contracts.zig`**
  - 主线落点：`ourclaw/src/tools/contracts.zig`
  - 目标：只搬运 tool contract 相关类型与导出，不改 handler 组织方式
  - 完成定义：tool contract 不再直接堆在 `tools/root.zig`

- [x] **A12. 为 `tools/root.zig` 建立 `registry.zig` 落点并迁移 registry**
  - 主线落点：`ourclaw/src/tools/registry.zig`
  - 目标：抽离 tool registry 与其直接依赖逻辑，继续保持 handler 文件不动
  - 完成定义：tool registry 已独立成文件，handler、contract、registry 三类职责不再混装

- [x] **A13. 更新 `tools/*` 导入并回收 `tools/root.zig` 为聚合根**
  - 主线落点：`ourclaw/src/tools/root.zig`
  - 目标：让 `root.zig` 只负责统一导出 contracts、registry 与既有 handler 面
  - 完成定义：`tools/root.zig` 不再承担 contract 与 registry 的主体实现

- [x] **A14. 对 `tools` 拆分执行定向验证**
  - 主线落点：`ourclaw/src/tools/*`
  - 目标：确认 tools 拆分后导出稳定，且 handler 引用没有被破坏
  - 完成定义：tools 相关 import 路径与聚合访问面保持可用

- [x] **A15. 为 `channels/root.zig` 建立 `contracts.zig` 落点**
  - 主线落点：`ourclaw/src/channels/contracts.zig`
  - 目标：先单独落位 channel contracts，不在这一步同时处理 registry、snapshots、ingress runtime
  - 完成定义：`channels/contracts.zig` 已创建，contract 迁移边界清晰

- [x] **A16. 将 channel contracts 从 `channels/root.zig` 移入 `channels/contracts.zig`**
  - 主线落点：`ourclaw/src/channels/contracts.zig`
  - 目标：只搬运 channel contract 相关类型与导出
  - 完成定义：channel contracts 不再直接定义在 `channels/root.zig`

- [x] **A17. 为 `channels/root.zig` 建立 `snapshots.zig` 落点并迁移 snapshot 语义**
  - 主线落点：`ourclaw/src/channels/snapshots.zig`
  - 目标：先把 telemetry、snapshot 相关结构从 root 中拆出
  - 完成定义：snapshot 相关语义已独立到 `channels/snapshots.zig`

- [x] **A18. 为 `channels/root.zig` 建立 `ingress_runtime.zig` 落点并迁移 ingress runtime**
  - 主线落点：`ourclaw/src/channels/ingress_runtime.zig`
  - 目标：将 ingress runtime 独立成单文件职责，避免继续与 contracts、registry、snapshots 混放
  - 完成定义：ingress runtime 已有清晰单独落点

- [x] **A19. 为 `channels/root.zig` 建立 `registry.zig` 落点并迁移 registry**
  - 主线落点：`ourclaw/src/channels/registry.zig`
  - 目标：在 contracts、snapshots 与 ingress runtime 已有独立落点后，再抽离 channel registry 与直接相关辅助逻辑
  - 完成定义：channel registry 已独立成文件，且依赖抖动可控

- [x] **A20. 更新 `channels/*` 导入并回收 `channels/root.zig` 为聚合根**
  - 主线落点：`ourclaw/src/channels/root.zig`
  - 目标：统一聚合 `contracts.zig`、`snapshots.zig`、`registry.zig`、`ingress_runtime.zig`
  - 完成定义：`channels/root.zig` 主要承担聚合导出职责，不再混装 registry 与 telemetry/snapshot 语义

- [x] **A21. 对 `channels` 拆分执行定向验证**
  - 主线落点：`ourclaw/src/channels/*`
  - 目标：只验证 channels 相关导出、导入与入口面稳定性
  - 完成定义：channels 拆分后外部访问面尽量稳定，没有新增明显断裂

## 2. Wave B — 收敛 domain 核心边界

- [x] **B1. 建立 `domain/core` 与 `domain/extensions` 分层**
  - 主线落点：`ourclaw/src/domain/*`
  - 目标：将核心执行核与扩展域拆成两个清晰层次
  - 产物：
    - `domain/core/*`
    - `domain/extensions/*`
    - 更新后的 `domain/root.zig`
  - 完成定义：核心 loop 相关文件不再与扩展子域混放在同一层级中心

- [x] **B2. 拆分 `agent_runtime.zig` 的辅助结构**
  - 主线落点：`ourclaw/src/domain/core/*`
  - 目标：从主循环文件中拆出 request / budget / provider-loop 辅助逻辑
  - 参考：保持 `AgentRuntime.run()` / `runStream()` 为主入口
  - 完成定义：`agent_runtime.zig` 主要保留编排主干，而不是继续承担所有辅助结构

- [x] **B3. 拆分 `session_state.zig` 的 snapshot 与 JSON 辅助逻辑**
  - 主线落点：`ourclaw/src/domain/core/*`
  - 目标：减轻 `SessionStore` 主文件体积与责任密度
  - 完成定义：账本入口、snapshot 聚合、字段辅助逻辑结构清晰

## 3. Wave C — 收缩 runtime 装配中心

- [x] **C1. 为 `runtime/app_context.zig` 引入 bootstrap 子模块**
  - 主线落点：`ourclaw/src/runtime/bootstrap/*`
  - 目标：将现有大体量装配逻辑拆成三段：
    - core bootstrap
    - domain bootstrap
    - control-plane bootstrap
  - 产物：
    - `runtime/bootstrap/core_bootstrap.zig`
    - `runtime/bootstrap/domain_bootstrap.zig`
    - `runtime/bootstrap/control_plane_bootstrap.zig`
  - 完成定义：`AppContext` 仍为总依赖容器，但具体装配不再全部堆在一个文件中

- [x] **C2. 校准 runtime 聚合导出**
  - 主线落点：`ourclaw/src/runtime/root.zig`
  - 目标：确保 runtime 聚合根继续稳定导出新的内部结构
  - 完成定义：外部通过 `runtime/root.zig` 的访问方式尽量不变

## 4. Wave D — 按子域重组 commands

- [x] **D1. 为 commands 建立子域目录**
  - 主线落点：`ourclaw/src/commands/*`
  - 目标：建立：
    - `agent/`
    - `session/`
    - `provider/`
    - `channel/`
    - `gateway/`
    - `service/`
    - `memory/`
    - `events/`
  - 完成定义：命令文件可以按子域被独立浏览、修改和验证

- [x] **D2. 保持 `commands/root.zig` 为统一注册入口**
  - 主线落点：`ourclaw/src/commands/root.zig`
  - 目标：在目录重组后仍通过单一注册入口挂载全部内建命令
  - 完成定义：命令 method 名与注册总量不发生破坏性变化

## 5. Wave E — 校准聚合根与导入路径

- [x] **E1. 校准顶层聚合根**
  - 主线落点：
    - `ourclaw/src/root.zig`
    - `ourclaw/src/runtime/root.zig`
    - `ourclaw/src/domain/root.zig`
    - `ourclaw/src/interfaces/root.zig`
  - 目标：继续通过原聚合根向外导出重组后的内部模块
  - 完成定义：外部 import 路径尽量稳定

- [x] **E2. 验证依赖方向未被污染**
  - 主线落点：`ourclaw/src/*`
  - 目标：确认：
    - `interfaces` 不直接依赖 domain/core
    - `providers/tools/channels` 不反向依赖 `interfaces`
    - 没有把业务语义误下沉到 `framework`
  - 完成定义：结构调整后依赖方向仍符合设计约束

## 6. 执行约定

- 每次只推进一个原子任务
- 每次重组优先保证聚合根兼容
- 每次任务完成后都要重新确认：
  - 导出是否仍可访问
  - 入口是否仍稳定
  - 依赖方向是否仍正确

## 7. 一句结论

本任务表的目标不是“一次性大重构”，而是把 `ourclaw/src` 拆成：**足够清晰、足够稳定、足够可分任务推进** 的结构化主线。
