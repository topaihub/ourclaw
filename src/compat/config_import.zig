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
    return .{
        .source_kind = source_kind,
        .migration_preview = try config_migration.previewMigration(allocator, source_json),
    };
}

pub fn applyImport(
    allocator: std.mem.Allocator,
    source_kind: SourceKind,
    source_json: []const u8,
    pipeline: *const framework.ConfigWritePipeline,
    confirm_risk: bool,
) anyerror!config_migration.ApplyResult {
    _ = source_kind;
    return config_migration.applyMigration(allocator, source_json, pipeline, confirm_risk);
}

test "compat import parses supported source kinds" {
    try std.testing.expectEqual(SourceKind.nullclaw, try parseSourceKind("nullclaw"));
    try std.testing.expectError(error.UnsupportedCompatSourceKind, parseSourceKind("legacy"));
}
