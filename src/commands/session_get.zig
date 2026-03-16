const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "session.get",
        .method = "session.get",
        .description = "Get session snapshot with summary",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "session_id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "summary_items", .required = false, .value_kind = .integer, .rules = &.{.{ .int_range = .{ .min = 1, .max = 32 } }} },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const session_id = ctx.param("session_id").?.value.string;
    const summary_items: usize = if (ctx.param("summary_items")) |field| @intCast(field.value.integer) else 6;

    var snapshot = try services.session_store.snapshotMeta(ctx.allocator, session_id);
    defer snapshot.deinit(ctx.allocator);
    var summary = try services.memory_runtime.summarizeSession(ctx.allocator, session_id, summary_items);
    defer summary.deinit(ctx.allocator);

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.writeByte('{');
    try appendStringField(writer, "sessionId", snapshot.session_id, true);
    try appendUnsignedField(writer, "eventCount", snapshot.event_count, false);
    try appendUnsigned64Field(writer, "firstEventSeq", snapshot.first_event_seq, false);
    try appendUnsigned64Field(writer, "lastEventSeq", snapshot.last_event_seq, false);
    try appendOptionalSigned64Field(writer, "lastEventTsUnixMs", snapshot.last_event_ts_unix_ms, false);
    try appendUnsigned64Field(writer, "firstStreamSeq", snapshot.first_stream_seq, false);
    try appendUnsigned64Field(writer, "lastStreamSeq", snapshot.last_stream_seq, false);
    try appendUnsignedField(writer, "replayableEventCount", snapshot.replayable_event_count, false);
    try appendOptionalStringField(writer, "lastExecutionId", snapshot.latest_execution_id, false);
    try appendUnsignedField(writer, "turnCount", snapshot.turn_count, false);
    try appendUnsignedField(writer, "assistantResponseCount", snapshot.assistant_response_count, false);
    try appendUnsignedField(writer, "errorEventCount", snapshot.error_event_count, false);
    try appendUnsignedField(writer, "streamOutputCount", snapshot.stream_output_count, false);
    try appendUnsignedField(writer, "memoryEntryCount", services.memory_runtime.countBySession(session_id), false);
    try appendUnsignedField(writer, "toolTraceCount", snapshot.tool_trace_count, false);
    try appendOptionalStringField(writer, "lastEventKind", snapshot.last_event_kind, false);
    try appendOptionalStringField(writer, "latestSummaryEvent", snapshot.latest_summary_text, false);
    try appendOptionalStringField(writer, "latestAssistantResponse", snapshot.latest_assistant_response, false);
    try appendOptionalStringField(writer, "providerId", snapshot.latest_provider_id, false);
    try appendOptionalStringField(writer, "model", snapshot.latest_model, false);
    try appendOptionalStringField(writer, "lastToolId", snapshot.latest_tool_id, false);
    try appendOptionalRawJsonField(writer, "latestToolResult", snapshot.latest_tool_result_json, false);
    try appendUnsignedField(writer, "toolRounds", snapshot.latest_tool_rounds, false);
    try appendUnsignedField(writer, "providerRoundBudget", snapshot.latest_provider_round_budget, false);
    try appendUnsignedField(writer, "providerRoundsRemaining", snapshot.latest_provider_rounds_remaining, false);
    try appendUnsignedField(writer, "providerAttemptBudget", snapshot.latest_provider_attempt_budget, false);
    try appendUnsignedField(writer, "providerAttemptsRemaining", snapshot.latest_provider_attempts_remaining, false);
    try appendUnsignedField(writer, "toolCallBudget", snapshot.latest_tool_call_budget, false);
    try appendUnsignedField(writer, "toolCallsRemaining", snapshot.latest_tool_calls_remaining, false);
    try appendUnsignedField(writer, "providerRetryBudget", snapshot.latest_provider_retry_budget, false);
    try appendUnsigned64Field(writer, "totalDeadlineMs", snapshot.latest_total_deadline_ms, false);
    try appendOptionalUnsignedField(writer, "promptTokens", snapshot.latest_prompt_tokens, false);
    try appendOptionalUnsignedField(writer, "completionTokens", snapshot.latest_completion_tokens, false);
    try appendOptionalUnsignedField(writer, "totalTokens", snapshot.latest_total_tokens, false);
    try appendOptionalUnsignedField(writer, "providerLatencyMs", snapshot.latest_provider_latency_ms, false);
    try appendUnsignedField(writer, "memoryEntriesUsed", snapshot.latest_memory_entries_used, false);
    try appendOptionalStringField(writer, "lastErrorCode", snapshot.last_error_code, false);
    try appendStringField(writer, "summaryText", summary.summary_text, false);
    try appendUnsignedField(writer, "summarySourceCount", summary.source_count, false);
    try writer.writeAll(",\"counts\":{");
    try appendUnsignedField(writer, "events", snapshot.event_count, true);
    try appendUnsignedField(writer, "toolTraces", snapshot.tool_trace_count, false);
    try appendUnsignedField(writer, "turns", snapshot.turn_count, false);
    try appendUnsignedField(writer, "assistantResponses", snapshot.assistant_response_count, false);
    try appendUnsignedField(writer, "errors", snapshot.error_event_count, false);
    try appendUnsignedField(writer, "streamOutputs", snapshot.stream_output_count, false);
    try writer.writeByte('}');
    try writer.writeAll(",\"replay\":{");
    try appendUnsigned64Field(writer, "firstStreamSeq", snapshot.first_stream_seq, true);
    try appendUnsigned64Field(writer, "lastStreamSeq", snapshot.last_stream_seq, false);
    try appendUnsignedField(writer, "replayableEventCount", snapshot.replayable_event_count, false);
    try appendOptionalStringField(writer, "lastExecutionId", snapshot.latest_execution_id, false);
    try writer.writeByte('}');
    try writer.writeAll(",\"latestTurn\":{");
    try appendOptionalStringField(writer, "providerId", snapshot.latest_provider_id, true);
    try appendOptionalStringField(writer, "model", snapshot.latest_model, false);
    try appendOptionalStringField(writer, "toolId", snapshot.latest_tool_id, false);
    try appendUnsignedField(writer, "toolRounds", snapshot.latest_tool_rounds, false);
    try appendOptionalUnsignedField(writer, "providerLatencyMs", snapshot.latest_provider_latency_ms, false);
    try appendUnsignedField(writer, "memoryEntriesUsed", snapshot.latest_memory_entries_used, false);
    try appendUnsignedField(writer, "providerRoundBudget", snapshot.latest_provider_round_budget, false);
    try appendUnsignedField(writer, "providerRoundsRemaining", snapshot.latest_provider_rounds_remaining, false);
    try appendUnsignedField(writer, "providerAttemptBudget", snapshot.latest_provider_attempt_budget, false);
    try appendUnsignedField(writer, "providerAttemptsRemaining", snapshot.latest_provider_attempts_remaining, false);
    try appendUnsignedField(writer, "toolCallBudget", snapshot.latest_tool_call_budget, false);
    try appendUnsignedField(writer, "toolCallsRemaining", snapshot.latest_tool_calls_remaining, false);
    try appendUnsignedField(writer, "providerRetryBudget", snapshot.latest_provider_retry_budget, false);
    try appendUnsigned64Field(writer, "totalDeadlineMs", snapshot.latest_total_deadline_ms, false);
    try appendOptionalUnsignedField(writer, "promptTokens", snapshot.latest_prompt_tokens, false);
    try appendOptionalUnsignedField(writer, "completionTokens", snapshot.latest_completion_tokens, false);
    try appendOptionalUnsignedField(writer, "totalTokens", snapshot.latest_total_tokens, false);
    try appendOptionalStringField(writer, "lastErrorCode", snapshot.last_error_code, false);
    try appendOptionalStringField(writer, "executionId", snapshot.latest_execution_id, false);
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

fn appendOptionalUnsignedField(writer: anytype, key: []const u8, value: ?u64, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    if (value) |number| {
        try writer.print("{d}", .{number});
    } else {
        try writer.writeAll("null");
    }
}

fn appendUnsigned64Field(writer: anytype, key: []const u8, value: u64, first: bool) anyerror!void {
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

fn appendOptionalRawJsonField(writer: anytype, key: []const u8, value: ?[]const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    if (value) |json| {
        try writer.writeAll(json);
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
