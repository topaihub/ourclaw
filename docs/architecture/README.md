# architecture

`ourclaw/docs/architecture/` 只负责解释 `ourclaw` 业务层本身的结构，不再承担 `framework` 底座文档职责。

## 建议阅读顺序

1. `overall-design.md`
2. `agent-runtime.md`
3. `provider-channel-tool.md`
4. `config-runtime.md`
5. `adapters.md`
6. `manager-reuse.md`

## 文件索引

- `overall-design.md`
  - 解释 `framework / ourclaw / ourclaw-manager` 三层关系
- `agent-runtime.md`
  - 解释 agent runtime、prompt、tool、memory、session 的主链路
- `provider-channel-tool.md`
  - 解释 provider / channel / tool 三个扩展面如何协作
- `config-runtime.md`
  - 解释 config schema、runtime hook、control-plane 与运行态的关系
- `adapters.md`
  - 解释 CLI / HTTP / bridge 等接口层适配方式
- `manager-reuse.md`
  - 解释 manager 如何复用 runtime contract / runtime_client

## 不再在这里展开的主题

以下属于 `framework` 通用底座能力，应直接去 `framework/docs/architecture/`：

- `logging.md`
- `validation.md`
- `runtime-pipeline.md`

## 一句结论

如果要理解 `ourclaw` 业务结构，看这里；
如果要理解共享底座能力，看 `framework/docs/architecture/`。
