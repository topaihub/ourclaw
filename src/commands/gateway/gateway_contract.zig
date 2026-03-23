const std = @import("std");
const gateway_host = @import("../../runtime/gateway_host.zig");

pub fn buildGatewaySnapshotJson(allocator: std.mem.Allocator, status: gateway_host.GatewayStatus, extra_fields_json: ?[]const u8) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeByte('{');
    try appendBoolField(writer, "running", status.running, true);
    try appendBoolField(writer, "listenerReady", status.listener_ready, false);
    try appendStringField(writer, "bindHost", status.bind_host, false);
    try appendUnsignedField(writer, "bindPort", status.bind_port, false);
    try appendUnsignedField(writer, "requestCount", status.request_count, false);
    try appendUnsignedField(writer, "activeConnections", status.active_connections, false);
    try appendUnsignedField(writer, "streamSubscriptions", status.stream_subscriptions, false);
    try appendBoolField(writer, "handlerAttached", status.handler_attached, false);
    try appendUnsignedField(writer, "reloadCount", status.reload_count, false);
    try appendOptionalSigned64Field(writer, "lastStartedMs", status.last_started_ms, false);
    try appendOptionalSigned64Field(writer, "lastReloadedMs", status.last_reloaded_ms, false);
    try appendOptionalSigned64Field(writer, "lastStoppedMs", status.last_stopped_ms, false);
    try appendOptionalStringField(writer, "lastErrorCode", status.last_error, false);
    try appendStringField(writer, "healthState", healthState(status), false);
    try appendStringField(writer, "healthMessage", healthMessage(status), false);
    if (extra_fields_json) |extra| try writer.writeAll(extra);
    try writer.writeByte('}');
    return allocator.dupe(u8, buf.items);
}

fn healthState(status: gateway_host.GatewayStatus) []const u8 {
    if (status.last_error != null) return "degraded";
    if (!status.running) return "stopped";
    if (!status.listener_ready) return "starting";
    if (!status.handler_attached) return "degraded";
    return "healthy";
}

fn healthMessage(status: gateway_host.GatewayStatus) []const u8 {
    if (status.last_error) |err| return err;
    if (!status.running) return "gateway host is stopped";
    if (!status.listener_ready) return "gateway listener is starting";
    if (!status.handler_attached) return "gateway handler is not attached";
    return "gateway host is healthy";
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

fn appendBoolField(writer: anytype, key: []const u8, value: bool, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.writeAll(if (value) "true" else "false");
}

fn appendUnsignedField(writer: anytype, key: []const u8, value: usize, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.print("{d}", .{value});
}

fn appendOptionalSigned64Field(writer: anytype, key: []const u8, value: ?i64, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    if (value) |number| {
        try writer.print("{d}", .{number});
    } else {
        try writer.writeAll("null");
    }
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
