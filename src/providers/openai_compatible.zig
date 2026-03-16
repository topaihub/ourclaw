const std = @import("std");
const root = @import("root.zig");
const http_util = @import("../compat/http_util.zig");

var mock_retry_once_counter: usize = 0;

pub fn chatStream(
    allocator: std.mem.Allocator,
    definition: root.ProviderDefinition,
    request: root.ProviderRequest,
    api_key: []const u8,
) anyerror![]root.ProviderStreamChunk {
    if (std.mem.eql(u8, definition.endpoint, "mock://openai/chat_timeout")) {
        return error.ProviderTimeout;
    }
    if (std.mem.eql(u8, definition.endpoint, "mock://openai/chat_stream_malformed")) {
        return error.ProviderMalformedResponse;
    }
    if (std.mem.eql(u8, definition.endpoint, "mock://openai/chat_stream_upstream_close")) {
        return error.ProviderHttpFailed;
    }
    if (std.mem.eql(u8, definition.endpoint, "mock://openai/chat_stream_retry_exhausted")) {
        return error.ProviderTemporaryUnavailable;
    }
    if (std.mem.eql(u8, definition.endpoint, "mock://openai/chat_cancel_wait")) {
        var index: usize = 0;
        while (index < 20) : (index += 1) {
            if (request.cancel_requested) |signal| {
                if (signal.load(.acquire)) return error.StreamCancelled;
            }
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
    }
    if (std.mem.eql(u8, definition.endpoint, "mock://openai/chat_retry_once")) {
        if (mock_retry_once_counter == 0) {
            mock_retry_once_counter += 1;
            return error.ProviderTemporaryUnavailable;
        }
        mock_retry_once_counter = 0;
    }

    if (!std.mem.startsWith(u8, definition.endpoint, "mock://") or std.mem.eql(u8, definition.endpoint, "mock://openai/chat_stream_sse")) {
        return chatStreamSse(allocator, definition, request, api_key);
    }

    var chunks: std.ArrayListUnmanaged(root.ProviderStreamChunk) = .empty;
    errdefer {
        for (chunks.items) |*chunk| chunk.deinit(allocator);
        chunks.deinit(allocator);
    }

    if (shouldEmitToolCall(request)) {
        try appendTextChunks(allocator, &chunks, &.{"thinking "});
        try chunks.append(allocator, .{
            .kind = .tool_call,
            .tool_name = try allocator.dupe(u8, "echo"),
            .tool_input_json = try allocator.dupe(u8, "{\"message\":\"hello from tool\"}"),
        });
        try chunks.append(allocator, .{
            .kind = .done,
            .finish_reason = try allocator.dupe(u8, "tool_calls"),
            .prompt_tokens = 14,
            .completion_tokens = 4,
        });
        return chunks.toOwnedSlice(allocator);
    }

    if (containsMessage(request.messages, "PROMPT_ASSEMBLY_PROBE")) {
        try appendTextChunks(allocator, &chunks, &.{ "prompt ", "assembly ", "ok" });
        try chunks.append(allocator, .{
            .kind = .done,
            .finish_reason = try allocator.dupe(u8, "stop"),
            .prompt_tokens = 20,
            .completion_tokens = 3,
        });
        return chunks.toOwnedSlice(allocator);
    } else if (containsMessage(request.messages, "Tool Result:")) {
        try appendTextChunks(allocator, &chunks, &.{ "final ", "response ", "after ", "tool" });
        try chunks.append(allocator, .{
            .kind = .done,
            .finish_reason = try allocator.dupe(u8, "stop"),
            .prompt_tokens = 18,
            .completion_tokens = 9,
        });
        return chunks.toOwnedSlice(allocator);
    } else {
        try appendTextChunks(allocator, &chunks, &.{ "mock ", "openai ", "response" });
        try chunks.append(allocator, .{
            .kind = .done,
            .finish_reason = try allocator.dupe(u8, "stop"),
            .prompt_tokens = 12,
            .completion_tokens = 8,
        });
        return chunks.toOwnedSlice(allocator);
    }
}

fn chatStreamSse(
    allocator: std.mem.Allocator,
    definition: root.ProviderDefinition,
    request: root.ProviderRequest,
    api_key: []const u8,
) anyerror![]root.ProviderStreamChunk {
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
    try writer.writeAll("],\"stream\":true}");

    const auth_header = try std.fmt.allocPrint(allocator, "Authorization: Bearer {s}", .{api_key});
    defer allocator.free(auth_header);

    var response = try http_util.curlJsonPostStreaming(allocator, definition.endpoint, &.{auth_header}, body.items, request.timeout_secs, request.cancel_requested);
    defer response.deinit(allocator);
    if (response.status_code < 200 or response.status_code >= 300) return error.ProviderHttpFailed;

    return parseSseChunks(allocator, response.body);
}

fn parseSseChunks(allocator: std.mem.Allocator, sse_body: []const u8) anyerror![]root.ProviderStreamChunk {
    var chunks: std.ArrayListUnmanaged(root.ProviderStreamChunk) = .empty;
    errdefer {
        for (chunks.items) |*chunk| chunk.deinit(allocator);
        chunks.deinit(allocator);
    }

    var tool_name: ?[]u8 = null;
    errdefer if (tool_name) |value| allocator.free(value);
    var tool_input: std.ArrayListUnmanaged(u8) = .empty;
    defer tool_input.deinit(allocator);
    var finish_reason: ?[]u8 = null;
    defer if (finish_reason) |value| allocator.free(value);
    var appended_done = false;

    var events = std.mem.splitSequence(u8, sse_body, "\n\n");
    while (events.next()) |event_block| {
        const trimmed_block = std.mem.trim(u8, event_block, "\r\n \t");
        if (trimmed_block.len == 0) continue;

        var event_data: std.ArrayListUnmanaged(u8) = .empty;
        defer event_data.deinit(allocator);
        var lines = std.mem.splitScalar(u8, trimmed_block, '\n');
        while (lines.next()) |line| {
            const trimmed_line = std.mem.trim(u8, line, "\r\n \t");
            if (!std.mem.startsWith(u8, trimmed_line, "data:")) continue;
            const payload = std.mem.trim(u8, trimmed_line[5..], " \t");
            if (event_data.items.len > 0) try event_data.append(allocator, '\n');
            try event_data.appendSlice(allocator, payload);
        }

        if (event_data.items.len == 0) continue;
        if (std.mem.eql(u8, event_data.items, "[DONE]")) break;

        if (extractStringField(event_data.items, "content")) |content| {
            try chunks.append(allocator, .{
                .kind = .text_delta,
                .text = try allocator.dupe(u8, content),
            });
        }
        if (tool_name == null) {
            if (extractToolName(event_data.items)) |value| {
                tool_name = try allocator.dupe(u8, value);
            }
        }
        if (extractToolArguments(event_data.items)) |arguments| {
            const unescaped = try unescapeJsonString(allocator, arguments);
            defer allocator.free(unescaped);
            try tool_input.appendSlice(allocator, unescaped);
        }
        if (extractStringField(event_data.items, "finish_reason")) |value| {
            if (finish_reason) |owned| allocator.free(owned);
            finish_reason = try allocator.dupe(u8, value);
        }

        const prompt_tokens = extractUnsignedField(event_data.items, "prompt_tokens");
        const completion_tokens = extractUnsignedField(event_data.items, "completion_tokens");
        if (prompt_tokens != null or completion_tokens != null) {
            try chunks.append(allocator, .{
                .kind = .done,
                .finish_reason = if (finish_reason) |value| try allocator.dupe(u8, value) else try allocator.dupe(u8, "stop"),
                .prompt_tokens = if (prompt_tokens) |value| @intCast(value) else null,
                .completion_tokens = if (completion_tokens) |value| @intCast(value) else null,
            });
            appended_done = true;
            finish_reason = null;
        }
    }

    if (tool_name) |value| {
        try chunks.append(allocator, .{
            .kind = .tool_call,
            .tool_name = value,
            .tool_input_json = if (tool_input.items.len > 0) try allocator.dupe(u8, tool_input.items) else null,
        });
        tool_name = null;
    }
    if (!appended_done) {
        try chunks.append(allocator, .{
            .kind = .done,
            .finish_reason = if (finish_reason) |value| try allocator.dupe(u8, value) else try allocator.dupe(u8, "stop"),
            .prompt_tokens = null,
            .completion_tokens = null,
        });
    }

    return chunks.toOwnedSlice(allocator);
}

pub fn chatOnce(
    allocator: std.mem.Allocator,
    definition: root.ProviderDefinition,
    request: root.ProviderRequest,
    api_key: []const u8,
) anyerror!root.ProviderResponse {
    var effective_definition = definition;
    if (std.mem.eql(u8, definition.endpoint, "mock://openai/chat_timeout")) {
        return error.ProviderTimeout;
    }
    if (std.mem.eql(u8, definition.endpoint, "mock://openai/chat_cancel_wait")) {
        var index: usize = 0;
        while (index < 20) : (index += 1) {
            if (request.cancel_requested) |signal| {
                if (signal.load(.acquire)) return error.StreamCancelled;
            }
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
        effective_definition.endpoint = "mock://openai/chat";
    }
    if (std.mem.eql(u8, definition.endpoint, "mock://openai/chat_retry_once")) {
        if (mock_retry_once_counter == 0) {
            mock_retry_once_counter += 1;
            return error.ProviderTemporaryUnavailable;
        }
        mock_retry_once_counter = 0;
        effective_definition.endpoint = "mock://openai/chat";
    }

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

    var response = try http_util.curlJsonPost(allocator, effective_definition.endpoint, &.{auth_header}, body.items, request.timeout_secs, request.cancel_requested);
    defer response.deinit(allocator);
    if (response.status_code < 200 or response.status_code >= 300) return error.ProviderHttpFailed;

    const text = extractContent(response.body) orelse return error.ProviderMalformedResponse;
    const model = extractStringField(response.body, "model") orelse effective_definition.default_model;
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

pub fn embedText(
    allocator: std.mem.Allocator,
    definition: root.ProviderDefinition,
    request: root.EmbeddingRequest,
    api_key: []const u8,
) anyerror!root.EmbeddingResponse {
    _ = api_key;
    return .{
        .provider_id = try allocator.dupe(u8, request.provider_id),
        .model = try allocator.dupe(u8, request.model orelse definition.default_embedding_model),
        .strategy = .provider_proxy_v1,
        .vector = embedLocally(request.input),
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

fn embedLocally(text: []const u8) root.EmbeddingVector {
    var vector: root.EmbeddingVector = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
    for (text) |ch| {
        const bucket = ch % vector.len;
        vector[bucket] += 1;
    }
    return normalize(vector);
}

fn shouldEmitToolCall(request: root.ProviderRequest) bool {
    return request.enable_tools and containsMessage(request.messages, "CALL_TOOL:echo") and !containsMessage(request.messages, "Tool Result:");
}

fn containsMessage(messages: []const root.ProviderMessage, needle: []const u8) bool {
    for (messages) |message| {
        if (std.mem.indexOf(u8, message.content, needle) != null) return true;
    }
    return false;
}

fn appendTextChunks(allocator: std.mem.Allocator, chunks: *std.ArrayListUnmanaged(root.ProviderStreamChunk), texts: []const []const u8) anyerror!void {
    for (texts) |text| {
        try chunks.append(allocator, .{
            .kind = .text_delta,
            .text = try allocator.dupe(u8, text),
        });
    }
}

fn normalize(vector: root.EmbeddingVector) root.EmbeddingVector {
    var sum: f32 = 0;
    for (vector) |value| sum += value * value;
    if (sum == 0) return vector;
    const norm = std.math.sqrt(sum);
    var result = vector;
    for (&result) |*value| value.* /= norm;
    return result;
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

test "openai compatible provider returns embedding response" {
    var response = try embedText(std.testing.allocator, .{
        .id = "mock_openai",
        .label = "Mock OpenAI",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .default_embedding_model = "text-embedding-3-small",
        .api_key_secret_ref = "openai:api_key",
        .supports_embeddings = true,
        .health_json = "{}",
    }, .{
        .provider_id = "mock_openai",
        .input = "gateway status",
    }, "test-key");
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("mock_openai", response.provider_id);
    try std.testing.expectEqualStrings("text-embedding-3-small", response.model);
    try std.testing.expectEqual(root.EmbeddingStrategy.provider_proxy_v1, response.strategy);
}

test "openai compatible provider returns timeout for timeout mock endpoint" {
    const request = root.ProviderRequest{
        .provider_id = "mock_openai_timeout",
        .messages = &.{.{ .role = .user, .content = "hello" }},
    };
    try std.testing.expectError(error.ProviderTimeout, chatOnce(std.testing.allocator, .{
        .id = "mock_openai_timeout",
        .label = "Mock OpenAI Timeout",
        .endpoint = "mock://openai/chat_timeout",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    }, request, "test-key"));
}

test "openai compatible provider honours cancellation signal" {
    var cancelled = std.atomic.Value(bool).init(true);
    const request = root.ProviderRequest{
        .provider_id = "mock_openai_cancel_wait",
        .messages = &.{.{ .role = .user, .content = "hello" }},
        .cancel_requested = &cancelled,
    };
    try std.testing.expectError(error.StreamCancelled, chatOnce(std.testing.allocator, .{
        .id = "mock_openai_cancel_wait",
        .label = "Mock OpenAI Cancel Wait",
        .endpoint = "mock://openai/chat_cancel_wait",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    }, request, "test-key"));
}

test "openai compatible provider emits native text stream chunks" {
    const request = root.ProviderRequest{
        .provider_id = "mock_openai_stream",
        .messages = &.{.{ .role = .user, .content = "hello" }},
    };
    const chunks = try chatStream(std.testing.allocator, .{
        .id = "mock_openai_stream",
        .label = "Mock OpenAI Stream",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    }, request, "test-key");
    defer {
        for (chunks) |*chunk| chunk.deinit(std.testing.allocator);
        std.testing.allocator.free(chunks);
    }

    try std.testing.expect(chunks.len >= 2);
    try std.testing.expectEqual(root.ProviderStreamChunk.Kind.text_delta, chunks[0].kind);
    try std.testing.expectEqual(root.ProviderStreamChunk.Kind.done, chunks[chunks.len - 1].kind);
}

test "openai compatible provider emits tool call mid-stream" {
    const request = root.ProviderRequest{
        .provider_id = "mock_openai_stream_tool",
        .messages = &.{.{ .role = .user, .content = "CALL_TOOL:echo" }},
        .enable_tools = true,
    };
    const chunks = try chatStream(std.testing.allocator, .{
        .id = "mock_openai_stream_tool",
        .label = "Mock OpenAI Stream Tool",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    }, request, "test-key");
    defer {
        for (chunks) |*chunk| chunk.deinit(std.testing.allocator);
        std.testing.allocator.free(chunks);
    }

    try std.testing.expectEqual(root.ProviderStreamChunk.Kind.text_delta, chunks[0].kind);
    try std.testing.expectEqual(root.ProviderStreamChunk.Kind.tool_call, chunks[1].kind);
    try std.testing.expectEqualStrings("echo", chunks[1].tool_name.?);
}

test "openai compatible provider reports malformed stream endpoint" {
    try std.testing.expectError(error.ProviderMalformedResponse, chatStream(std.testing.allocator, .{
        .id = "mock_openai_stream_malformed",
        .label = "Mock OpenAI Stream Malformed",
        .endpoint = "mock://openai/chat_stream_malformed",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    }, .{
        .provider_id = "mock_openai_stream_malformed",
        .messages = &.{.{ .role = .user, .content = "hello" }},
    }, "test-key"));
}

test "openai compatible provider reports upstream close endpoint" {
    try std.testing.expectError(error.ProviderHttpFailed, chatStream(std.testing.allocator, .{
        .id = "mock_openai_stream_upstream_close",
        .label = "Mock OpenAI Stream Upstream Close",
        .endpoint = "mock://openai/chat_stream_upstream_close",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    }, .{
        .provider_id = "mock_openai_stream_upstream_close",
        .messages = &.{.{ .role = .user, .content = "hello" }},
    }, "test-key"));
}

test "openai compatible provider parses SSE chat stream endpoint" {
    const chunks = try chatStream(std.testing.allocator, .{
        .id = "mock_openai_stream_sse",
        .label = "Mock OpenAI Stream SSE",
        .endpoint = "mock://openai/chat_stream_sse",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    }, .{
        .provider_id = "mock_openai_stream_sse",
        .messages = &.{.{ .role = .user, .content = "hello" }},
    }, "test-key");
    defer {
        for (chunks) |*chunk| chunk.deinit(std.testing.allocator);
        std.testing.allocator.free(chunks);
    }

    try std.testing.expectEqual(root.ProviderStreamChunk.Kind.text_delta, chunks[0].kind);
    try std.testing.expectEqualStrings("mock ", chunks[0].text.?);
    try std.testing.expectEqual(root.ProviderStreamChunk.Kind.done, chunks[chunks.len - 1].kind);
    try std.testing.expectEqualStrings("stop", chunks[chunks.len - 1].finish_reason.?);
}
