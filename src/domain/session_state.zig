const std = @import("std");

pub const SessionEvent = struct {
    kind: []u8,
    payload_json: []u8,

    pub fn clone(self: SessionEvent, allocator: std.mem.Allocator) anyerror!SessionEvent {
        return .{
            .kind = try allocator.dupe(u8, self.kind),
            .payload_json = try allocator.dupe(u8, self.payload_json),
        };
    }

    pub fn deinit(self: *SessionEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.payload_json);
    }
};

pub const SessionRecord = struct {
    id: []u8,
    events: std.ArrayListUnmanaged(SessionEvent) = .empty,

    pub fn deinit(self: *SessionRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        for (self.events.items) |*event| event.deinit(allocator);
        self.events.deinit(allocator);
    }
};

pub const SessionSnapshot = struct {
    session_id: []u8,
    event_count: usize,
    tool_trace_count: usize = 0,
    last_event_kind: ?[]u8 = null,
    latest_summary_text: ?[]u8 = null,
    latest_assistant_response: ?[]u8 = null,
    latest_provider_id: ?[]u8 = null,
    latest_model: ?[]u8 = null,
    latest_tool_id: ?[]u8 = null,
    latest_tool_result_json: ?[]u8 = null,
    latest_tool_rounds: usize = 0,
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
    last_error_code: ?[]u8 = null,

    pub fn deinit(self: *SessionSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.session_id);
        if (self.last_event_kind) |value| allocator.free(value);
        if (self.latest_summary_text) |value| allocator.free(value);
        if (self.latest_assistant_response) |value| allocator.free(value);
        if (self.latest_provider_id) |value| allocator.free(value);
        if (self.latest_model) |value| allocator.free(value);
        if (self.latest_tool_id) |value| allocator.free(value);
        if (self.latest_tool_result_json) |value| allocator.free(value);
        if (self.last_error_code) |value| allocator.free(value);
    }
};

pub const SessionStore = struct {
    allocator: std.mem.Allocator,
    sessions: std.ArrayListUnmanaged(SessionRecord) = .empty,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.sessions.items) |*session| session.deinit(self.allocator);
        self.sessions.deinit(self.allocator);
    }

    pub fn appendEvent(self: *Self, session_id: []const u8, kind: []const u8, payload_json: []const u8) anyerror!void {
        const session = try self.ensureSession(session_id);
        try session.events.append(self.allocator, .{
            .kind = try self.allocator.dupe(u8, kind),
            .payload_json = try self.allocator.dupe(u8, payload_json),
        });
    }

    pub fn find(self: *const Self, session_id: []const u8) ?*const SessionRecord {
        for (self.sessions.items) |*session| {
            if (std.mem.eql(u8, session.id, session_id)) return session;
        }
        return null;
    }

    pub fn count(self: *const Self) usize {
        return self.sessions.items.len;
    }

    pub fn countEvents(self: *const Self, session_id: []const u8) usize {
        const session = self.find(session_id) orelse return 0;
        return session.events.items.len;
    }

    pub fn snapshot(self: *const Self, allocator: std.mem.Allocator, session_id: []const u8) anyerror![]SessionEvent {
        const session = self.find(session_id) orelse return allocator.alloc(SessionEvent, 0);
        return cloneEvents(allocator, session.events.items, 0);
    }

    pub fn snapshotSince(self: *const Self, allocator: std.mem.Allocator, session_id: []const u8, start_index: usize) anyerror![]SessionEvent {
        const session = self.find(session_id) orelse return allocator.alloc(SessionEvent, 0);
        return cloneEvents(allocator, session.events.items, start_index);
    }

    pub fn snapshotMeta(self: *const Self, allocator: std.mem.Allocator, session_id: []const u8) anyerror!SessionSnapshot {
        const session = self.find(session_id) orelse return .{
            .session_id = try allocator.dupe(u8, session_id),
            .event_count = 0,
        };

        var latest_summary_text: ?[]u8 = null;
        var latest_assistant_response: ?[]u8 = null;
        var latest_provider_id: ?[]u8 = null;
        var latest_model: ?[]u8 = null;
        var latest_tool_id: ?[]u8 = null;
        var latest_tool_result_json: ?[]u8 = null;
        var latest_tool_rounds: usize = 0;
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
        var last_error_code: ?[]u8 = null;
        var tool_trace_count: usize = 0;

        for (session.events.items) |event| {
            if (std.mem.startsWith(u8, event.kind, "tool.call.")) {
                tool_trace_count += 1;
            }
        }

        var index = session.events.items.len;
        while (index > 0) {
            index -= 1;
            const event = session.events.items[index];
            if (latest_summary_text == null and std.mem.eql(u8, event.kind, "session.summary")) {
                latest_summary_text = try allocator.dupe(u8, event.payload_json);
            }
            if (latest_assistant_response == null and std.mem.eql(u8, event.kind, "assistant.response")) {
                latest_assistant_response = try allocator.dupe(u8, event.payload_json);
            }
            if (latest_tool_result_json == null and std.mem.eql(u8, event.kind, "tool.result")) {
                latest_tool_result_json = try allocator.dupe(u8, event.payload_json);
            }
            if (latest_tool_id == null and std.mem.startsWith(u8, event.kind, "tool.call.")) {
                latest_tool_id = try cloneJsonStringField(allocator, event.payload_json, "toolId");
            }
            if (last_error_code == null and (std.mem.eql(u8, event.kind, "error") or std.mem.eql(u8, event.kind, "tool.call.failed") or std.mem.eql(u8, event.kind, "tool.call.denied"))) {
                last_error_code = try cloneJsonStringField(allocator, event.payload_json, "errorCode");
            }
            if (std.mem.eql(u8, event.kind, "session.turn.completed")) {
                if (latest_provider_id == null) latest_provider_id = try cloneJsonStringField(allocator, event.payload_json, "providerId");
                if (latest_model == null) latest_model = try cloneJsonStringField(allocator, event.payload_json, "model");
                if (latest_tool_id == null) latest_tool_id = try cloneJsonStringField(allocator, event.payload_json, "toolId");
                if (latest_provider_latency_ms == null) latest_provider_latency_ms = parseJsonUnsignedField(event.payload_json, "providerLatencyMs");
                if (latest_tool_rounds == 0) latest_tool_rounds = @intCast(parseJsonUnsignedField(event.payload_json, "toolRounds") orelse 0);
                if (latest_memory_entries_used == 0) latest_memory_entries_used = @intCast(parseJsonUnsignedField(event.payload_json, "memoryEntriesUsed") orelse 0);
                if (latest_provider_round_budget == 0) latest_provider_round_budget = @intCast(parseJsonUnsignedField(event.payload_json, "providerRoundBudget") orelse 0);
                if (latest_provider_rounds_remaining == 0) latest_provider_rounds_remaining = @intCast(parseJsonUnsignedField(event.payload_json, "providerRoundsRemaining") orelse 0);
                if (latest_provider_attempt_budget == 0) latest_provider_attempt_budget = @intCast(parseJsonUnsignedField(event.payload_json, "providerAttemptBudget") orelse 0);
                if (latest_provider_attempts_remaining == 0) latest_provider_attempts_remaining = @intCast(parseJsonUnsignedField(event.payload_json, "providerAttemptsRemaining") orelse 0);
                if (latest_tool_call_budget == 0) latest_tool_call_budget = @intCast(parseJsonUnsignedField(event.payload_json, "toolCallBudget") orelse 0);
                if (latest_tool_calls_remaining == 0) latest_tool_calls_remaining = @intCast(parseJsonUnsignedField(event.payload_json, "toolCallsRemaining") orelse 0);
                if (latest_provider_retry_budget == 0) latest_provider_retry_budget = @intCast(parseJsonUnsignedField(event.payload_json, "providerRetryBudget") orelse 0);
                if (latest_total_deadline_ms == 0) latest_total_deadline_ms = parseJsonUnsignedField(event.payload_json, "totalDeadlineMs") orelse 0;
            }
        }

        return .{
            .session_id = try allocator.dupe(u8, session.id),
            .event_count = session.events.items.len,
            .tool_trace_count = tool_trace_count,
            .last_event_kind = if (session.events.items.len > 0)
                try allocator.dupe(u8, session.events.items[session.events.items.len - 1].kind)
            else
                null,
            .latest_summary_text = latest_summary_text,
            .latest_assistant_response = latest_assistant_response,
            .latest_provider_id = latest_provider_id,
            .latest_model = latest_model,
            .latest_tool_id = latest_tool_id,
            .latest_tool_result_json = latest_tool_result_json,
            .latest_tool_rounds = latest_tool_rounds,
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
            .last_error_code = last_error_code,
        };
    }

    fn cloneJsonStringField(allocator: std.mem.Allocator, payload_json: []const u8, key: []const u8) anyerror!?[]u8 {
        var pattern_buf: [64]u8 = undefined;
        const pattern = try std.fmt.bufPrint(&pattern_buf, "\"{s}\":\"", .{key});
        const start = std.mem.indexOf(u8, payload_json, pattern) orelse return null;
        const value_start = start + pattern.len;
        const suffix = payload_json[value_start..];
        const value_end_rel = std.mem.indexOfScalar(u8, suffix, '"') orelse return null;
        const cloned = try allocator.dupe(u8, suffix[0..value_end_rel]);
        return cloned;
    }

    fn parseJsonUnsignedField(payload_json: []const u8, key: []const u8) ?u64 {
        var pattern_buf: [64]u8 = undefined;
        const pattern = std.fmt.bufPrint(&pattern_buf, "\"{s}\":", .{key}) catch return null;
        const start = std.mem.indexOf(u8, payload_json, pattern) orelse return null;
        const value_start = start + pattern.len;
        const suffix = payload_json[value_start..];
        var value_end: usize = 0;
        while (value_end < suffix.len and suffix[value_end] >= '0' and suffix[value_end] <= '9') : (value_end += 1) {}
        if (value_end == 0) return null;
        return std.fmt.parseUnsigned(u64, suffix[0..value_end], 10) catch null;
    }

    fn cloneEvents(allocator: std.mem.Allocator, source: []const SessionEvent, start_index: usize) anyerror![]SessionEvent {
        const bounded_start = @min(start_index, source.len);
        const events = try allocator.alloc(SessionEvent, source.len - bounded_start);
        errdefer allocator.free(events);

        for (source[bounded_start..], 0..) |event, index| {
            events[index] = try event.clone(allocator);
        }
        return events;
    }

    fn ensureSession(self: *Self, session_id: []const u8) anyerror!*SessionRecord {
        for (self.sessions.items) |*session| {
            if (std.mem.eql(u8, session.id, session_id)) return session;
        }
        try self.sessions.append(self.allocator, .{ .id = try self.allocator.dupe(u8, session_id) });
        return &self.sessions.items[self.sessions.items.len - 1];
    }
};

test "session store keeps per-session events" {
    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();
    try store.appendEvent("sess_01", "tool.result", "{\"ok\":true}");
    try std.testing.expectEqual(@as(usize, 1), store.count());
    try std.testing.expectEqual(@as(usize, 1), store.find("sess_01").?.events.items.len);
}

test "session store builds snapshot metadata" {
    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();
    try store.appendEvent("sess_meta", "user.prompt", "{\"text\":\"hello\"}");
    try store.appendEvent("sess_meta", "session.summary", "condensed summary");

    var snapshot = try store.snapshotMeta(std.testing.allocator, "sess_meta");
    defer snapshot.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), snapshot.event_count);
    try std.testing.expectEqualStrings("session.summary", snapshot.last_event_kind.?);
    try std.testing.expectEqualStrings("condensed summary", snapshot.latest_summary_text.?);
}

test "session store tracks latest turn metadata and tool trace summary" {
    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();
    try store.appendEvent("sess_turn", "tool.call.started", "{\"toolId\":\"echo\"}");
    try store.appendEvent("sess_turn", "tool.result", "{\"ok\":true}");
    try store.appendEvent("sess_turn", "assistant.response", "hello back");
    try store.appendEvent("sess_turn", "session.turn.completed", "{\"providerId\":\"mock_openai\",\"model\":\"gpt-4o-mini\",\"toolId\":\"echo\",\"toolRounds\":1,\"providerRoundBudget\":4,\"providerRoundsRemaining\":2,\"providerAttemptBudget\":8,\"providerAttemptsRemaining\":6,\"toolCallBudget\":3,\"toolCallsRemaining\":1,\"providerRetryBudget\":1,\"totalDeadlineMs\":250,\"providerLatencyMs\":42,\"memoryEntriesUsed\":3}");

    var snapshot = try store.snapshotMeta(std.testing.allocator, "sess_turn");
    defer snapshot.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 4), snapshot.event_count);
    try std.testing.expectEqual(@as(usize, 1), snapshot.tool_trace_count);
    try std.testing.expectEqualStrings("hello back", snapshot.latest_assistant_response.?);
    try std.testing.expectEqualStrings("mock_openai", snapshot.latest_provider_id.?);
    try std.testing.expectEqualStrings("gpt-4o-mini", snapshot.latest_model.?);
    try std.testing.expectEqualStrings("echo", snapshot.latest_tool_id.?);
    try std.testing.expectEqual(@as(usize, 1), snapshot.latest_tool_rounds);
    try std.testing.expectEqual(@as(u64, 42), snapshot.latest_provider_latency_ms.?);
    try std.testing.expectEqual(@as(usize, 3), snapshot.latest_memory_entries_used);
    try std.testing.expectEqual(@as(usize, 4), snapshot.latest_provider_round_budget);
    try std.testing.expectEqual(@as(usize, 2), snapshot.latest_provider_rounds_remaining);
    try std.testing.expectEqual(@as(usize, 8), snapshot.latest_provider_attempt_budget);
    try std.testing.expectEqual(@as(usize, 6), snapshot.latest_provider_attempts_remaining);
    try std.testing.expectEqual(@as(usize, 3), snapshot.latest_tool_call_budget);
    try std.testing.expectEqual(@as(usize, 1), snapshot.latest_tool_calls_remaining);
    try std.testing.expectEqual(@as(usize, 1), snapshot.latest_provider_retry_budget);
    try std.testing.expectEqual(@as(u64, 250), snapshot.latest_total_deadline_ms);
}
