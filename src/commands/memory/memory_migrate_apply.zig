const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "memory.migrate_apply",
        .method = "memory.migrate_apply",
        .description = "Apply memory snapshot migration",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{.{ .key = "snapshot_json", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} }},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const snapshot_json = ctx.param("snapshot_json").?.value.string;
    const migrated = try services.memory_runtime.migrateSnapshotJson(ctx.allocator, snapshot_json);
    const preview = services.memory_runtime.previewMigration(snapshot_json);
    defer ctx.allocator.free(migrated);
    const migrated_json = try jsonString(ctx.allocator, migrated);
    defer ctx.allocator.free(migrated_json);

    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"fromVersion\":{d},\"toVersion\":{d},\"changed\":{s},\"snapshot\":{s},\"snapshotJson\":{s},\"readyForImport\":true}}",
        .{ preview.from_version, preview.to_version, if (preview.changed) "true" else "false", migrated, migrated_json },
    );
}

fn jsonString(allocator: std.mem.Allocator, value: []const u8) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);
    try writer.writeByte('"');
    for (value) |ch| {
        switch (ch) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(ch),
        }
    }
    try writer.writeByte('"');
    return allocator.dupe(u8, buf.items);
}
