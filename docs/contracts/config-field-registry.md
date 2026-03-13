# ourclaw 配置字段注册表契约

## 1. 目标

本文档定义 `ourclaw` 配置字段注册表的统一契约。所有可读写配置字段都应通过注册表声明，以支撑：

- 配置校验
- 风险确认
- GUI 表单元数据
- 文档生成
- 日志脱敏
- 是否需要重启判断

## 2. 核心结构

建议统一定义：

```zig
pub const ConfigFieldDefinition = struct {
    path: []const u8,
    label: []const u8,
    description: []const u8,
    value_kind: ValueKind,
    required: bool = false,
    sensitive: bool = false,
    requires_restart: bool = false,
    risk_level: RiskLevel = .none,
    rules: []const ValidationRule,
};
```

## 3. ValueKind 建议

建议包含：

- `string`
- `integer`
- `boolean`
- `float`
- `enum_string`
- `object`
- `array`

## 4. RiskLevel 建议

建议包含：

- `none`
- `low`
- `medium`
- `high`

## 5. 路径规则

- 使用逻辑路径，如 `gateway.port`
- 不允许任意文件系统路径作为字段标识
- 路径必须稳定，避免 UI/CLI/bridge 三端不一致

## 6. 字段元数据要求

每个字段建议至少说明：

- 它是什么
- 值类型是什么
- 是否敏感
- 是否需要重启
- 是否高风险
- 适用哪些规则

## 7. 示例

```zig
.{
    .path = "gateway.port",
    .label = "Gateway Port",
    .description = "HTTP gateway listening port",
    .value_kind = .integer,
    .required = false,
    .sensitive = false,
    .requires_restart = true,
    .risk_level = .none,
    .rules = &.{ validate_port_rule },
}
```

```zig
.{
    .path = "models.providers.openai.api_key",
    .label = "OpenAI API Key",
    .description = "Credential for OpenAI provider",
    .value_kind = .string,
    .required = false,
    .sensitive = true,
    .requires_restart = false,
    .risk_level = .none,
    .rules = &.{ validate_non_empty_if_present_rule },
}
```

## 8. 注册表职责

注册表应支持：

- 按 `path` 查找字段
- 枚举全部字段
- 提供给校验器读取规则
- 提供给命令处理器判断 `requires_restart`
- 提供给日志系统判断 `sensitive`

## 9. 写回约束

所有配置写回都必须遵循：

1. 查注册表
2. 校验值类型
3. 执行字段规则
4. 执行对象级交叉规则
5. 判断风险确认
6. 写入配置

禁止直接在业务 handler 中绕过注册表写字段。

## 10. 与 GUI 的关系

后续 GUI 可以直接消费注册表元数据，用于：

- 自动生成表单
- 展示字段说明
- 标记敏感字段
- 标记高风险字段
- 显示“修改后需重启”提示

## 11. 验收要求

- 所有可写字段都已注册
- 注册表可被校验器和命令层共同使用
- `sensitive`、`requires_restart`、`risk_level` 元数据可直接读取
