const std = @import("std");
const framework = @import("framework");
const field_registry = @import("field_registry.zig");

pub const ConfigDefaultEntry = framework.ConfigDefaultEntry;
pub const ConfigDefaults = framework.ConfigDefaults;
pub const ConfigLoader = framework.ConfigLoader;
pub const ConfigStore = framework.ConfigStore;
pub const ValidationValue = framework.ValidationValue;
pub const ValueKind = framework.ValueKind;

pub fn defaults() ConfigDefaults {
    return .{ .entries = field_registry.ConfigFieldRegistry.defaultEntries() };
}

pub fn loader(allocator: std.mem.Allocator, store: ConfigStore) ConfigLoader {
    return ConfigLoader.init(allocator, store, defaults());
}

pub fn bootstrapDefaults(allocator: std.mem.Allocator, store: ConfigStore) anyerror!framework.ConfigWriteStats {
    return defaults().applyToStore(allocator, store);
}

pub fn defaultValueJson(allocator: std.mem.Allocator, path: []const u8) anyerror!?[]u8 {
    return defaults().valueJson(allocator, path);
}

pub fn parseValue(allocator: std.mem.Allocator, kind: ValueKind, raw: []const u8) anyerror!ValidationValue {
    return framework.ConfigValueParser.parseRawValue(allocator, kind, raw);
}

pub fn loadSnapshotJson(allocator: std.mem.Allocator, json_text: []const u8) anyerror![]framework.ValidationField {
    return framework.ConfigLoader.loadSnapshotJson(allocator, json_text, field_registry.ConfigFieldRegistry.fieldDefinitions());
}

pub fn loadSnapshotFile(allocator: std.mem.Allocator, file_path: []const u8) anyerror![]framework.ValidationField {
    return framework.ConfigLoader.loadSnapshotFile(allocator, file_path, field_registry.ConfigFieldRegistry.fieldDefinitions());
}

pub fn loadEnvOverrides(allocator: std.mem.Allocator, prefix: []const u8) anyerror![]framework.ValidationField {
    return framework.ConfigLoader.loadEnvOverrides(allocator, field_registry.ConfigFieldRegistry.fieldDefinitions(), prefix);
}

pub fn fieldDefinitions() []const framework.FieldDefinition {
    return field_registry.ConfigFieldRegistry.fieldDefinitions();
}

pub fn configRules() []const framework.ConfigRule {
    return field_registry.ConfigFieldRegistry.configRules();
}

test "config runtime exposes stable bootstrap defaults" {
    const gateway_host = try defaultValueJson(std.testing.allocator, "gateway.host");
    defer if (gateway_host) |owned| std.testing.allocator.free(owned);
    try std.testing.expect(gateway_host != null);
    try std.testing.expectEqualStrings("\"127.0.0.1\"", gateway_host.?);

    var store = framework.MemoryConfigStore.init(std.testing.allocator);
    defer store.deinit();
    const stats = try bootstrapDefaults(std.testing.allocator, store.asConfigStore());
    try std.testing.expectEqual(field_registry.ConfigFieldRegistry.defaultEntries().len, stats.applied_count);
    try std.testing.expectEqual(@as(i64, 8080), store.get("gateway.port").?.integer);
}

test "config runtime loads snapshot json with nested objects" {
    const fields = try loadSnapshotJson(std.testing.allocator, "{\"gateway\":{\"host\":\"0.0.0.0\",\"port\":9091}}");
    defer {
        for (fields) |field| field.deinit(std.testing.allocator);
        std.testing.allocator.free(fields);
    }
    try std.testing.expect(fields.len >= 2);
}
