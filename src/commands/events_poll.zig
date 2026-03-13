const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "events.poll",
        .method = "events.poll",
        .description = "Poll runtime events from a subscription cursor",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "subscription_id", .required = true, .value_kind = .integer },
            .{ .key = "limit", .required = false, .value_kind = .integer, .rules = &.{.{ .int_range = .{ .min = 1, .max = 100 } }} },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const subscription_id: u64 = @intCast(ctx.param("subscription_id").?.value.integer);
    const limit: usize = if (ctx.param("limit")) |field| @intCast(field.value.integer) else 32;

    var batch = try services.framework_context.event_bus.pollSubscription(ctx.allocator, subscription_id, limit);
    defer batch.deinit(ctx.allocator);

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.writeByte('{');
    try writer.print("\"subscriptionId\":{d},\"lastSeq\":{d},\"eventCount\":{d},\"hasMore\":{s},\"events\":[", .{ subscription_id, batch.last_seq, batch.events.len, if (batch.has_more) "true" else "false" });
    for (batch.events, 0..) |event, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("{{\"seq\":{d},\"topic\":\"{s}\",\"payload\":{s}}}", .{ event.seq, event.topic, event.payload_json });
    }
    try writer.writeByte(']');
    try writer.writeByte('}');
    return ctx.allocator.dupe(u8, buf.items);
}
