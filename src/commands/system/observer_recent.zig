const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "observer.recent",
        .method = "observer.recent",
        .description = "Return recent observer events",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "limit", .required = false, .value_kind = .integer, .rules = &.{.{ .int_range = .{ .min = 1, .max = 100 } }} },
            .{ .key = "execution_id", .required = false, .value_kind = .string },
            .{ .key = "session_id", .required = false, .value_kind = .string },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const limit: usize = if (ctx.param("limit")) |field| @intCast(field.value.integer) else 20;
    const execution_filter = if (ctx.param("execution_id")) |field| field.value.string else null;
    const session_filter = if (ctx.param("session_id")) |field| field.value.string else null;
    const events = try services.framework_context.memory_observer.snapshot(ctx.allocator);
    defer {
        for (events) |*event| event.deinit(ctx.allocator);
        ctx.allocator.free(events);
    }

    const start = if (events.len > limit) events.len - limit else 0;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.print("{{\"totalCount\":{d},\"events\":[", .{events.len});
    var returned_count: usize = 0;
    for (events[start..]) |event| {
        if (!matchesCorrelation(event.payload_json, execution_filter, session_filter)) continue;
        if (returned_count > 0) try writer.writeByte(',');
        try writer.print("{{\"topic\":\"{s}\",\"tsUnixMs\":{d},\"executionId\":", .{ event.topic, event.ts_unix_ms });
        try appendOptionalString(writer, extractJsonStringField(event.payload_json, "executionId"));
        try writer.writeAll(",\"sessionId\":");
        try appendOptionalString(writer, extractJsonStringField(event.payload_json, "sessionId"));
        try writer.print(",\"payload\":{s}}}", .{event.payload_json});
        returned_count += 1;
    }
    try writer.print("],\"returnedCount\":{d}}}", .{returned_count});
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
