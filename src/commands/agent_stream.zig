const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");
const runtime_model = @import("../runtime/app_context.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "agent.stream",
        .method = "agent.stream",
        .description = "Run agent turn and return stream event snapshot",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "session_id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "prompt", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "provider_id", .required = false, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "tool_id", .required = false, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "tool_input_json", .required = false, .value_kind = .string },
            .{ .key = "limit", .required = false, .value_kind = .integer, .rules = &.{.{ .int_range = .{ .min = 1, .max = 256 } }} },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *runtime_model.AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const limit: usize = if (ctx.param("limit")) |field| @intCast(field.value.integer) else 128;

    const after_seq = app.framework_context.event_bus.latestSeq();
    const subscription_id = try app.framework_context.event_bus.subscribe(&.{"stream.output"}, after_seq);

    var result = try app.agent_runtime.runStream(.{
        .session_id = ctx.param("session_id").?.value.string,
        .prompt = ctx.param("prompt").?.value.string,
        .provider_id = if (ctx.param("provider_id")) |field| field.value.string else "openai",
        .tool_id = if (ctx.param("tool_id")) |field| field.value.string else null,
        .tool_input_json = if (ctx.param("tool_input_json")) |field| field.value.string else null,
        .authority = ctx.request.authority,
    });
    defer result.deinit(ctx.allocator);

    var batch = try app.framework_context.event_bus.pollSubscription(ctx.allocator, subscription_id, limit);
    defer batch.deinit(ctx.allocator);

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.writeByte('{');
    try appendStringField(writer, "sessionId", result.session_id, true);
    try appendStringField(writer, "providerId", result.provider_id, false);
    try appendStringField(writer, "model", result.model, false);
    try appendUnsignedField(writer, "toolRounds", result.tool_rounds, false);
    try appendUnsignedField(writer, "memoryEntriesUsed", result.memory_entries_used, false);
    try appendUnsignedField(writer, "providerLatencyMs", @intCast(result.provider_latency_ms), false);
    try appendUnsignedField(writer, "subscriptionId", @intCast(subscription_id), false);
    try appendUnsignedField(writer, "lastSeq", @intCast(batch.last_seq), false);
    try appendBoolField(writer, "hasMore", batch.has_more, false);
    try writer.writeAll(",\"events\":[");
    for (batch.events, 0..) |event, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try appendUnsignedField(writer, "seq", @intCast(event.seq), true);
        try appendStringField(writer, "topic", event.topic, false);
        try appendRawJsonField(writer, "payload", event.payload_json, false);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
    try appendStringField(writer, "finalResponseText", result.final_response_text, false);
    try writer.writeByte('}');
    return ctx.allocator.dupe(u8, buf.items);
}

fn appendStringField(writer: anytype, key: []const u8, value: []const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writeJsonString(writer, value);
}

fn appendUnsignedField(writer: anytype, key: []const u8, value: usize, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.print("{d}", .{value});
}

fn appendBoolField(writer: anytype, key: []const u8, value: bool, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.writeAll(if (value) "true" else "false");
}

fn appendRawJsonField(writer: anytype, key: []const u8, value_json: []const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.writeAll(value_json);
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
