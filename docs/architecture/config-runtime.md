# ourclaw 配置运行时详细设计

## 1. 目标与范围

本文档定义 `ourclaw` 完整业务版的配置运行时，包括：

- 配置读取
- 默认值装配
- 兼容解析
- 字段注册表
- 校验与风险确认
- 受控写回
- diff / change log / side effect / post-write hook

> 当前共享实现已先落在 `framework/src/config/store.zig`、`framework/src/config/pipeline.zig`，并已补 `framework/src/config/parser.zig`、`framework/src/config/defaults.zig`、`framework/src/config/loader.zig` 第一版；`ourclaw` 侧则已有 `ourclaw/src/config/field_registry.zig` 与 `ourclaw/src/config/runtime.zig` 的最小装配。完整配置运行时尚未完成，但 `loader / parser / defaults` 主链路第一版已落地。

## 2. 设计目标

1. 配置读取、校验、写回都走统一 runtime
2. 所有可写字段必须来自 field registry
3. 支持 defaults / migration / compat import
4. 写回必须能产出 diff summary、change log、side effect、post-write summary
5. 敏感字段读写与日志必须可控脱敏

## 3. 模块边界

建议完整模块结构：

```text
src/config/
  loader.zig
  parser.zig
  defaults.zig
  field_registry.zig
  validators.zig
  migration.zig
  compatibility.zig
```

当前第一版实际落点：

- `framework/src/config/parser.zig`：共享标量配置值解析（命令输入 / bootstrap default JSON）
- `framework/src/config/defaults.zig`：共享默认值表与 bootstrap seeding
- `framework/src/config/loader.zig`：统一读取 runtime store + bootstrap defaults，并稳定产出 source/sourceHint 所需来源判断
- `ourclaw/src/config/runtime.zig`：装配 `ourclaw` 的默认配置、loader 入口与 parser 入口

完整版建议继续保持：

- `loader.zig`：文件加载与环境变量覆盖
- `parser.zig`：配置结构解析
- `defaults.zig`：默认值生成
- `field_registry.zig`：字段定义与元数据
- `validators.zig`：对象级交叉规则
- `migration.zig`：版本迁移
- `compatibility.zig`：导入旧配置

## 4. 配置读取链路

建议完整读取顺序：

1. 读取配置文件
2. 应用 defaults
3. 解析结构
4. 迁移旧版本字段
5. 应用环境变量覆盖
6. 执行字段级校验
7. 执行对象级交叉规则
8. 产出 runtime snapshot

## 5. Config Field Registry

完整业务版中，注册表不仅要提供：

- `path`
- `label`
- `description`
- `value_kind`
- `required`
- `sensitive`
- `requires_restart`
- `risk_level`

还应提供：

- `category`
- `display_group`
- `default_value`
- `allowed_in_sources`
- `side_effect_kind`
- `migration_aliases`

当前第一版已经落地：

- `category`
- `display_group`
- `default_value_json`
- `allowed_in_sources`
- `side_effect_kind`

仍未落地的主要是：

- `migration_aliases`

## 6. Config Write Pipeline

完整写回链路建议如下：

1. 查注册表
2. 解析输入值
3. 字段级校验
4. 对象级交叉规则
5. 风险确认
6. 生成 diff
7. 写入 store
8. 写入 change log
9. 触发 side effect
10. 触发 post-write hook
11. 发送 `config.changed` 事件

## 7. Diff / Change Log / Side Effect

当前共享层已经具备：

- `ConfigChange.kind`
- `sensitive`
- `value_kind`
- `requires_restart`
- `side_effect_kind`
- `change_log`
- `post_write_hook`

完整版建议继续补：

- `old_display_value`
- `new_display_value`
- `risk_level`
- `source`
- `actor`
- `effective_at`

## 8. Defaults / Migration / Compat

完整版配置运行时必须支持：

- 初次启动生成最小默认配置
- 旧版本配置迁移
- 导入 `nullclaw` / `openclaw` 兼容配置

当前第一版已经落地：

- `config.migrate_preview`：结构化预览 legacy alias rewrite 与版本迁移摘要
- `config.migrate_apply`：把 preview 后的规范化字段写入现有 config pipeline / store
- `config.compat_import`：支持 `generic / nullclaw / openclaw` source kind 的 compatibility import 第一版
- `ourclaw/src/runtime/config_runtime_hooks.zig`：把 side effect / post-write hook 接到 ourclaw runtime，提供最小真实行为

## 9. Secret / Sensitive 配置

敏感字段建议遵循：

- store 可以保存真实值
- `config.get` 默认返回脱敏值
- change log 默认记录脱敏值
- 日志系统绝不打印真实 secret

## 10. 当前差距

- `loader/parser/defaults` 已有第一版，但目前仍以标量字段和 bootstrap defaults 为主，尚未覆盖文件加载、环境变量覆盖、复杂 object/array 解析
- field registry 覆盖面已从最小演示级扩到首批 manager 相关字段，但距离完整业务版仍不够
- side effect / post-write hook 已有第一版真实行为，但仍未进入完整生产级副作用体系
- migration / compat import 已有第一版命令入口，但还没有完整的配置文件 schema versioning / migration rules / source-specific importer 体系

## 11. 验收标准

完整业务版至少应满足：

1. 可以从文件完整加载配置并生成 runtime snapshot
2. 所有可写字段都来自 field registry
3. `config.set` 能稳定产出 diff / change log / side effect / post-write summary
4. 能兼容导入旧配置
