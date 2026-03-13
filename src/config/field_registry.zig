const std = @import("std");
const framework = @import("framework");

pub const ValueKind = framework.ValueKind;
pub const ValidationRule = framework.ValidationRule;
pub const FieldDefinition = framework.FieldDefinition;
pub const ConfigRule = framework.ConfigRule;

pub const RiskLevel = enum {
    none,
    low,
    medium,
    high,
};

pub const ConfigCategory = enum {
    gateway,
    logging,
    providers,
    runtime,
    service,
};

pub const DisplayGroup = enum {
    network_bind,
    access_control,
    file_logging,
    provider_openai,
    provider_anthropic,
    runtime_limits,
    service_lifecycle,
};

pub const AllowedSource = enum {
    bootstrap_default,
    runtime_store,
    env_override,
    compat_import,
};

const DEFAULT_ALLOWED_SOURCES = [_]AllowedSource{ .bootstrap_default, .runtime_store };
const SECRET_ALLOWED_SOURCES = [_]AllowedSource{ .runtime_store, .env_override, .compat_import };

pub const ConfigFieldDefinition = struct {
    path: []const u8,
    label: []const u8,
    description: []const u8,
    category: ConfigCategory,
    display_group: DisplayGroup,
    value_kind: ValueKind,
    required: bool = false,
    sensitive: bool = false,
    requires_restart: bool = false,
    risk_level: RiskLevel = .none,
    default_value_json: ?[]const u8 = null,
    side_effect_kind: framework.ConfigSideEffectKind = .none,
    allowed_in_sources: []const AllowedSource = DEFAULT_ALLOWED_SOURCES[0..],
    field_definition: FieldDefinition,
};

const FIELD_DEFINITIONS = [_]ConfigFieldDefinition{
    .{
        .path = "gateway.host",
        .label = "Gateway Host",
        .description = "Gateway bind host",
        .category = .gateway,
        .display_group = .network_bind,
        .value_kind = .string,
        .required = true,
        .requires_restart = true,
        .default_value_json = "\"127.0.0.1\"",
        .side_effect_kind = .restart_required,
        .field_definition = .{
            .key = "gateway.host",
            .required = true,
            .requires_restart = true,
            .value_kind = .string,
            .rules = &.{.hostname_or_ipv4},
        },
    },
    .{
        .path = "gateway.port",
        .label = "Gateway Port",
        .description = "Gateway bind port",
        .category = .gateway,
        .display_group = .network_bind,
        .value_kind = .integer,
        .required = true,
        .requires_restart = true,
        .default_value_json = "8080",
        .side_effect_kind = .restart_required,
        .field_definition = .{
            .key = "gateway.port",
            .required = true,
            .requires_restart = true,
            .value_kind = .integer,
            .rules = &.{.port},
        },
    },
    .{
        .path = "gateway.require_pairing",
        .label = "Require Pairing",
        .description = "Whether gateway pairing is required",
        .category = .gateway,
        .display_group = .access_control,
        .value_kind = .boolean,
        .required = true,
        .risk_level = .high,
        .default_value_json = "true",
        .side_effect_kind = .notify_runtime,
        .field_definition = .{
            .key = "gateway.require_pairing",
            .required = true,
            .value_kind = .boolean,
        },
    },
    .{
        .path = "logging.level",
        .label = "Logging Level",
        .description = "Application log level",
        .category = .logging,
        .display_group = .file_logging,
        .value_kind = .enum_string,
        .required = true,
        .default_value_json = "\"info\"",
        .side_effect_kind = .reload_logging,
        .field_definition = .{
            .key = "logging.level",
            .required = true,
            .value_kind = .enum_string,
            .rules = &.{.{ .enum_string = &.{ "trace", "debug", "info", "warn", "error" } }},
        },
    },
    .{
        .path = "logging.file.enabled",
        .label = "File Logging Enabled",
        .description = "Whether file logging is enabled",
        .category = .logging,
        .display_group = .file_logging,
        .value_kind = .boolean,
        .required = false,
        .default_value_json = "false",
        .side_effect_kind = .reload_logging,
        .field_definition = .{
            .key = "logging.file.enabled",
            .required = false,
            .value_kind = .boolean,
        },
    },
    .{
        .path = "logging.file.path",
        .label = "File Logging Path",
        .description = "Target file path for file logging",
        .category = .logging,
        .display_group = .file_logging,
        .value_kind = .string,
        .required = false,
        .side_effect_kind = .reload_logging,
        .field_definition = .{
            .key = "logging.file.path",
            .required = false,
            .value_kind = .string,
            .rules = &.{.path_no_traversal},
        },
    },
    .{
        .path = "logging.file.max_bytes",
        .label = "File Logging Max Bytes",
        .description = "Maximum bytes per log file before rotation",
        .category = .logging,
        .display_group = .file_logging,
        .value_kind = .integer,
        .required = false,
        .default_value_json = "10485760",
        .side_effect_kind = .reload_logging,
        .field_definition = .{
            .key = "logging.file.max_bytes",
            .required = false,
            .value_kind = .integer,
        },
    },
    .{
        .path = "logging.file.max_backups",
        .label = "File Logging Max Backups",
        .description = "How many rotated log files to retain",
        .category = .logging,
        .display_group = .file_logging,
        .value_kind = .integer,
        .required = false,
        .default_value_json = "5",
        .side_effect_kind = .reload_logging,
        .field_definition = .{
            .key = "logging.file.max_backups",
            .required = false,
            .value_kind = .integer,
        },
    },
    .{
        .path = "providers.openai.api_key",
        .label = "OpenAI API Key",
        .description = "OpenAI provider credential",
        .category = .providers,
        .display_group = .provider_openai,
        .value_kind = .string,
        .required = false,
        .sensitive = true,
        .side_effect_kind = .refresh_providers,
        .allowed_in_sources = SECRET_ALLOWED_SOURCES[0..],
        .field_definition = .{
            .key = "providers.openai.api_key",
            .required = false,
            .sensitive = true,
            .value_kind = .string,
            .rules = &.{.non_empty_string},
        },
    },
    .{
        .path = "providers.openai.base_url",
        .label = "OpenAI Base URL",
        .description = "Base endpoint for the OpenAI-compatible provider",
        .category = .providers,
        .display_group = .provider_openai,
        .value_kind = .string,
        .required = false,
        .default_value_json = "\"https://api.openai.com/v1/chat/completions\"",
        .side_effect_kind = .refresh_providers,
        .field_definition = .{
            .key = "providers.openai.base_url",
            .required = false,
            .value_kind = .string,
            .rules = &.{.non_empty_string},
        },
    },
    .{
        .path = "providers.openai.model",
        .label = "OpenAI Default Model",
        .description = "Default model used for OpenAI-compatible requests",
        .category = .providers,
        .display_group = .provider_openai,
        .value_kind = .string,
        .required = false,
        .default_value_json = "\"gpt-4o-mini\"",
        .side_effect_kind = .refresh_providers,
        .field_definition = .{
            .key = "providers.openai.model",
            .required = false,
            .value_kind = .string,
            .rules = &.{.non_empty_string},
        },
    },
    .{
        .path = "providers.anthropic.api_key",
        .label = "Anthropic API Key",
        .description = "Anthropic provider credential",
        .category = .providers,
        .display_group = .provider_anthropic,
        .value_kind = .string,
        .required = false,
        .sensitive = true,
        .side_effect_kind = .refresh_providers,
        .allowed_in_sources = SECRET_ALLOWED_SOURCES[0..],
        .field_definition = .{
            .key = "providers.anthropic.api_key",
            .required = false,
            .sensitive = true,
            .value_kind = .string,
            .rules = &.{.non_empty_string},
        },
    },
    .{
        .path = "runtime.max_tool_rounds",
        .label = "Maximum Tool Rounds",
        .description = "Upper bound for provider→tool→provider loop rounds",
        .category = .runtime,
        .display_group = .runtime_limits,
        .value_kind = .integer,
        .required = false,
        .default_value_json = "4",
        .side_effect_kind = .notify_runtime,
        .field_definition = .{
            .key = "runtime.max_tool_rounds",
            .required = false,
            .value_kind = .integer,
        },
    },
    .{
        .path = "service.autostart",
        .label = "Service Autostart",
        .description = "Whether the service should start automatically with the host",
        .category = .service,
        .display_group = .service_lifecycle,
        .value_kind = .boolean,
        .required = false,
        .default_value_json = "false",
        .side_effect_kind = .restart_required,
        .field_definition = .{
            .key = "service.autostart",
            .required = false,
            .value_kind = .boolean,
        },
    },
};

fn buildFieldDefinitions() [FIELD_DEFINITIONS.len]FieldDefinition {
    var definitions: [FIELD_DEFINITIONS.len]FieldDefinition = undefined;
    for (FIELD_DEFINITIONS, 0..) |definition, index| {
        definitions[index] = definition.field_definition;
    }
    return definitions;
}

fn countDefaultEntries() usize {
    var count: usize = 0;
    for (FIELD_DEFINITIONS) |definition| {
        if (definition.default_value_json != null) count += 1;
    }
    return count;
}

const DEFAULT_ENTRY_COUNT = countDefaultEntries();

fn buildDefaultEntries() [DEFAULT_ENTRY_COUNT]framework.ConfigDefaultEntry {
    var entries: [DEFAULT_ENTRY_COUNT]framework.ConfigDefaultEntry = undefined;
    var index: usize = 0;
    for (FIELD_DEFINITIONS) |definition| {
        if (definition.default_value_json) |value_json| {
            entries[index] = .{
                .path = definition.path,
                .value_kind = definition.value_kind,
                .value_json = value_json,
            };
            index += 1;
        }
    }
    return entries;
}

const FIELD_VALIDATION_DEFINITIONS = buildFieldDefinitions();
const DEFAULT_ENTRIES = buildDefaultEntries();

const CONFIG_RULES = [_]ConfigRule{
    .{ .require_non_empty_string_when_bool = .{
        .flag_path = "logging.file.enabled",
        .expected = true,
        .required_path = "logging.file.path",
        .message = "logging.file.path is required when file logging is enabled",
    } },
    .{ .risk_confirmation_for_string_value = .{
        .path = "gateway.host",
        .expected = "0.0.0.0",
        .message = "binding to 0.0.0.0 requires explicit confirmation",
    } },
    .{ .risk_confirmation_for_boolean_value = .{
        .path = "gateway.require_pairing",
        .expected = false,
        .message = "disabling pairing protection requires explicit confirmation",
    } },
};

pub const ConfigFieldRegistry = struct {
    pub fn all() []const ConfigFieldDefinition {
        return FIELD_DEFINITIONS[0..];
    }

    pub fn fieldDefinitions() []const FieldDefinition {
        return FIELD_VALIDATION_DEFINITIONS[0..];
    }

    pub fn configRules() []const ConfigRule {
        return CONFIG_RULES[0..];
    }

    pub fn find(path: []const u8) ?ConfigFieldDefinition {
        for (FIELD_DEFINITIONS) |definition| {
            if (std.mem.eql(u8, definition.path, path)) {
                return definition;
            }
        }
        return null;
    }

    pub fn defaultEntries() []const framework.ConfigDefaultEntry {
        return DEFAULT_ENTRIES[0..];
    }
};

test "config field registry exposes stable metadata" {
    const definition = ConfigFieldRegistry.find("gateway.port").?;
    try std.testing.expectEqualStrings("Gateway Port", definition.label);
    try std.testing.expect(definition.requires_restart);
    try std.testing.expectEqual(ConfigCategory.gateway, definition.category);
    try std.testing.expectEqual(DisplayGroup.network_bind, definition.display_group);
    try std.testing.expectEqualStrings("8080", definition.default_value_json.?);
    try std.testing.expectEqual(framework.ConfigSideEffectKind.restart_required, definition.side_effect_kind);
    try std.testing.expectEqual(@as(usize, 14), ConfigFieldRegistry.all().len);
    try std.testing.expectEqual(@as(usize, 3), ConfigFieldRegistry.configRules().len);
    try std.testing.expect(ConfigFieldRegistry.defaultEntries().len >= 10);
}
