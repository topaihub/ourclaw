# ourclaw 错误模型契约

## 1. 目标

本文档定义 `ourclaw` 对外暴露的统一错误模型契约，供 CLI、bridge、HTTP、后台服务与后续 GUI 共享。

目标：

- 统一错误码命名
- 统一用户可见错误结构
- 区分内部错误与对外错误
- 为日志、trace、事件、任务状态提供稳定错误标识

当前共享实现已先落在 `framework/src/core/error.zig`，由 `ourclaw` 和未来 `ourclaw-manager` 共同复用。

## 2. 设计原则

- 内部使用 Zig error union 控制流
- 外部边界统一输出 `AppError`
- 对外错误结构稳定，内部错误细节可演进
- `message` 面向开发和日志，`user_message` 面向用户
- `code` 必须稳定且可枚举

## 3. 核心结构

建议定义：

```zig
pub const AppError = struct {
    code: []const u8,
    message: []const u8,
    user_message: ?[]const u8 = null,
    retryable: bool = false,
    target: ?[]const u8 = null,
    details_json: ?[]const u8 = null,
};
```

字段说明：

- `code`：稳定错误码
- `message`：开发和日志用错误说明
- `user_message`：用户可直接展示的友好提示
- `retryable`：是否建议重试
- `target`：建议聚焦的域、页面或命令目标
- `details_json`：结构化补充信息

## 4. 错误码命名规则

建议格式：`<DOMAIN>_<KIND>`，全部大写，下划线分隔。

建议域前缀：

- `CORE_*`
- `VALIDATION_*`
- `CONFIG_*`
- `RUNTIME_*`
- `SERVICE_*`
- `PROVIDER_*`
- `CHANNEL_*`
- `TOOL_*`
- `SECURITY_*`
- `LOGGING_*`

示例：

- `CORE_INTERNAL_ERROR`
- `VALIDATION_FAILED`
- `CONFIG_FIELD_UNKNOWN`
- `RUNTIME_TIMEOUT`
- `SERVICE_OPERATION_FAILED`
- `SECURITY_PATH_NOT_ALLOWED`

## 5. 错误分类建议

### 5.1 协议/入口层

- `CORE_INVALID_REQUEST`
- `CORE_METHOD_NOT_FOUND`
- `CORE_METHOD_NOT_ALLOWED`
- `CORE_TIMEOUT`
- `CORE_INTERNAL_ERROR`

### 5.2 校验层

- `VALIDATION_FAILED`
- `VALIDATION_UNKNOWN_FIELD`
- `VALIDATION_TYPE_MISMATCH`
- `VALIDATION_VALUE_OUT_OF_RANGE`
- `VALIDATION_RISK_CONFIRMATION_REQUIRED`

### 5.3 配置层

- `CONFIG_LOAD_FAILED`
- `CONFIG_PARSE_FAILED`
- `CONFIG_FIELD_UNKNOWN`
- `CONFIG_WRITE_FAILED`
- `CONFIG_MIGRATION_FAILED`

### 5.4 安全层

- `SECURITY_PATH_NOT_ALLOWED`
- `SECURITY_COMMAND_NOT_ALLOWED`
- `SECURITY_SECRET_REF_INVALID`
- `SECURITY_POLICY_DENIED`

### 5.5 运行时/任务层

- `RUNTIME_TASK_NOT_FOUND`
- `RUNTIME_TASK_CANCELLED`
- `RUNTIME_TASK_FAILED`
- `RUNTIME_SHUTTING_DOWN`

## 6. details 结构约定

`details_json` 推荐承载结构化补充信息，常见场景如下：

- 校验失败时附 `issues[]`
- 配置失败时附 `path`、`valueKind`
- service 失败时附 `stderr`、`exitCode`
- task 失败时附 `taskId`

推荐示例：

```json
{
  "issues": [
    {
      "path": "gateway.port",
      "code": "VALUE_OUT_OF_RANGE",
      "message": "port must be between 1 and 65535"
    }
  ]
}
```

## 7. 与日志和 trace 的关系

- `AppError.code` 应写入日志字段 `error_code`
- 同一请求中的失败 span 应记录相同错误码
- runtime event 中的失败任务也应携带同一错误码

## 8. 与 Envelope 的关系

所有外部响应中的失败分支都应嵌入 `AppError`，不直接暴露原始 Zig error 名称。

## 9. 映射约定

建议提供统一映射函数：

- `fromValidationReport(...)`
- `fromInternalError(...)`
- `fromErrorName(...)`
- `fromTimeout(...)`
- `fromSecurityDenied(...)`

当前共享实现已先提供：

- `framework/src/core/error.zig` 的 `fromKind(...)`
- `framework/src/core/error.zig` 的 `fromValidationReport(...)`
- `framework/src/core/error.zig` 的 `fromErrorName(...)`
- `framework/src/core/error.zig` 的 `fromInternalError(...)`
- `framework/src/core/error.zig` 的 `fromTimeout(...)`
- `framework/src/core/error.zig` 的 `fromSecurityDenied(...)`

当前规则：

- 已知内部错误名会映射到稳定错误码
- 未识别的内部错误名会回退为 `CORE_INTERNAL_ERROR`
- `Timeout`、`RequestTimeout`、`ConnectionTimedOut` 会统一映射到 `CORE_TIMEOUT`
- `ValidationError`、`UnknownField`、`TypeMismatch` 等常见校验错误名会统一映射到 `VALIDATION_*`
- `ValidationReport` 会优先按 issue code 映射到更具体的 `VALIDATION_*`，例如 unknown field、type mismatch、value out of range、risk confirmation required
- 若 primary issue 带有 `details_json`，共享 `AppError.details_json` 会尽量保留这部分结构化上下文

映射规则要求：

- 不丢失稳定错误码
- 尽量保留结构化 details
- 不把敏感信息直接写进 `user_message`

## 10. 验收要求

完成实现时，应满足：

- 对外错误结构统一
- 错误码稳定、可枚举
- 校验失败可带 `issues[]`
- 日志/trace/task 可共享同一错误码
