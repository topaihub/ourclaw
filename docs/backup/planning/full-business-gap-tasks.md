# ourclaw 完整业务版 GAP Tasks

> 使用说明（2026-03-16）：本文档保留为“历史 FB 任务拆分与阶段判断”参考，但其中状态**不再保证**与当前代码同步。当前如需继续推进主线实现，请优先使用：
>
> - `ourclaw/docs/specs/reference-aligned-ourclaw/requirements.md`
> - `ourclaw/docs/specs/reference-aligned-ourclaw/design.md`
> - `ourclaw/docs/specs/reference-aligned-ourclaw/tasks.md`
>
> 如需理解旧任务编号与阶段背景，可把本文档与 `session-resume.md`、新 spec 一起交叉阅读；不要再把本文档当成 live checklist 或默认续做入口。

## 1. 目标

本文档在 `ourclaw/docs/planning/nullclaw-gap-analysis.md` 的基础上，进一步把“从最小业务层推进到接近 nullclaw 完整业务版”的工作拆成更适合交给大模型持续执行的任务清单。

## 2. 状态定义

- `done`：已完成
- `partial`：已落最小版
- `todo`：未开始或未形成可用能力

## 3. 当前总判断

- `framework` 共享运行时：`done`
- `ourclaw` 最小业务层：`partial`
- `ourclaw` 完整业务版：仍大量 `todo`

## 4. 任务总览

### Phase A：把最小业务命令推进到完整业务版

| ID | 任务 | 当前状态 |
|---|---|---|
| FB-01 | 完善 `app.meta` 输出：版本、build、runtime、capabilities、health 摘要 | done |
| FB-02 | 完善 `config.get`：支持批量、元数据、脱敏显示、来源说明 | done |
| FB-03 | 完善 `config.set`：支持 preview、risk confirm、diff 详情、write summary | done |
| FB-04 | 完善 `logs.recent`：支持过滤、级别、subsystem、traceId | done |

### Phase B：补全配置运行时

| ID | 任务 | 当前状态 |
|---|---|---|
| FB-05 | 实现 `loader.zig`、`parser.zig`、`defaults.zig` | todo |
| FB-06 | 扩展 field registry，覆盖更多配置字段 | partial |
| FB-07 | 实现 config migration / compatibility import | todo |
| FB-08 | 完善 config side effect 与 post-write hook 真实行为 | partial |

### Phase C：补全 provider / channel / tool 实际业务能力

| ID | 任务 | 当前状态 |
|---|---|---|
| FB-09 | 实现一个真实 OpenAI-compatible provider | done |
| FB-10 | 实现 provider health / model listing / streaming 能力 | done |
| FB-11 | 实现最小真实 CLI channel | todo |
| FB-12 | 实现 bridge / HTTP 关联的 channel/runtime 语义 | todo |
| FB-13 | 实现 file/shell/http 三个真实高价值工具 | done |
| FB-14 | 完善 tool security、schema、error mapping | done |

### Phase D：补 agent runtime 主链路

| ID | 任务 | 当前状态 |
|---|---|---|
| FB-15 | 实现 `agent-runtime` 主循环 | done |
| FB-16 | 实现 prompt assembly / system prompt / tools prompt 注入 | todo |
| FB-17 | 实现 provider → tool → provider 多步 loop | done |
| FB-18 | 实现 session snapshot / compaction / summary | partial |
| FB-19 | 实现真正流式输出协议与 adapter 投影 | partial |

### Phase E：补 memory 与检索能力

| ID | 任务 | 当前状态 |
|---|---|---|
| FB-20 | 实现 memory store abstraction | done |
| FB-21 | 实现最小本地 memory backend | done |
| FB-22 | 实现 recall / append / tool result memory 写回 | done |
| FB-23 | 实现 embeddings / retrieval / migration 路线 | partial |

### Phase F：补长期运行与控制面

| ID | 任务 | 当前状态 |
|---|---|---|
| FB-24 | 实现 ourclaw gateway/runtime host | partial |
| FB-25 | 实现 service/daemon 模型 | partial |
| FB-26 | 实现 health / diagnostics / task query 命令域 | done |
| FB-27 | 完善 event bus / observer / metrics 查询面 | partial |

### Phase G：补高级能力面

| ID | 任务 | 当前状态 |
|---|---|---|
| FB-28 | 实现 skills / skillforge | partial |
| FB-29 | 实现 cron / heartbeat | partial |
| FB-30 | 实现 tunnel / mcp | partial |
| FB-31 | 实现 peripherals / hardware | partial |
| FB-32 | 实现 voice | todo |

## 5. 建议执行顺序

建议按以下顺序交给大模型推进：

1. FB-01 ~ FB-04
2. FB-05 ~ FB-08
3. FB-09 ~ FB-14
4. FB-15 ~ FB-19
5. FB-20 ~ FB-23
6. FB-24 ~ FB-27
7. FB-28 ~ FB-32

## 6. 大模型执行约束

每次交给大模型时建议遵循：

1. 一次只做一个 FB 任务或一组非常紧耦合的小任务
2. 先补类型、契约、测试，再补深实现
3. 每完成一轮，都同步更新 `ourclaw/docs/planning/session-resume.md`
4. 设计判断必须写回 docs，而不是只留在上下文

## 7. 近期最值得先做的 10 项

1. FB-01
2. FB-02
3. FB-03
4. FB-09
5. FB-13
6. FB-15
7. FB-19
8. FB-20
9. FB-24
10. FB-26

## 8. 当前结论

- `ourclaw` 已经拥有最小业务层与共享运行时骨架
- 现在最适合的开发策略，是把“完整业务版”拆成上面的 FB tasks 持续推进
- 本文档比 `nullclaw-gap-analysis.md` 更适合直接交给大模型逐步执行
