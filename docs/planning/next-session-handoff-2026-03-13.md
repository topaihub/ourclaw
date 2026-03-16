# ourclaw 续接速览（2026-03-13）

> 用途：历史 dated handoff，保留为阶段快照参考，不再作为默认续做入口。

## 1. 当前目标

- 主线实现目录是：`framework/`、`ourclaw/`、`ourclaw-manager/`
- 参考目录是：`nullclaw/`、`openclaw/`、`nullclaw-manager/`
- 最终目标不是继续开发参考仓，而是：
  - 在 `framework/` 沉淀可复用 Zig 通用能力
  - 在 `ourclaw/` 实现对标 `openclaw` 的 claw runtime / agent / gateway / tool / stream / service 能力
  - 在 `ourclaw-manager/` 实现配置与管理应用

## 2. 文档主入口

继续工作时，优先看这几份：

1. `ourclaw/docs/specs/framework-based-ourclaw/requirements.md`
2. `ourclaw/docs/specs/framework-based-ourclaw/design.md`
3. `ourclaw/docs/specs/framework-based-ourclaw/tasks.md`
4. `ourclaw/docs/specs/framework-based-ourclaw/next-stage-backlog.md`
5. `ourclaw/docs/planning/session-resume.md`

说明：旧的 `architecture/`、`planning/` 文档未做全面清理，目前策略是**轻量提示“以新 spec 为准”**，而不是大规模重写。

## 3. 已完成到哪里

新的主线 spec 已建立：

- `ourclaw/docs/specs/framework-based-ourclaw/requirements.md`
- `ourclaw/docs/specs/framework-based-ourclaw/design.md`
- `ourclaw/docs/specs/framework-based-ourclaw/tasks.md`

并且已经把任务状态按当前代码现实做过一次校准，不要把任务表里的所有项都当成“未开始”。

当前已完成的 M2 任务：

- `M2-01` execution reconnect / resume
- `M2-02` CLI / Bridge / HTTP envelope 对齐
- `M2-03` gateway host listener-ready 宿主化
- `M2-04` service manager / daemon 后台运行模型
- `M2-05` 共享配置加载栈（file + env + object/array）
- `M2-06` field registry / migration / compat import 深化
- `M2-07` execution 级 observability 关联键
- `M2-08` prompt profile / identity-driven prompt assembly
- `M2-09` retrieval / embeddings / memory ranking
- `M2-10` provider / tool 第一阶段生产语义

当前**已完成**：

- `M2-09`：收口 retrieval / embeddings / memory ranking
- `M2-10`：把现有 provider / tool 做到生产语义第一阶段

## 4. 当前最重要的判断

- `framework/` 已经不是空壳，已有 `AppContext`、`CommandDispatcher`、`TaskRunner`、`EventBus`、错误模型、validation、envelope、config pipeline 等共享底座。
- `ourclaw/` 已经有第一版可运行主干：runtime、agent、session/memory、stream、tool loop、gateway/service/daemon、CLI/Bridge/HTTP、config、diagnostics/metrics。
- `nullclaw/` 更适合当 **Zig 架构与边界参考**。
- `openclaw/` 更适合当 **产品能力与控制平面对标参考**。
- 当前阶段不是回头重做底座，而是继续把 `ourclaw` 往产品级 runtime / provider / tool / memory 语义推进。

## 5. 当前建议继续的方向（主线 spec 已收口）

当前关注的代码：

- `ourclaw/src/providers/root.zig`
- `ourclaw/src/providers/openai_compatible.zig`
- `ourclaw/src/tools/root.zig`
- `ourclaw/src/domain/tool_orchestrator.zig`
- `ourclaw/src/domain/agent_runtime.zig`
- `ourclaw/tests/smoke.zig`

已知现状：

- `M2-01` ~ `M2-10` 已按当前主线 spec 全部完成
- provider/tool 已具备第一阶段生产语义：timeout / retry / budget / risk gating / audit / failure mapping 均有最小实现与回归覆盖
- 当前更适合转入“深化语义”或“启动新 spec/backlog”，而不是继续按旧 handoff 里的未完成项推进

如果继续往下做，建议优先选这几类后续工作：

- 把 provider/tool 的第一阶段生产语义深化到更真实的 cancel token / deadline 传播
- 为 `skills / tunnel / mcp / hardware / voice` 新建下一阶段任务或 spec
- 清理旧 `planning/` 文档与新 spec 的状态映射，减少历史漂移

## 6. 已知验证状态

- 近期已完成的 M2-01 ~ M2-08 都跑过验证
- 当前最新可确认状态：请以 `session-resume.md`、`current-task-board.md` 与最新测试输出为准；本文件中的计数只代表历史快照。

已知环境噪声：

- Windows 下 `gateway_host` listener 测试偶尔会向 stderr 打出 `GetLastError(87)`
- 但 `zig build test --summary all` 仍然成功
- 这目前视为环境噪声，不作为功能失败处理

## 7. Git 约束与工作方式

- 工作区原本没有 git 仓库
- 已在以下目录初始化本地 git 仓库：
  - `framework/`
  - `ourclaw/`
  - `ourclaw-manager/`
- 已加 `.gitignore`，清理 `.zig-cache/`、`zig-out/` 等构建产物
- 用户明确要求：**每完成一个子任务及时做 git 提交**

继续工作时必须遵守：

- 不要在 `nullclaw/`、`openclaw/`、`nullclaw-manager/` 里落主线实现
- 修改前先确认最终落点是 `framework/`、`ourclaw/`、还是 `ourclaw-manager/`
- 完成每个子任务后都要测试，并及时提交

## 8. 下个会话建议动作

建议直接按下面顺序继续：

1. 打开 `ourclaw/docs/specs/framework-based-ourclaw/tasks.md`
2. 确认主线第一阶段已完成，并跳转 `next-stage-backlog.md`
3. 按 `next-stage-backlog.md` 中当前仍为 `active/todo` 的顺序挑一个 backlog 子项
4. 实现一个子项 → 跑 `zig build test --summary all`
5. 更新 `current-task-board.md`、`session-resume.md` 与 `next-stage-backlog.md`

## 9. 可直接贴给新模型的续接提示词

你现在在 `ourclaw-dev` 工作区继续开发，必须遵守以下边界：

- 主线实现只能落在 `framework/`、`ourclaw/`、`ourclaw-manager/`
- `nullclaw/`、`openclaw/`、`nullclaw-manager/` 仅作为参考，不要直接往参考目录写代码
- 输出与沟通默认使用简体中文

当前主入口文档：

- `ourclaw/docs/specs/framework-based-ourclaw/requirements.md`
- `ourclaw/docs/specs/framework-based-ourclaw/design.md`
- `ourclaw/docs/specs/framework-based-ourclaw/tasks.md`
- `ourclaw/docs/specs/framework-based-ourclaw/next-stage-backlog.md`
- `ourclaw/docs/planning/session-resume.md`
- `ourclaw/docs/planning/next-session-handoff-2026-03-13.md`

当前进度：本文件所述状态是历史快照；当前进度请以 `next-stage-backlog.md`、`session-resume.md` 与 `current-task-board.md` 为准。

当前要继续的任务是：**从 `next-stage-backlog.md` 里选择下一阶段 backlog，而不是继续回到旧 M2 任务。**

先阅读以下文件：

- `ourclaw/docs/specs/framework-based-ourclaw/next-stage-backlog.md`
- `docs/planning/current-task-board.md`
- `ourclaw/docs/planning/session-resume.md`
- 对应 backlog 子项涉及的代码文件

工作要求：

- 先基于当前实现做增量收口，不要推翻重写
- 参考 `nullclaw/` 的 Zig 边界设计与 `openclaw/` 的产品语义
- 每完成一个子任务都要运行测试并更新文档状态
- 不要重复实现已经归档完成的主线任务

本轮目标是：从 `next-stage-backlog.md` 中选择一个 backlog 子项推进；完成后更新 spec / session-resume / current-task-board 中对应状态。
