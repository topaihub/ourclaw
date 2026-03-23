const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

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
            .{ .key = "execution_id", .required = false, .value_kind = .string },
            .{ .key = "session_id", .required = false, .value_kind = .string },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const subscription_id: u64 = @intCast(ctx.param("subscription_id").?.value.integer);
    const limit: usize = if (ctx.param("limit")) |field| @intCast(field.value.integer) else 32;
    const execution_filter = if (ctx.param("execution_id")) |field| field.value.string else null;
    const session_filter = if (ctx.param("session_id")) |field| field.value.string else null;

    var batch = try services.framework_context.event_bus.pollSubscription(ctx.allocator, subscription_id, limit);
    defer batch.deinit(ctx.allocator);

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.writeByte('{');
    try writer.print("\"subscriptionId\":{d},\"lastSeq\":{d},\"hasMore\":{s},\"events\":[", .{ subscription_id, batch.last_seq, if (batch.has_more) "true" else "false" });
    var matched_count: usize = 0;
    for (batch.events) |event| {
        if (!matchesCorrelation(event.payload_json, execution_filter, session_filter)) continue;
        if (matched_count > 0) try writer.writeByte(',');
        try writer.print("{{\"seq\":{d},\"topic\":\"{s}\",\"executionId\":", .{ event.seq, event.topic });
        try appendOptionalString(writer, extractJsonStringField(event.payload_json, "executionId"));
        try writer.writeAll(",\"sessionId\":");
        try appendOptionalString(writer, extractJsonStringField(event.payload_json, "sessionId"));
        try writer.print(",\"subscriptionId\":{d},\"payload\":{s}}}", .{ subscription_id, event.payload_json });
        matched_count += 1;
    }
    try writer.print("],\"eventCount\":{d}}}", .{matched_count});
    return ctx.allocator.dupe(u8, buf.items);
}

fn matchesCorrelation(payload_json: []const u8, execution_id: ?[]const u8, session_id: ?[]const u8) bool {
    if (execution_id) |expected| {
        const actual = extractJsonStringField(payload_json, "executionId") orelse return false;
        if (!std.mem.eql(u8, actual, expected)) return false;
    }
    if (session_id) |expected| {
        const actual = extractJsonStringField(payload_json, "sessionId") orelse return false;
        if (!std.mem.eql(u8, actual, expected)) return false;
    }
    return true;
}

fn extractJsonStringField(payload_json: []const u8, key: []const u8) ?[]const u8 {
    var marker_buf: [128]u8 = undefined;
    const marker = std.fmt.bufPrint(&marker_buf, "\"{s}\":\"", .{key}) catch return null;
    const start = std.mem.indexOf(u8, payload_json, marker) orelse return null;
    const value_start = start + marker.len;
    const rest = payload_json[value_start..];
    const end = std.mem.indexOfScalar(u8, rest, '"') orelse return null;
    return rest[0..end];
}

fn appendOptionalString(writer: anytype, value: ?[]const u8) anyerror!void {
    if (value) |actual| {
        try writer.print("\"{s}\"", .{actual});
    } else {
        try writer.writeAll("null");
    }
}
