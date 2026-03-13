const std = @import("std");
const framework = @import("framework");
const config_migration = @import("../config/migration.zig");

pub const SourceKind = enum {
    generic,
    nullclaw,
    openclaw,
};

pub const ImportPreview = struct {
    source_kind: SourceKind,
    migration_preview: config_migration.MigrationPreview,
};

pub fn parseSourceKind(text: []const u8) anyerror!SourceKind {
    if (std.mem.eql(u8, text, "generic")) return .generic;
    if (std.mem.eql(u8, text, "nullclaw")) return .nullclaw;
    if (std.mem.eql(u8, text, "openclaw")) return .openclaw;
    return error.UnsupportedCompatSourceKind;
}

pub fn previewImport(allocator: std.mem.Allocator, source_kind: SourceKind, source_json: []const u8) anyerror!ImportPreview {
    const normalized = try normalizeSourceJson(allocator, source_kind, source_json);
    defer allocator.free(normalized);
    return .{
        .source_kind = source_kind,
        .migration_preview = try config_migration.previewMigration(allocator, normalized),
    };
}

pub fn applyImport(
    allocator: std.mem.Allocator,
    source_kind: SourceKind,
    source_json: []const u8,
    pipeline: *const framework.ConfigWritePipeline,
    confirm_risk: bool,
) anyerror!config_migration.ApplyResult {
    const normalized = try normalizeSourceJson(allocator, source_kind, source_json);
    defer allocator.free(normalized);
    return config_migration.applyMigration(allocator, normalized, pipeline, confirm_risk);
}

fn normalizeSourceJson(allocator: std.mem.Allocator, source_kind: SourceKind, source_json: []const u8) anyerror![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, source_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return allocator.dupe(u8, source_json);

    const object = parsed.value.object;
    if (object.get("version") != null or object.get("config") != null) {
        return allocator.dupe(u8, source_json);
    }

    return switch (source_kind) {
        .generic => allocator.dupe(u8, source_json),
        .nullclaw => std.fmt.allocPrint(allocator, "{{\"version\":1,\"config\":{s}}}", .{source_json}),
        .openclaw => std.fmt.allocPrint(allocator, "{{\"version\":2,\"config\":{s}}}", .{source_json}),
    };
}

test "compat import parses supported source kinds" {
    try std.testing.expectEqual(SourceKind.nullclaw, try parseSourceKind("nullclaw"));
    try std.testing.expectError(error.UnsupportedCompatSourceKind, parseSourceKind("legacy"));
}

test "compat import normalizes source payload by source kind" {
    const nullclaw_json = try normalizeSourceJson(std.testing.allocator, .nullclaw, "{\"server\":{\"port\":8081}}");
    defer std.testing.allocator.free(nullclaw_json);
    try std.testing.expect(std.mem.indexOf(u8, nullclaw_json, "\"version\":1") != null);

    const openclaw_json = try normalizeSourceJson(std.testing.allocator, .openclaw, "{\"gateway\":{\"port\":9090}}");
    defer std.testing.allocator.free(openclaw_json);
    try std.testing.expect(std.mem.indexOf(u8, openclaw_json, "\"version\":2") != null);
}
