const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "memory.snapshot_import",
        .method = "memory.snapshot_import",
        .description = "Import memory snapshot JSON",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{.{ .key = "snapshot_json", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} }},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const snapshot_json = ctx.param("snapshot_json").?.value.string;
    const result = try services.memory_runtime.importSnapshotJson(ctx.allocator, snapshot_json);
    return std.fmt.allocPrint(ctx.allocator, "{{\"importedCount\":{d},\"rejectedCount\":{d},\"sourceVersion\":{d},\"resultingCount\":{d}}}", .{ result.imported_count, result.rejected_count, result.source_version, result.resulting_count });
}
