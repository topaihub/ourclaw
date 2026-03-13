# ourclaw 校验体系详细设计

## 1. 目标与范围

本文档定义 `ourclaw` 的统一校验体系，目标是解决当前 `nullclaw` 与 `nullclaw-manager` 中校验逻辑分散、错误表达不统一、配置规则与请求规则混杂的问题。

> 当前共享实现已先落在 `framework/src/core/validation/*`。截至 2026-03-11，`issue.zig`、`report.zig`、`rule.zig`、`rules_basic.zig`、`rules_security.zig`、`rules_config.zig`、`validator.zig` 与 `framework/src/core/error.zig` 中的 `fromValidationReport(...)` 已有第一版实现；当前已支持 request/config 模式、unknown field 严格拒绝、基础 object/array/schema 校验、安全规则、配置交叉字段规则，以及 issue-level `details_json`。primitive array element rules、对象数组 schema 推断与嵌套 details 也已接通；更完整的规则库仍待后续补齐。

本文档覆盖：

- 统一校验模型
- 校验层级与执行顺序
- 字段注册表设计
- 请求校验与配置校验的接线方式
- 安全规则与风险确认模型
- 校验与错误模型的映射关系
- 测试与验收策略

## 2. 设计目标

`ourclaw` 的校验体系必须满足以下目标：

1. 所有外部输入都有统一校验入口
2. 校验结果可结构化返回，不只依赖错误码
3. 配置校验和命令参数校验共享基础规则体系
4. 支持跨字段规则与安全规则
5. 支持风险确认而不是简单拒绝
6. GUI、CLI、bridge 可以复用同一份 issue 数据
7. 校验与业务 handler 解耦

## 3. 核心问题定义

当前已有代码里的主要问题包括：

- 同类规则在不同模块重复实现
- 外部输入有时直接在 handler 中写 if/else 判定
- 配置字段元数据与实际校验规则没有统一来源
- 失败时有时只返回 Zig error，不返回字段级 issue

因此，`ourclaw` 需要先定义校验的公共语言，再让配置、命令、桥接和安全模块都接入这套语言。

## 4. 总体设计原则

### 4.1 校验前置

外部输入必须在进入业务 handler 之前完成校验。

### 4.2 问题可枚举

校验结果不能只有 `true/false`，必须能够输出多条 `ValidationIssue`。

### 4.3 模型与规则分离

字段定义、规则定义、执行器、结果模型必须分层。

### 4.4 严格优先

对于：

- 未知字段
- 类型错误
- 非法路径
- 越权访问

默认使用严格拒绝策略。

### 4.5 风险型配置与错误型配置分离

有些输入不是无效，而是高风险。例如：

- 监听 `0.0.0.0`
- 关闭 pairing 保护
- 关闭日志脱敏

这些场景应通过 `risk confirmation` 流程处理，而不是简单当作非法值。

## 5. 模块边界

建议模块结构如下：

```text
src/core/validation/
  issue.zig
  report.zig
  validator.zig
  rule.zig
  rules_basic.zig
  rules_security.zig
  rules_config.zig
  assert.zig

src/config/
  field_registry.zig
  validators.zig
```

模块职责建议如下：

- `issue.zig`：定义 `ValidationIssue` 及 severity/code
- `report.zig`：定义 `ValidationReport`
- `rule.zig`：定义规则接口、规则上下文
- `validator.zig`：规则执行器与 builder
- `rules_basic.zig`：字符串、整数、布尔、枚举、长度、范围等基础规则
- `rules_security.zig`：路径、命令、secret id、URL、host、port 等安全规则
- `rules_config.zig`：配置专属规则
- `assert.zig`：内部不变量断言，不负责外部输入校验
- `field_registry.zig`：配置字段元数据中心
- `config/validators.zig`：配置对象级交叉字段规则

## 6. 核心数据模型

## 6.1 ValidationSeverity

建议定义：

- `error`
- `warn`
- `info`

默认只有 `error` 会阻止提交；`warn` 和 `info` 可用于风险提示与补充说明。

## 6.2 ValidationIssue

建议统一定义：

```zig
pub const ValidationIssue = struct {
    path: []const u8,
    code: []const u8,
    severity: ValidationSeverity,
    message: []const u8,
    hint: ?[]const u8 = null,
    retryable: bool = false,
    details_json: ?[]const u8 = null,
};
```

字段说明：

- `path`：逻辑路径，如 `gateway.port` 或 `params.providerId`
- `code`：稳定问题码，例如 `VALUE_OUT_OF_RANGE`
- `severity`：错误级别
- `message`：主要错误说明
- `hint`：修复建议
- `retryable`：是否建议用户调整后重试
- `details_json`：可选结构化补充信息

## 6.3 ValidationReport

建议定义：

```zig
pub const ValidationReport = struct {
    ok: bool,
    issue_count: usize,
    issues: []const ValidationIssue,
    warning_count: usize,
    error_count: usize,
};
```

约束：

- `ok == true` 不代表没有 warning，只代表没有阻断错误
- 所有校验层统一产出同一种报告模型

## 6.4 RuleContext

建议定义规则执行上下文：

```zig
pub const RuleContext = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    field_meta: ?*const ConfigFieldDefinition = null,
    mode: ValidationMode,
    confirm_risk: bool = false,
};
```

`ValidationMode` 可区分：

- `request`
- `config_write`
- `config_load`
- `security_check`

## 7. 校验层次与执行顺序

建议严格按以下顺序执行：

1. 输入解析校验
2. schema 校验
3. 基础规则校验
4. 语义规则校验
5. 交叉字段校验
6. 安全规则校验
7. 风险确认校验

## 7.1 输入解析校验

负责判断：

- 请求是否为对象
- 字段类型是否可读
- JSON 是否可解析
- 必填字段是否存在

这个阶段失败时，一般直接返回 `INVALID_PARAMS` 类问题。

## 7.2 schema 校验

负责判断：

- 字段是否存在于允许集合
- 每个字段类型是否正确
- 是否存在未知字段

第一阶段不一定要引入完整 schema DSL，但必须先做到严格对象字段校验。

## 7.3 基础规则校验

典型规则：

- 非空字符串
- 最小/最大长度
- 整数范围
- 布尔类型
- 枚举取值
- 字符串前缀/后缀
- 路径段格式

这些规则应沉淀在 `rules_basic.zig`，供 request 和 config 复用。

## 7.4 语义规则校验

典型语义规则：

- `gateway.port` 必须位于 `1..65535`
- `agents.defaults.model.primary` 不能为空
- `logging.file.path` 在开启文件日志时必须可解析

这层比基础规则更接近业务含义，但仍然不应放进 handler。

## 7.5 交叉字段校验

典型场景：

- `gateway.tailscale.mode != off` 时，`gateway.bind` 必须是 loopback 语义
- 开启 `logging.file.enabled` 时，`logging.file.path` 不可为空
- 开启某 provider 时，对应 credential 字段必须存在

这类规则应单独在 `config/validators.zig` 维护，避免散落在多处。

## 7.6 安全规则校验

这部分是 `ourclaw` 必须重点强化的地方。

典型规则包括：

- 路径是否逃逸允许根目录
- secret ref id 是否包含 `.` 或 `..` 段
- host 是否为合法 IPv4 或可接受主机名
- command id 是否在允许清单中
- URL 是否符合允许协议和域名策略

建议统一在 `rules_security.zig` 中沉淀。

## 7.7 风险确认校验

对于高风险但不一定非法的变更，采用“显式确认”模型。

例如：

- `gateway.host = 0.0.0.0`
- `gateway.require_pairing = false`
- `logging.redact.mode = off`

如果未携带 `confirm_risk`，则返回：

- `severity = error`
- `code = RISK_CONFIRMATION_REQUIRED`
- 并附带具体风险描述

## 8. 字段注册表设计

## 8.1 目标

配置字段注册表是 `ourclaw` 配置治理的核心元数据中心。所有可写配置字段都必须在注册表中声明。

## 8.2 ConfigFieldDefinition

建议定义：

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

建议 `ValueKind` 包含：

- `string`
- `integer`
- `boolean`
- `float`
- `enum_string`
- `object`
- `array`

建议 `RiskLevel` 包含：

- `none`
- `low`
- `medium`
- `high`

## 8.3 注册表的作用

同一份字段注册表至少服务于：

- 配置写回校验
- 文档生成
- GUI 表单元数据
- 风险提示
- 是否需要重启判断
- 日志脱敏判定

## 9. 请求校验设计

除了配置校验，还需要命令参数校验。

建议每个命令注册时提供参数 schema 元数据，例如：

```zig
pub const CommandParamDefinition = struct {
    key: []const u8,
    required: bool,
    value_kind: ValueKind,
    rules: []const ValidationRule,
};
```

命令分发器在执行 handler 前，应使用：

- 命令元数据
- 参数对象
- 安全上下文

构造一次完整 `ValidationReport`。

## 10. unknown field 策略

建议默认严格拒绝未知字段。

理由：

- 防止拼写错误悄悄被忽略
- 防止能力泄漏
- 防止桥接层和 GUI 端调用旧字段产生不确定行为

对于向前兼容扩展，建议通过版本化 schema 或新增字段声明来处理，而不是默认忽略未知字段。

## 11. Assert 的角色

`Assert` 保留，但职责收缩为：

- 验证内部不变量
- 验证本不该被外部输入触发的开发期错误

禁止把 `Assert` 用作：

- CLI 参数校验
- bridge 请求校验
- 配置字段合法性校验

换句话说：

- `Assert` 面向开发者
- `Validator` 面向外部输入

## 12. 校验与错误模型的关系

校验层不应直接返回零散 Zig error，而应先汇总为 `ValidationReport`，再由边界层映射到统一错误模型。

建议映射规则：

- `ValidationReport.ok == true`：继续执行
- 存在 `error` 级 issue：映射为 `VALIDATION_FAILED`
- 仅有 warning：允许继续，但在结果中附带 warning

典型错误模型示例：

```json
{
  "code": "VALIDATION_FAILED",
  "message": "request validation failed",
  "userMessage": "输入参数不符合要求",
  "details": {
    "issues": [
      {
        "path": "gateway.port",
        "code": "VALUE_OUT_OF_RANGE",
        "message": "port must be between 1 and 65535"
      }
    ]
  }
}
```

## 13. 配置写入流程中的校验接线

建议配置写入流程如下：

1. 解析逻辑路径
2. 查字段注册表
3. 校验值类型
4. 执行字段规则
5. 执行交叉字段规则
6. 执行安全规则
7. 判断是否需要风险确认
8. 通过后写入配置
9. 记录变更日志与 warning

所有配置写入都必须走这条流程，不允许业务代码直接修改 JSON 对象后落盘。

## 14. 安全规则建议清单

建议第一阶段至少落地以下规则：

- `validateNonEmptyString`
- `validateLengthRange`
- `validateIntegerRange`
- `validateEnumValue`
- `validateIpv4Address`
- `validateHostnameOrIpv4`
- `validatePort`
- `validatePathNoTraversal`
- `validatePathWithinAllowedRoots`
- `validateSecretRefId`
- `validateUrlProtocol`
- `validateCommandIdAllowed`

这些规则可以覆盖大部分配置、桥接命令和安全边界需求。

## 15. 风险提示模型

有些问题不应被建模为“非法输入”，而应建模为“风险提示”。

建议定义：

```zig
pub const ValidationOutcome = struct {
    report: ValidationReport,
    requires_confirmation: bool,
};
```

这样可以支持以下交互：

- CLI 提示用户加 `--confirm-risk`
- GUI 弹出确认对话框
- bridge 返回 `RISK_CONFIRMATION_REQUIRED`

## 16. 测试策略

建议覆盖以下测试：

### 16.1 基础规则测试

- 字符串长度
- 枚举值
- 端口范围
- IPv4/host 合法性
- path traversal 阻断

### 16.2 注册表测试

- 字段查找
- value kind 匹配
- `requires_restart`、`sensitive`、`risk_level` 元数据可用

### 16.3 配置校验测试

- 单字段错误
- 跨字段错误
- 风险确认缺失
- unknown field 拒绝

### 16.4 请求校验测试

- params 非 object
- 缺少必填字段
- 字段类型错误
- 越权参数注入

## 17. 实施顺序建议

建议按以下顺序落地：

1. `issue.zig` + `report.zig`
2. `rules_basic.zig`
3. `validator.zig`
4. `field_registry.zig`
5. `rules_security.zig`
6. `config/validators.zig`
7. 命令参数校验元数据
8. 风险确认接线
9. 错误映射集成

## 18. 验收标准

校验体系完成时，应满足：

- 任意外部输入都能得到结构化校验结果
- 配置写入必须经过字段注册表与规则执行器
- request/bridge/CLI 共用同一套基础规则
- 支持跨字段校验与安全规则校验
- 支持风险确认而不只是简单报错
- 边界层能稳定映射为统一错误模型

## 19. 结论

`ourclaw` 的校验体系不是若干帮助函数的集合，而是一套统一的输入治理框架。只有先建立好 `ValidationIssue`、字段注册表和严格执行顺序，后续配置系统、桥接系统和 GUI 才能共享同一套稳定规则。
