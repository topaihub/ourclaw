const std = @import("std");
const root = @import("root.zig");
const http_util = @import("../compat/http_util.zig");

pub fn chatOnce(
    allocator: std.mem.Allocator,
    definition: root.ProviderDefinition,
    request: root.ProviderRequest,
    api_key: []const u8,
) anyerror!root.ProviderResponse {
    var body: std.ArrayListUnmanaged(u8) = .empty;
    defer body.deinit(allocator);
    const writer = body.writer(allocator);

    try writer.writeAll("{\"model\":");
    try writeJsonString(writer, request.model orelse definition.default_model);
    try writer.writeAll(",\"messages\":[");
    for (request.messages, 0..) |message, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeAll("{\"role\":");
        try writeJsonString(writer, message.role.asText());
        try writer.writeAll(",\"content\":");
        try writeJsonString(writer, message.content);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
    try writer.writeByte('}');

    const auth_header = try std.fmt.allocPrint(allocator, "Authorization: Bearer {s}", .{api_key});
    defer allocator.free(auth_header);

    var response = try http_util.curlJsonPost(allocator, definition.endpoint, &.{auth_header}, body.items, 60);
    defer response.deinit(allocator);
    if (response.status_code < 200 or response.status_code >= 300) return error.ProviderHttpFailed;

    const text = extractContent(response.body) orelse return error.ProviderMalformedResponse;
    const model = extractStringField(response.body, "model") orelse definition.default_model;
    const finish_reason = extractStringField(response.body, "finish_reason");
    const prompt_tokens = extractUnsignedField(response.body, "prompt_tokens");
    const completion_tokens = extractUnsignedField(response.body, "completion_tokens");
    const tool_name = extractToolName(response.body);
    const tool_input_json = if (extractToolArguments(response.body)) |value| try unescapeJsonString(allocator, value) else null;

    return .{
        .provider_id = try allocator.dupe(u8, request.provider_id),
        .model = try allocator.dupe(u8, model),
        .text = try allocator.dupe(u8, text),
        .tool_name = if (tool_name) |value| try allocator.dupe(u8, value) else null,
        .tool_input_json = tool_input_json,
        .finish_reason = if (finish_reason) |value| try allocator.dupe(u8, value) else null,
        .prompt_tokens = if (prompt_tokens) |value| @intCast(value) else null,
        .completion_tokens = if (completion_tokens) |value| @intCast(value) else null,
        .raw_json = try allocator.dupe(u8, response.body),
    };
}

fn extractContent(body: []const u8) ?[]const u8 {
    const message_marker = "\"content\":\"";
    const start = std.mem.indexOf(u8, body, message_marker) orelse return null;
    const value_start = start + message_marker.len;
    const value_end = std.mem.indexOfScalarPos(u8, body, value_start, '"') orelse return null;
    return body[value_start..value_end];
}

fn extractStringField(body: []const u8, key: []const u8) ?[]const u8 {
    var marker_buf: [128]u8 = undefined;
    const marker = std.fmt.bufPrint(&marker_buf, "\"{s}\":\"", .{key}) catch return null;
    const start = std.mem.indexOf(u8, body, marker) orelse return null;
    const value_start = start + marker.len;
    const value_end = std.mem.indexOfScalarPos(u8, body, value_start, '"') orelse return null;
    return body[value_start..value_end];
}

fn extractUnsignedField(body: []const u8, key: []const u8) ?u64 {
    var marker_buf: [128]u8 = undefined;
    const marker = std.fmt.bufPrint(&marker_buf, "\"{s}\":", .{key}) catch return null;
    const start = std.mem.indexOf(u8, body, marker) orelse return null;
    const value_start = start + marker.len;
    var value_end = value_start;
    while (value_end < body.len and std.ascii.isDigit(body[value_end])) : (value_end += 1) {}
    if (value_end == value_start) return null;
    return std.fmt.parseInt(u64, body[value_start..value_end], 10) catch null;
}

fn extractToolName(body: []const u8) ?[]const u8 {
    return extractStringField(body, "name");
}

fn extractToolArguments(body: []const u8) ?[]const u8 {
    const marker = "\"arguments\":\"";
    const start = std.mem.indexOf(u8, body, marker) orelse return null;
    const value_start = start + marker.len;
    var value_end = value_start;
    var escaped = false;
    while (value_end < body.len) : (value_end += 1) {
        const ch = body[value_end];
        if (escaped) {
            escaped = false;
            continue;
        }
        if (ch == '\\') {
            escaped = true;
            continue;
        }
        if (ch == '"') break;
    }
    if (value_end >= body.len) return null;
    return body[value_start..value_end];
}

fn unescapeJsonString(allocator: std.mem.Allocator, value: []const u8) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);

    var index: usize = 0;
    while (index < value.len) : (index += 1) {
        const ch = value[index];
        if (ch == '\\' and index + 1 < value.len) {
            index += 1;
            const next = value[index];
            switch (next) {
                '"' => try buf.append(allocator, '"'),
                '\\' => try buf.append(allocator, '\\'),
                'n' => try buf.append(allocator, '\n'),
                'r' => try buf.append(allocator, '\r'),
                't' => try buf.append(allocator, '\t'),
                else => {
                    try buf.append(allocator, next);
                },
            }
            continue;
        }

        try buf.append(allocator, ch);
    }

    return allocator.dupe(u8, buf.items);
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

test "openai compatible provider parses mock response" {
    const request = root.ProviderRequest{
        .provider_id = "mock_openai",
        .messages = &.{.{ .role = .user, .content = "hello" }},
    };
    var response = try chatOnce(std.testing.allocator, .{
        .id = "mock_openai",
        .label = "Mock OpenAI",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    }, request, "test-key");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("mock openai response", response.text);
    try std.testing.expectEqual(@as(u32, 12), response.prompt_tokens.?);
}

test "openai compatible provider parses tool call response" {
    const request = root.ProviderRequest{
        .provider_id = "mock_openai",
        .messages = &.{.{ .role = .user, .content = "CALL_TOOL:echo" }},
        .enable_tools = true,
    };
    var response = try chatOnce(std.testing.allocator, .{
        .id = "mock_openai",
        .label = "Mock OpenAI",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    }, request, "test-key");
    defer response.deinit(std.testing.allocator);

    try std.testing.expect(response.tool_name != null);
    try std.testing.expectEqualStrings("echo", response.tool_name.?);
    try std.testing.expect(response.tool_input_json != null);
}
