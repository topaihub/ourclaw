const std = @import("std");
const framework = @import("framework");
const field_registry = @import("field_registry.zig");

pub const CURRENT_CONFIG_VERSION: u32 = 2;

const ValidationField = framework.ValidationField;
const ValidationValue = framework.ValidationValue;

const Alias = struct {
    legacy_path: []const u8,
    current_path: []const u8,
};

const ALIASES = [_]Alias{
    .{ .legacy_path = "server.host", .current_path = "gateway.host" },
    .{ .legacy_path = "server.port", .current_path = "gateway.port" },
    .{ .legacy_path = "security.require_pairing", .current_path = "gateway.require_pairing" },
    .{ .legacy_path = "log.level", .current_path = "logging.level" },
    .{ .legacy_path = "log.file.enabled", .current_path = "logging.file.enabled" },
    .{ .legacy_path = "log.file.path", .current_path = "logging.file.path" },
    .{ .legacy_path = "openai.api_key", .current_path = "providers.openai.api_key" },
    .{ .legacy_path = "openai.base_url", .current_path = "providers.openai.base_url" },
    .{ .legacy_path = "openai.model", .current_path = "providers.openai.model" },
    .{ .legacy_path = "anthropic.api_key", .current_path = "providers.anthropic.api_key" },
    .{ .legacy_path = "service.auto_start", .current_path = "service.autostart" },
};

pub const MigrationPreview = struct {
    from_version: u32,
    to_version: u32,
    changed: bool,
    mapped_count: usize,
    alias_rewrite_count: usize,
    unknown_count: usize,
};

pub const PreparedMigration = struct {
    preview: MigrationPreview,
    updates: []ValidationField,
    unknown_paths: [][]u8,

    pub fn deinit(self: *PreparedMigration, allocator: std.mem.Allocator) void {
        for (self.updates) |field| field.deinit(allocator);
        allocator.free(self.updates);
        for (self.unknown_paths) |path| allocator.free(path);
        allocator.free(self.unknown_paths);
    }
};

pub const ApplyResult = struct {
    preview: MigrationPreview,
    attempt: framework.ConfigWriteAttempt,

    pub fn deinit(self: *ApplyResult, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.attempt.deinit();
    }
};

pub fn previewMigration(allocator: std.mem.Allocator, source_json: []const u8) anyerror!MigrationPreview {
    var prepared = try prepareMigration(allocator, source_json);
    defer prepared.deinit(allocator);
    return prepared.preview;
}

pub fn prepareMigration(allocator: std.mem.Allocator, source_json: []const u8) anyerror!PreparedMigration {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, source_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidConfigMigrationSource;

    const root = parsed.value.object;
    const from_version = parseVersion(root);
    const payload = if (root.get("config")) |value| value else parsed.value;

    var flat_fields: std.ArrayListUnmanaged(ValidationField) = .empty;
    defer freeFieldList(allocator, &flat_fields);
    try collectFields(allocator, &flat_fields, "", payload, true);

    var updates: std.ArrayListUnmanaged(ValidationField) = .empty;
    errdefer freeFieldList(allocator, &updates);
    var unknown_paths: std.ArrayListUnmanaged([]u8) = .empty;
    errdefer freeStringList(allocator, &unknown_paths);

    var alias_rewrite_count: usize = 0;

    for (flat_fields.items) |field| {
        if (std.mem.eql(u8, field.key, "version")) continue;

        const normalized = normalizePath(field.key);
        if (!std.mem.eql(u8, normalized, field.key)) alias_rewrite_count += 1;

        if (field_registry.ConfigFieldRegistry.find(normalized)) |_| {
            try upsertField(allocator, &updates, normalized, field.value);
        } else {
            try unknown_paths.append(allocator, try allocator.dupe(u8, field.key));
        }
    }

    const changed = from_version != CURRENT_CONFIG_VERSION or alias_rewrite_count > 0;
    const mapped_count = updates.items.len;
    const unknown_count = unknown_paths.items.len;
    const owned_updates = try allocator.dupe(ValidationField, updates.items);
    const owned_unknown_paths = try allocator.dupe([]u8, unknown_paths.items);
    updates.deinit(allocator);
    unknown_paths.deinit(allocator);

    return .{
        .preview = .{
            .from_version = from_version,
            .to_version = CURRENT_CONFIG_VERSION,
            .changed = changed,
            .mapped_count = mapped_count,
            .alias_rewrite_count = alias_rewrite_count,
            .unknown_count = unknown_count,
        },
        .updates = owned_updates,
        .unknown_paths = owned_unknown_paths,
    };
}

pub fn applyMigration(
    allocator: std.mem.Allocator,
    source_json: []const u8,
    pipeline: *const framework.ConfigWritePipeline,
    confirm_risk: bool,
) anyerror!ApplyResult {
    var prepared = try prepareMigration(allocator, source_json);
    defer prepared.deinit(allocator);
    const attempt = try pipeline.applyWrite(prepared.updates, confirm_risk);
    return .{ .preview = prepared.preview, .attempt = attempt };
}

fn parseVersion(root: std.json.ObjectMap) u32 {
    const version_value = root.get("version") orelse return 1;
    return switch (version_value) {
        .integer => |number| if (number >= 0) @as(u32, @intCast(number)) else 1,
        else => 1,
    };
}

fn collectFields(
    allocator: std.mem.Allocator,
    list: *std.ArrayListUnmanaged(ValidationField),
    prefix: []const u8,
    value: std.json.Value,
    root_level: bool,
) anyerror!void {
    switch (value) {
        .object => |object| {
            var iter = object.iterator();
            while (iter.next()) |entry| {
                if (root_level and std.mem.eql(u8, entry.key_ptr.*, "version")) continue;
                const next_path = if (prefix.len == 0)
                    try allocator.dupe(u8, entry.key_ptr.*)
                else
                    try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, entry.key_ptr.* });
                defer allocator.free(next_path);
                try collectFields(allocator, list, next_path, entry.value_ptr.*, false);
            }
        },
        else => {
            try list.append(allocator, .{
                .key = try allocator.dupe(u8, prefix),
                .value = try jsonValueToValidationValue(allocator, value),
            });
        },
    }
}

fn jsonValueToValidationValue(allocator: std.mem.Allocator, value: std.json.Value) anyerror!ValidationValue {
    return switch (value) {
        .null => .null,
        .bool => |flag| .{ .boolean = flag },
        .integer => |number| .{ .integer = number },
        .float => |number| .{ .float = number },
        .string => |text| .{ .string = try allocator.dupe(u8, text) },
        else => error.UnsupportedConfigMigrationValue,
    };
}

fn normalizePath(path: []const u8) []const u8 {
    for (ALIASES) |alias| {
        if (std.mem.eql(u8, alias.legacy_path, path)) return alias.current_path;
    }
    return path;
}

fn upsertField(
    allocator: std.mem.Allocator,
    list: *std.ArrayListUnmanaged(ValidationField),
    path: []const u8,
    value: ValidationValue,
) anyerror!void {
    for (list.items, 0..) |*existing, index| {
        if (std.mem.eql(u8, existing.key, path)) {
            _ = index;
            existing.value.deinit(allocator);
            existing.value = try value.clone(allocator);
            return;
        }
    }

    try list.append(allocator, .{
        .key = try allocator.dupe(u8, path),
        .value = try value.clone(allocator),
    });
}

fn freeFieldList(allocator: std.mem.Allocator, list: *std.ArrayListUnmanaged(ValidationField)) void {
    for (list.items) |field| field.deinit(allocator);
    list.deinit(allocator);
}

fn freeStringList(allocator: std.mem.Allocator, list: *std.ArrayListUnmanaged([]u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit(allocator);
}

test "config migration preview maps legacy aliases" {
    const preview = try previewMigration(std.testing.allocator, "{\"version\":1,\"config\":{\"server\":{\"host\":\"0.0.0.0\",\"port\":8081},\"openai\":{\"api_key\":\"demo\"}}}");
    try std.testing.expect(preview.changed);
    try std.testing.expectEqual(@as(u32, 1), preview.from_version);
    try std.testing.expectEqual(@as(u32, 2), preview.to_version);
    try std.testing.expectEqual(@as(usize, 3), preview.mapped_count);
    try std.testing.expectEqual(@as(usize, 3), preview.alias_rewrite_count);
}

test "config migration prepare tracks unknown fields" {
    var prepared = try prepareMigration(std.testing.allocator, "{\"version\":2,\"mystery\":123,\"gateway\":{\"port\":9090}}");
    defer prepared.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), prepared.updates.len);
    try std.testing.expectEqual(@as(usize, 1), prepared.unknown_paths.len);
    try std.testing.expectEqualStrings("mystery", prepared.unknown_paths[0]);
    try std.testing.expectEqualStrings("gateway.port", prepared.updates[0].key);
}
