# architecture

## 角色

`ourclaw/docs/architecture/` 现在只负责解释：

- `ourclaw` 业务层如何消费共享底座
- 当前业务域的边界、角色和演进意图

它不再承担“框架底座能力说明”的职责。

## 已迁移到 framework 的底座文档

以下主题现在属于 `framework` 共享能力：

- `framework/docs/architecture/logging.md`
- `framework/docs/architecture/validation.md`
- `framework/docs/architecture/runtime-pipeline.md`

在本目录下同名文件仅保留为跳转页。

## 当前建议保留并继续更新的文档

- `overall-design.md`
- `agent-runtime.md`
- `provider-channel-tool.md`
- `config-runtime.md`
- `adapters.md`
- `manager-reuse.md`

## 后续建议

- `overall-design.md`：按当前 `framework / ourclaw / ourclaw-manager` 三层结构重写顶部背景说明
- `manager-reuse.md`：按当前 `runtime_client` 与 manager contract 现状更新复用边界
- `agent-runtime.md`、`provider-channel-tool.md`：把“尚未落地”的旧表述改成“已落第一版、继续深化”的现状描述

## 一句结论

如果你想知道“底座能力本身是什么”，去看 `framework/docs/`；
如果你想知道“ourclaw 业务层怎样使用这些能力”，看这里。
