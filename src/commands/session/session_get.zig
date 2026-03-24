const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;
const session_state = domain.session_state;

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
            .{ .key = "recent_turns_limit", .required = false, .value_kind = .integer, .rules = &.{.{ .int_range = .{ .min = 1, .max = 8 } }} },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const session_id = ctx.param("session_id").?.value.string;
    const summary_items: usize = if (ctx.param("summary_items")) |field| @intCast(field.value.integer) else 6;
    const recent_turns_limit: usize = if (ctx.param("recent_turns_limit")) |field| @intCast(field.value.integer) else 3;

    var snapshot = try services.session_store.snapshotMeta(ctx.allocator, session_id);
    defer snapshot.deinit(ctx.allocator);
    var summary = try services.memory_runtime.summarizeSession(ctx.allocator, session_id, summary_items);
    defer summary.deinit(ctx.allocator);
    const recent_turns = try services.session_store.recentTurns(ctx.allocator, session_id, recent_turns_limit);
    defer {
        for (recent_turns) |*turn| turn.deinit(ctx.allocator);
        ctx.allocator.free(recent_turns);
    }

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
    try appendOptionalBoolField(writer, "allowProviderTools", snapshot.latest_allow_provider_tools, false);
    try appendOptionalStringField(writer, "promptProfile", snapshot.latest_prompt_profile, false);
    try appendOptionalStringField(writer, "responseMode", snapshot.latest_response_mode, false);
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
    try appendUsageBlock(writer, snapshot);
    try appendRecentTurnsBlock(writer, recent_turns);
    try appendCountsBlock(writer, snapshot);
    try appendReplayBlock(writer, snapshot);
    try appendRecoveryBlock(ctx.allocator, writer, snapshot);
    try appendLatestTurnBlock(writer, snapshot);
    try writer.writeByte('}');
    return ctx.allocator.dupe(u8, buf.items);
}

fn appendUsageBlock(writer: anytype, snapshot: session_state.SessionSnapshot) anyerror!void {
    try writer.writeAll(",\"usage\":{");
    try appendUnsigned64Field(writer, "promptTokens", snapshot.cumulative_prompt_tokens, true);
    try appendUnsigned64Field(writer, "completionTokens", snapshot.cumulative_completion_tokens, false);
    try appendUnsigned64Field(writer, "totalTokens", snapshot.cumulative_total_tokens, false);
    try appendUnsignedField(writer, "turnCount", snapshot.usage_turn_count, false);
    try writer.writeByte('}');
}

fn appendRecentTurnsBlock(writer: anytype, recent_turns: []const session_state.RecentTurnSnapshot) anyerror!void {
    try writer.writeAll(",\"recentTurns\":[");
    for (recent_turns, 0..) |turn, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try appendUnsigned64Field(writer, "seq", turn.seq, true);
        try appendOptionalUnsignedField(writer, "streamSeq", turn.stream_seq, false);
        try appendOptionalStringField(writer, "executionId", turn.execution_id, false);
        try appendSigned64Field(writer, "tsUnixMs", turn.ts_unix_ms, false);
        try appendOptionalStringField(writer, "providerId", turn.provider_id, false);
        try appendOptionalStringField(writer, "model", turn.model, false);
        try appendOptionalBoolField(writer, "allowProviderTools", turn.allow_provider_tools, false);
        try appendOptionalStringField(writer, "promptProfile", turn.prompt_profile, false);
        try appendOptionalStringField(writer, "responseMode", turn.response_mode, false);
        try appendOptionalStringField(writer, "toolId", turn.tool_id, false);
        try appendUnsignedField(writer, "toolRounds", turn.tool_rounds, false);
        try appendUnsignedField(writer, "maxToolRounds", turn.max_tool_rounds, false);
        try appendUnsignedField(writer, "memoryEntriesUsed", turn.memory_entries_used, false);
        try appendOptionalUnsignedField(writer, "providerLatencyMs", turn.provider_latency_ms, false);
        try appendOptionalUnsignedField(writer, "promptTokens", turn.prompt_tokens, false);
        try appendOptionalUnsignedField(writer, "completionTokens", turn.completion_tokens, false);
        try appendOptionalUnsignedField(writer, "totalTokens", turn.total_tokens, false);
        try appendOptionalStringField(writer, "errorCode", turn.error_code, false);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn appendRecoveryBlock(allocator: std.mem.Allocator, writer: anytype, snapshot: session_state.SessionSnapshot) anyerror!void {
    const execution_cursor = try buildExecutionCursor(allocator, snapshot.latest_execution_id, snapshot.last_stream_seq);
    defer if (execution_cursor) |value| allocator.free(value);
    const last_event_id: ?u64 = if (snapshot.last_stream_seq > 0) snapshot.last_stream_seq else null;

    try writer.writeAll(",\"recovery\":{");
    try appendOptionalUnsignedField(writer, "lastEventId", last_event_id, true);
    try appendOptionalStringField(writer, "executionCursor", execution_cursor, false);
    try writer.writeByte('}');
}

fn appendCountsBlock(writer: anytype, snapshot: session_state.SessionSnapshot) anyerror!void {
    try writer.writeAll(",\"counts\":{");
    try appendUnsignedField(writer, "events", snapshot.event_count, true);
    try appendUnsignedField(writer, "toolTraces", snapshot.tool_trace_count, false);
    try appendUnsignedField(writer, "turns", snapshot.turn_count, false);
    try appendUnsignedField(writer, "assistantResponses", snapshot.assistant_response_count, false);
    try appendUnsignedField(writer, "errors", snapshot.error_event_count, false);
    try appendUnsignedField(writer, "streamOutputs", snapshot.stream_output_count, false);
    try writer.writeByte('}');
}

fn appendReplayBlock(writer: anytype, snapshot: session_state.SessionSnapshot) anyerror!void {
    try writer.writeAll(",\"replay\":{");
    try appendUnsigned64Field(writer, "firstStreamSeq", snapshot.first_stream_seq, true);
    try appendUnsigned64Field(writer, "lastStreamSeq", snapshot.last_stream_seq, false);
    try appendUnsignedField(writer, "replayableEventCount", snapshot.replayable_event_count, false);
    try appendOptionalStringField(writer, "lastExecutionId", snapshot.latest_execution_id, false);
    try writer.writeByte('}');
}

fn appendLatestTurnBlock(writer: anytype, snapshot: session_state.SessionSnapshot) anyerror!void {
    try writer.writeAll(",\"latestTurn\":{");
    try appendOptionalStringField(writer, "providerId", snapshot.latest_provider_id, true);
    try appendOptionalStringField(writer, "model", snapshot.latest_model, false);
    try appendOptionalBoolField(writer, "allowProviderTools", snapshot.latest_allow_provider_tools, false);
    try appendOptionalStringField(writer, "promptProfile", snapshot.latest_prompt_profile, false);
    try appendOptionalStringField(writer, "responseMode", snapshot.latest_response_mode, false);
    try appendOptionalStringField(writer, "toolId", snapshot.latest_tool_id, false);
    try appendUnsignedField(writer, "toolRounds", snapshot.latest_tool_rounds, false);
    try appendUnsignedField(writer, "maxToolRounds", snapshot.latest_max_tool_rounds, false);
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
}

fn buildExecutionCursor(allocator: std.mem.Allocator, execution_id: ?[]const u8, after_seq: u64) anyerror!?[]u8 {
    if (execution_id == null or after_seq == 0) return null;
    const cursor = try std.fmt.allocPrint(allocator, "{s}:{d}", .{ execution_id.?, after_seq });
    return cursor;
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

fn appendOptionalBoolField(writer: anytype, key: []const u8, value: ?bool, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    if (value) |flag| {
        try writer.writeAll(if (flag) "true" else "false");
    } else {
        try writer.writeAll("null");
    }
}

fn appendSigned64Field(writer: anytype, key: []const u8, value: i64, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.print("{d}", .{value});
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
