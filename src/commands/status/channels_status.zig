const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "channels.status",
        .method = "channels.status",
        .description = "Get channel registry and routing snapshot",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *const @import("../../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const cli = app.channel_registry.cliSnapshot();
    const bridge = app.channel_registry.bridgeSnapshot();
    const http = app.channel_registry.httpSnapshot();

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);

    try writer.writeByte('{');
    try appendUnsignedField(writer, "count", app.channel_registry.count(), true);
    try writer.writeAll(",\"cli\":{");
    try appendUnsignedField(writer, "requestCount", cli.request_count, true);
    try appendUnsignedField(writer, "liveStreamCount", cli.live_stream_count, false);
    try appendOptionalStringField(writer, "lastMethod", cli.last_method, false);
    try appendStringField(writer, "lastRouteGroup", cli.last_route_group, false);
    try appendStringField(writer, "healthState", cli.health_state, false);
    try appendOptionalStringField(writer, "lastSessionId", cli.last_session_id, false);
    try writer.writeByte('}');
    try writer.writeAll(",\"bridge\":{");
    try appendUnsignedField(writer, "requestCount", bridge.request_count, true);
    try appendUnsignedField(writer, "streamCount", bridge.stream_count, false);
    try appendOptionalStringField(writer, "lastTarget", bridge.last_target, false);
    try appendStringField(writer, "lastRouteGroup", bridge.last_route_group, false);
    try appendStringField(writer, "healthState", bridge.health_state, false);
    try appendOptionalStringField(writer, "lastSessionId", bridge.last_session_id, false);
    try writer.writeByte('}');
    try writer.writeAll(",\"http\":{");
    try appendUnsignedField(writer, "requestCount", http.request_count, true);
    try appendUnsignedField(writer, "streamCount", http.stream_count, false);
    try appendOptionalStringField(writer, "lastTarget", http.last_target, false);
    try appendStringField(writer, "lastRouteGroup", http.last_route_group, false);
    try appendStringField(writer, "healthState", http.health_state, false);
    try appendOptionalStringField(writer, "lastSessionId", http.last_session_id, false);
    try writer.writeByte('}');
    try writer.writeByte('}');
    return ctx.allocator.dupe(u8, buf.items);
}

fn appendStringField(writer: anytype, key: []const u8, value: []const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writeJsonString(writer, value);
}

fn appendOptionalStringField(writer: anytype, key: []const u8, value: ?[]const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    if (value) |text| {
        try writeJsonString(writer, text);
    } else {
        try writer.writeAll("null");
    }
}

fn appendUnsignedField(writer: anytype, key: []const u8, value: usize, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.print("{d}", .{value});
}

fn writeJsonString(writer: anytype, value: []const u8) anyerror!void {
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
}
