# ourclaw

`ourclaw` 是一个基于 `framework` 的 Zig 业务应用骨架。

当前方向已经调整为三层结构：

- `framework/`：可复用的 Zig 通用框架
- `ourclaw/`：AI/runtime 业务应用
- `ourclaw-manager/`：未来的配置与管理应用

`ourclaw` 本身主要承载 claw 业务能力，而不是继续把所有通用基础设施都堆在应用内部。

## 文档入口

- `ourclaw/docs/README.md`
- `ourclaw/docs/architecture/overall-design.md`
- `ourclaw/docs/planning/implementation-epics.md`
- `ourclaw/docs/planning/llm-task-breakdown.md`

## 当前状态

- 工程目录已初始化
- 设计文档已落盘
- contracts 文档已补齐
- 业务应用骨架已初始化
- 通用基础设施将逐步迁移到 `framework/`
