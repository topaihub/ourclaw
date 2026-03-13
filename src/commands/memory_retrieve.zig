const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "memory.retrieve",
        .method = "memory.retrieve",
        .description = "Retrieve matching memory hits",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "session_id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "query", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "limit", .required = false, .value_kind = .integer, .rules = &.{.{ .int_range = .{ .min = 1, .max = 32 } }} },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const session_id = ctx.param("session_id").?.value.string;
    const query = ctx.param("query").?.value.string;
    const limit: usize = if (ctx.param("limit")) |field| @intCast(field.value.integer) else 5;
    const hits = try services.memory_runtime.retrieve(ctx.allocator, session_id, query, limit);
    defer {
        for (hits) |*hit| hit.deinit(ctx.allocator);
        ctx.allocator.free(hits);
    }

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.writeByte('[');
    for (hits, 0..) |hit, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("{{\"kind\":\"{s}\",\"score\":{d},\"content\":{s}}}", .{ hit.kind, hit.score, hit.content_json });
    }
    try writer.writeByte(']');
    return ctx.allocator.dupe(u8, buf.items);
}
