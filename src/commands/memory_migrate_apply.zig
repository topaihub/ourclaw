const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

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

    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"fromVersion\":{d},\"toVersion\":{d},\"changed\":{s},\"snapshot\":{s}}}",
        .{ preview.from_version, preview.to_version, if (preview.changed) "true" else "false", migrated },
    );
}
