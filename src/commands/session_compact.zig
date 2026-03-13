const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "session.compact",
        .method = "session.compact",
        .description = "Compact session memory and store summary event",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "session_id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "keep_last", .required = false, .value_kind = .integer, .rules = &.{.{ .int_range = .{ .min = 1, .max = 32 } }} },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const session_id = ctx.param("session_id").?.value.string;
    const keep_last: usize = if (ctx.param("keep_last")) |field| @intCast(field.value.integer) else 2;

    var summary = try services.memory_runtime.compactSession(ctx.allocator, session_id, keep_last);
    defer summary.deinit(ctx.allocator);
    try services.session_store.appendEvent(session_id, "session.summary", summary.summary_text);
    var snapshot = try services.session_store.snapshotMeta(ctx.allocator, session_id);
    defer snapshot.deinit(ctx.allocator);

    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"sessionId\":\"{s}\",\"keepLast\":{d},\"memoryEntryCount\":{d},\"eventCount\":{d},\"summaryText\":\"{s}\"}}",
        .{ session_id, keep_last, services.memory_runtime.countBySession(session_id), snapshot.event_count, summary.summary_text },
    );
}
