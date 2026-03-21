const std = @import("std");
const json_fields = @import("session_state_json_fields.zig");

pub const SessionSnapshot = struct {
    session_id: []u8,
    event_count: usize,
    tool_trace_count: usize = 0,
    turn_count: usize = 0,
    assistant_response_count: usize = 0,
    error_event_count: usize = 0,
    stream_output_count: usize = 0,
    first_event_seq: u64 = 0,
    last_event_seq: u64 = 0,
    last_event_ts_unix_ms: ?i64 = null,
    first_stream_seq: u64 = 0,
    last_stream_seq: u64 = 0,
    replayable_event_count: usize = 0,
    latest_execution_id: ?[]u8 = null,
    last_event_kind: ?[]u8 = null,
    latest_summary_text: ?[]u8 = null,
    latest_assistant_response: ?[]u8 = null,
    latest_provider_id: ?[]u8 = null,
    latest_model: ?[]u8 = null,
    latest_allow_provider_tools: ?bool = null,
    latest_prompt_profile: ?[]u8 = null,
    latest_response_mode: ?[]u8 = null,
    latest_tool_id: ?[]u8 = null,
    latest_tool_result_json: ?[]u8 = null,
    latest_tool_rounds: usize = 0,
    latest_max_tool_rounds: usize = 0,
    latest_provider_latency_ms: ?u64 = null,
    latest_memory_entries_used: usize = 0,
    latest_provider_round_budget: usize = 0,
    latest_provider_rounds_remaining: usize = 0,
    latest_provider_attempt_budget: usize = 0,
    latest_provider_attempts_remaining: usize = 0,
    latest_tool_call_budget: usize = 0,
    latest_tool_calls_remaining: usize = 0,
    latest_provider_retry_budget: usize = 0,
    latest_total_deadline_ms: u64 = 0,
    latest_prompt_tokens: ?u64 = null,
    latest_completion_tokens: ?u64 = null,
    latest_total_tokens: ?u64 = null,
    cumulative_prompt_tokens: u64 = 0,
    cumulative_completion_tokens: u64 = 0,
    cumulative_total_tokens: u64 = 0,
    usage_turn_count: usize = 0,
    last_error_code: ?[]u8 = null,

    pub fn deinit(self: *SessionSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.session_id);
        if (self.last_event_kind) |value| allocator.free(value);
        if (self.latest_execution_id) |value| allocator.free(value);
        if (self.latest_summary_text) |value| allocator.free(value);
        if (self.latest_assistant_response) |value| allocator.free(value);
        if (self.latest_provider_id) |value| allocator.free(value);
        if (self.latest_model) |value| allocator.free(value);
        if (self.latest_prompt_profile) |value| allocator.free(value);
        if (self.latest_response_mode) |value| allocator.free(value);
        if (self.latest_tool_id) |value| allocator.free(value);
        if (self.latest_tool_result_json) |value| allocator.free(value);
        if (self.last_error_code) |value| allocator.free(value);
    }
};

pub const RecentTurnSnapshot = struct {
    seq: u64,
    stream_seq: ?u64 = null,
    execution_id: ?[]u8 = null,
    ts_unix_ms: i64,
    provider_id: ?[]u8 = null,
    model: ?[]u8 = null,
    allow_provider_tools: ?bool = null,
    prompt_profile: ?[]u8 = null,
    response_mode: ?[]u8 = null,
    tool_id: ?[]u8 = null,
    tool_rounds: usize = 0,
    max_tool_rounds: usize = 0,
    memory_entries_used: usize = 0,
    provider_latency_ms: ?u64 = null,
    prompt_tokens: ?u64 = null,
    completion_tokens: ?u64 = null,
    total_tokens: ?u64 = null,
    error_code: ?[]u8 = null,

    pub fn deinit(self: *RecentTurnSnapshot, allocator: std.mem.Allocator) void {
        if (self.execution_id) |value| allocator.free(value);
        if (self.provider_id) |value| allocator.free(value);
        if (self.model) |value| allocator.free(value);
        if (self.prompt_profile) |value| allocator.free(value);
        if (self.response_mode) |value| allocator.free(value);
        if (self.tool_id) |value| allocator.free(value);
        if (self.error_code) |value| allocator.free(value);
    }
};

pub fn buildSnapshotMeta(allocator: std.mem.Allocator, session_id: []const u8, session: anytype) anyerror!SessionSnapshot {
    var latest_summary_text: ?[]u8 = null;
    var latest_assistant_response: ?[]u8 = null;
    var latest_provider_id: ?[]u8 = null;
    var latest_model: ?[]u8 = null;
    var latest_allow_provider_tools: ?bool = null;
    var latest_prompt_profile: ?[]u8 = null;
    var latest_response_mode: ?[]u8 = null;
    var latest_tool_id: ?[]u8 = null;
    var latest_tool_result_json: ?[]u8 = null;
    var latest_tool_rounds: usize = 0;
    var latest_max_tool_rounds: usize = 0;
    var latest_provider_latency_ms: ?u64 = null;
    var latest_memory_entries_used: usize = 0;
    var latest_provider_round_budget: usize = 0;
    var latest_provider_rounds_remaining: usize = 0;
    var latest_provider_attempt_budget: usize = 0;
    var latest_provider_attempts_remaining: usize = 0;
    var latest_tool_call_budget: usize = 0;
    var latest_tool_calls_remaining: usize = 0;
    var latest_provider_retry_budget: usize = 0;
    var latest_total_deadline_ms: u64 = 0;
    var latest_prompt_tokens: ?u64 = null;
    var latest_completion_tokens: ?u64 = null;
    var latest_total_tokens: ?u64 = null;
    var cumulative_prompt_tokens: u64 = 0;
    var cumulative_completion_tokens: u64 = 0;
    var cumulative_total_tokens: u64 = 0;
    var usage_turn_count: usize = 0;
    var last_error_code: ?[]u8 = null;
    var tool_trace_count: usize = 0;
    var turn_count: usize = 0;
    var assistant_response_count: usize = 0;
    var error_event_count: usize = 0;
    var stream_output_count: usize = 0;
    var first_stream_seq: u64 = 0;
    var last_stream_seq: u64 = 0;
    var replayable_event_count: usize = 0;
    var latest_execution_id: ?[]u8 = null;

    for (session.events.items) |event| {
        if (std.mem.startsWith(u8, event.kind, "tool.call.")) tool_trace_count += 1;
        if (std.mem.eql(u8, event.kind, "session.turn.completed")) turn_count += 1;
        if (std.mem.eql(u8, event.kind, "assistant.response")) assistant_response_count += 1;
        if (std.mem.eql(u8, event.kind, "error") or std.mem.eql(u8, event.kind, "session.turn.failed")) error_event_count += 1;
        if (std.mem.eql(u8, event.kind, "stream.output")) stream_output_count += 1;
        if (std.mem.eql(u8, event.kind, "session.turn.completed")) {
            if (json_fields.parseJsonUnsignedField(event.payload_json, "promptTokens")) |value| cumulative_prompt_tokens += value;
            if (json_fields.parseJsonUnsignedField(event.payload_json, "completionTokens")) |value| cumulative_completion_tokens += value;
            if (json_fields.parseJsonUnsignedField(event.payload_json, "totalTokens")) |value| cumulative_total_tokens += value;
            if (json_fields.parseJsonUnsignedField(event.payload_json, "promptTokens") != null or
                json_fields.parseJsonUnsignedField(event.payload_json, "completionTokens") != null or
                json_fields.parseJsonUnsignedField(event.payload_json, "totalTokens") != null)
            {
                usage_turn_count += 1;
            }
        }
        if (event.stream_seq) |stream_seq| {
            replayable_event_count += 1;
            if (first_stream_seq == 0) first_stream_seq = stream_seq;
            last_stream_seq = stream_seq;
        }
    }

    var index = session.events.items.len;
    while (index > 0) {
        index -= 1;
        const event = session.events.items[index];
        if (latest_summary_text == null and std.mem.eql(u8, event.kind, "session.summary")) latest_summary_text = try allocator.dupe(u8, event.payload_json);
        if (latest_assistant_response == null and std.mem.eql(u8, event.kind, "assistant.response")) latest_assistant_response = try allocator.dupe(u8, event.payload_json);
        if (latest_tool_result_json == null and std.mem.eql(u8, event.kind, "tool.result")) latest_tool_result_json = try allocator.dupe(u8, event.payload_json);
        if (latest_tool_id == null and std.mem.startsWith(u8, event.kind, "tool.call.")) latest_tool_id = try json_fields.cloneJsonStringField(allocator, event.payload_json, "toolId");
        if (latest_execution_id == null and event.execution_id != null) latest_execution_id = try allocator.dupe(u8, event.execution_id.?);
        if (last_error_code == null and (std.mem.eql(u8, event.kind, "error") or std.mem.eql(u8, event.kind, "tool.call.failed") or std.mem.eql(u8, event.kind, "tool.call.denied"))) {
            last_error_code = try json_fields.cloneJsonStringField(allocator, event.payload_json, "errorCode");
        }
        if (std.mem.eql(u8, event.kind, "session.turn.completed")) {
            if (latest_provider_id == null) latest_provider_id = try json_fields.cloneJsonStringField(allocator, event.payload_json, "providerId");
            if (latest_model == null) latest_model = try json_fields.cloneJsonStringField(allocator, event.payload_json, "model");
            if (latest_allow_provider_tools == null) latest_allow_provider_tools = json_fields.parseJsonBoolField(event.payload_json, "allowProviderTools");
            if (latest_prompt_profile == null) latest_prompt_profile = try json_fields.cloneJsonStringField(allocator, event.payload_json, "promptProfile");
            if (latest_response_mode == null) latest_response_mode = try json_fields.cloneJsonStringField(allocator, event.payload_json, "responseMode");
            if (latest_tool_id == null) latest_tool_id = try json_fields.cloneJsonStringField(allocator, event.payload_json, "toolId");
            if (latest_provider_latency_ms == null) latest_provider_latency_ms = json_fields.parseJsonUnsignedField(event.payload_json, "providerLatencyMs");
            if (latest_tool_rounds == 0) latest_tool_rounds = @intCast(json_fields.parseJsonUnsignedField(event.payload_json, "toolRounds") orelse 0);
            if (latest_max_tool_rounds == 0) latest_max_tool_rounds = @intCast(json_fields.parseJsonUnsignedField(event.payload_json, "maxToolRounds") orelse 0);
            if (latest_memory_entries_used == 0) latest_memory_entries_used = @intCast(json_fields.parseJsonUnsignedField(event.payload_json, "memoryEntriesUsed") orelse 0);
            if (latest_provider_round_budget == 0) latest_provider_round_budget = @intCast(json_fields.parseJsonUnsignedField(event.payload_json, "providerRoundBudget") orelse 0);
            if (latest_provider_rounds_remaining == 0) latest_provider_rounds_remaining = @intCast(json_fields.parseJsonUnsignedField(event.payload_json, "providerRoundsRemaining") orelse 0);
            if (latest_provider_attempt_budget == 0) latest_provider_attempt_budget = @intCast(json_fields.parseJsonUnsignedField(event.payload_json, "providerAttemptBudget") orelse 0);
            if (latest_provider_attempts_remaining == 0) latest_provider_attempts_remaining = @intCast(json_fields.parseJsonUnsignedField(event.payload_json, "providerAttemptsRemaining") orelse 0);
            if (latest_tool_call_budget == 0) latest_tool_call_budget = @intCast(json_fields.parseJsonUnsignedField(event.payload_json, "toolCallBudget") orelse 0);
            if (latest_tool_calls_remaining == 0) latest_tool_calls_remaining = @intCast(json_fields.parseJsonUnsignedField(event.payload_json, "toolCallsRemaining") orelse 0);
            if (latest_provider_retry_budget == 0) latest_provider_retry_budget = @intCast(json_fields.parseJsonUnsignedField(event.payload_json, "providerRetryBudget") orelse 0);
            if (latest_total_deadline_ms == 0) latest_total_deadline_ms = json_fields.parseJsonUnsignedField(event.payload_json, "totalDeadlineMs") orelse 0;
            if (latest_prompt_tokens == null) latest_prompt_tokens = json_fields.parseJsonUnsignedField(event.payload_json, "promptTokens");
            if (latest_completion_tokens == null) latest_completion_tokens = json_fields.parseJsonUnsignedField(event.payload_json, "completionTokens");
            if (latest_total_tokens == null) latest_total_tokens = json_fields.parseJsonUnsignedField(event.payload_json, "totalTokens");
        }
    }

    return .{
        .session_id = try allocator.dupe(u8, session_id),
        .event_count = session.events.items.len,
        .tool_trace_count = tool_trace_count,
        .turn_count = turn_count,
        .assistant_response_count = assistant_response_count,
        .error_event_count = error_event_count,
        .stream_output_count = stream_output_count,
        .first_event_seq = if (session.events.items.len > 0) session.events.items[0].seq else 0,
        .last_event_seq = if (session.events.items.len > 0) session.events.items[session.events.items.len - 1].seq else 0,
        .last_event_ts_unix_ms = if (session.events.items.len > 0) session.events.items[session.events.items.len - 1].ts_unix_ms else null,
        .first_stream_seq = first_stream_seq,
        .last_stream_seq = last_stream_seq,
        .replayable_event_count = replayable_event_count,
        .latest_execution_id = latest_execution_id,
        .last_event_kind = if (session.events.items.len > 0) try allocator.dupe(u8, session.events.items[session.events.items.len - 1].kind) else null,
        .latest_summary_text = latest_summary_text,
        .latest_assistant_response = latest_assistant_response,
        .latest_provider_id = latest_provider_id,
        .latest_model = latest_model,
        .latest_allow_provider_tools = latest_allow_provider_tools,
        .latest_prompt_profile = latest_prompt_profile,
        .latest_response_mode = latest_response_mode,
        .latest_tool_id = latest_tool_id,
        .latest_tool_result_json = latest_tool_result_json,
        .latest_tool_rounds = latest_tool_rounds,
        .latest_max_tool_rounds = latest_max_tool_rounds,
        .latest_provider_latency_ms = latest_provider_latency_ms,
        .latest_memory_entries_used = latest_memory_entries_used,
        .latest_provider_round_budget = latest_provider_round_budget,
        .latest_provider_rounds_remaining = latest_provider_rounds_remaining,
        .latest_provider_attempt_budget = latest_provider_attempt_budget,
        .latest_provider_attempts_remaining = latest_provider_attempts_remaining,
        .latest_tool_call_budget = latest_tool_call_budget,
        .latest_tool_calls_remaining = latest_tool_calls_remaining,
        .latest_provider_retry_budget = latest_provider_retry_budget,
        .latest_total_deadline_ms = latest_total_deadline_ms,
        .latest_prompt_tokens = latest_prompt_tokens,
        .latest_completion_tokens = latest_completion_tokens,
        .latest_total_tokens = latest_total_tokens,
        .cumulative_prompt_tokens = cumulative_prompt_tokens,
        .cumulative_completion_tokens = cumulative_completion_tokens,
        .cumulative_total_tokens = cumulative_total_tokens,
        .usage_turn_count = usage_turn_count,
        .last_error_code = last_error_code,
    };
}

pub fn buildRecentTurns(allocator: std.mem.Allocator, session: anytype, limit: usize) anyerror![]RecentTurnSnapshot {
    if (limit == 0) return allocator.alloc(RecentTurnSnapshot, 0);

    var completed_turn_count: usize = 0;
    for (session.events.items) |event| {
        if (std.mem.eql(u8, event.kind, "session.turn.completed")) completed_turn_count += 1;
    }

    const actual_count = @min(limit, completed_turn_count);
    const result = try allocator.alloc(RecentTurnSnapshot, actual_count);
    var initialized_from = actual_count;
    errdefer {
        for (result[initialized_from..actual_count]) |*turn| turn.deinit(allocator);
        allocator.free(result);
    }

    var remaining = actual_count;
    var index = session.events.items.len;
    while (index > 0 and remaining > 0) {
        index -= 1;
        const event = session.events.items[index];
        if (!std.mem.eql(u8, event.kind, "session.turn.completed")) continue;

        remaining -= 1;
        initialized_from = remaining;
        result[remaining] = try buildRecentTurnSnapshot(allocator, event);
    }

    return result;
}

fn buildRecentTurnSnapshot(allocator: std.mem.Allocator, event: anytype) anyerror!RecentTurnSnapshot {
    var turn_snapshot = RecentTurnSnapshot{
        .seq = event.seq,
        .stream_seq = event.stream_seq,
        .execution_id = if (event.execution_id) |value| try allocator.dupe(u8, value) else null,
        .ts_unix_ms = event.ts_unix_ms,
    };
    errdefer turn_snapshot.deinit(allocator);

    turn_snapshot.provider_id = try json_fields.cloneJsonStringField(allocator, event.payload_json, "providerId");
    turn_snapshot.model = try json_fields.cloneJsonStringField(allocator, event.payload_json, "model");
    turn_snapshot.allow_provider_tools = json_fields.parseJsonBoolField(event.payload_json, "allowProviderTools");
    turn_snapshot.prompt_profile = try json_fields.cloneJsonStringField(allocator, event.payload_json, "promptProfile");
    turn_snapshot.response_mode = try json_fields.cloneJsonStringField(allocator, event.payload_json, "responseMode");
    turn_snapshot.tool_id = try json_fields.cloneJsonStringField(allocator, event.payload_json, "toolId");
    turn_snapshot.tool_rounds = @intCast(json_fields.parseJsonUnsignedField(event.payload_json, "toolRounds") orelse 0);
    turn_snapshot.max_tool_rounds = @intCast(json_fields.parseJsonUnsignedField(event.payload_json, "maxToolRounds") orelse 0);
    turn_snapshot.memory_entries_used = @intCast(json_fields.parseJsonUnsignedField(event.payload_json, "memoryEntriesUsed") orelse 0);
    turn_snapshot.provider_latency_ms = json_fields.parseJsonUnsignedField(event.payload_json, "providerLatencyMs");
    turn_snapshot.prompt_tokens = json_fields.parseJsonUnsignedField(event.payload_json, "promptTokens");
    turn_snapshot.completion_tokens = json_fields.parseJsonUnsignedField(event.payload_json, "completionTokens");
    turn_snapshot.total_tokens = json_fields.parseJsonUnsignedField(event.payload_json, "totalTokens");
    turn_snapshot.error_code = try json_fields.cloneJsonStringField(allocator, event.payload_json, "errorCode");
    return turn_snapshot;
}
