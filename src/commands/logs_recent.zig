const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "logs.recent",
        .method = "logs.recent",
        .description = "Read recent logs from memory sink",
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "limit", .required = false, .value_kind = .integer, .rules = &.{.{ .int_range = .{ .min = 1, .max = 100 } }} },
            .{ .key = "level", .required = false, .value_kind = .string, .rules = &.{.{ .enum_string = &.{ "trace", "debug", "info", "warn", "error", "fatal" } }} },
            .{ .key = "subsystem", .required = false, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "trace_id", .required = false, .value_kind = .string, .rules = &.{.non_empty_string} },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const limit: usize = if (ctx.param("limit")) |field| @intCast(field.value.integer) else 10;
    const level_filter = if (ctx.param("level")) |field| field.value.string else null;
    const subsystem_filter = if (ctx.param("subsystem")) |field| field.value.string else null;
    const trace_filter = if (ctx.param("trace_id")) |field| field.value.string else null;
    const sink = services.framework_context.memory_sink;
    const count = sink.count();

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.writeByte('{');
    try appendUnsignedField(writer, "limit", limit, true);
    try writer.writeAll(",\"filters\":{");
    try appendOptionalStringField(writer, "level", level_filter, true);
    try appendOptionalStringField(writer, "subsystem", subsystem_filter, false);
    try appendOptionalStringField(writer, "traceId", trace_filter, false);
    try writer.writeByte('}');
    try writer.writeAll(",\"items\":[");

    var matches: usize = 0;
    var index = count;
    while (index > 0 and matches < limit) {
        index -= 1;
        const record = sink.recordAt(index).?;
        if (!matchesFilters(record, level_filter, subsystem_filter, trace_filter)) {
            continue;
        }
        if (matches > 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writer.print("\"tsUnixMs\":{d}", .{record.ts_unix_ms});
        try appendStringField(writer, "level", record.level.asText(), false);
        try appendStringField(writer, "subsystem", record.subsystem, false);
        try appendStringField(writer, "message", record.message, false);
        try appendOptionalStringField(writer, "traceId", record.trace_id, false);
        try appendOptionalStringField(writer, "requestId", record.request_id, false);
        try appendOptionalStringField(writer, "errorCode", record.error_code, false);
        try appendOptionalUnsignedField(writer, "durationMs", record.duration_ms, false);
        try writer.writeByte('}');
        matches += 1;
    }

    try writer.writeByte(']');
    try writer.writeAll(",\"count\":");
    try writer.print("{d}", .{matches});
    try writer.writeByte('}');
    return ctx.allocator.dupe(u8, buf.items);
}

fn matchesFilters(record: anytype, level: ?[]const u8, subsystem: ?[]const u8, trace_id: ?[]const u8) bool {
    if (level) |expected| {
        if (!std.mem.eql(u8, record.level.asText(), expected)) return false;
    }
    if (subsystem) |expected| {
        if (!std.mem.startsWith(u8, record.subsystem, expected)) return false;
    }
    if (trace_id) |expected| {
        if (record.trace_id == null or !std.mem.eql(u8, record.trace_id.?, expected)) return false;
    }
    return true;
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
    if (value) |actual| {
        try writeJsonString(writer, actual);
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

fn appendOptionalUnsignedField(writer: anytype, key: []const u8, value: ?u64, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    if (value) |actual| {
        try writer.print("{d}", .{actual});
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
            else => {
                if (ch < 32) {
                    try writer.print("\\u00{x:0>2}", .{ch});
                } else {
                    try writer.writeByte(ch);
                }
            },
        }
    }
    try writer.writeByte('"');
}
