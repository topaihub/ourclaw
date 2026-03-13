const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "events.subscribe",
        .method = "events.subscribe",
        .description = "Create runtime event subscription",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "topic_prefix", .required = false, .value_kind = .string },
            .{ .key = "after_seq", .required = false, .value_kind = .integer },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const prefix = if (ctx.param("topic_prefix")) |field| field.value.string else null;
    const after_seq: u64 = if (ctx.param("after_seq")) |field| @intCast(field.value.integer) else services.framework_context.event_bus.latestSeq();

    const subscription_id = if (prefix) |topic_prefix|
        try services.framework_context.event_bus.subscribe(&.{topic_prefix}, after_seq)
    else
        try services.framework_context.event_bus.subscribe(&.{}, after_seq);

    return std.fmt.allocPrint(ctx.allocator, "{{\"subscriptionId\":{d},\"afterSeq\":{d},\"subscriptionCount\":{d}}}", .{ subscription_id, after_seq, services.framework_context.event_bus.subscriptionCount() });
}
