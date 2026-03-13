const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "observer.recent",
        .method = "observer.recent",
        .description = "Return recent observer events",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{.{ .key = "limit", .required = false, .value_kind = .integer, .rules = &.{.{ .int_range = .{ .min = 1, .max = 100 } }} }},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const limit: usize = if (ctx.param("limit")) |field| @intCast(field.value.integer) else 20;
    const events = try services.framework_context.memory_observer.snapshot(ctx.allocator);
    defer {
        for (events) |*event| event.deinit(ctx.allocator);
        ctx.allocator.free(events);
    }

    const start = if (events.len > limit) events.len - limit else 0;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.print("{{\"totalCount\":{d},\"returnedCount\":{d},\"events\":[", .{ events.len, events.len - start });
    for (events[start..], 0..) |event, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("{{\"topic\":\"{s}\",\"tsUnixMs\":{d},\"payload\":{s}}}", .{ event.topic, event.ts_unix_ms, event.payload_json });
    }
    try writer.writeAll("]}");
    return ctx.allocator.dupe(u8, buf.items);
}
