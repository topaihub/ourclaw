const std = @import("std");
const snapshot_helper = @import("session_state_snapshot.zig");

pub const SessionEvent = struct {
    seq: u64,
    stream_seq: ?u64 = null,
    execution_id: ?[]u8 = null,
    ts_unix_ms: i64,
    kind: []u8,
    payload_json: []u8,

    pub fn clone(self: SessionEvent, allocator: std.mem.Allocator) anyerror!SessionEvent {
        return .{
            .seq = self.seq,
            .stream_seq = self.stream_seq,
            .execution_id = if (self.execution_id) |value| try allocator.dupe(u8, value) else null,
            .ts_unix_ms = self.ts_unix_ms,
            .kind = try allocator.dupe(u8, self.kind),
            .payload_json = try allocator.dupe(u8, self.payload_json),
        };
    }

    pub fn deinit(self: *SessionEvent, allocator: std.mem.Allocator) void {
        if (self.execution_id) |value| allocator.free(value);
        allocator.free(self.kind);
        allocator.free(self.payload_json);
    }
};

pub const SessionRecord = struct {
    id: []u8,
    next_seq: u64 = 1,
    events: std.ArrayListUnmanaged(SessionEvent) = .empty,

    pub fn deinit(self: *SessionRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        for (self.events.items) |*event| event.deinit(allocator);
        self.events.deinit(allocator);
    }
};

pub const SessionSnapshot = snapshot_helper.SessionSnapshot;
pub const RecentTurnSnapshot = snapshot_helper.RecentTurnSnapshot;

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
        return self.appendEventWithMeta(session_id, null, null, kind, payload_json);
    }

    pub fn appendEventWithMeta(self: *Self, session_id: []const u8, execution_id: ?[]const u8, stream_seq: ?u64, kind: []const u8, payload_json: []const u8) anyerror!void {
        const session = try self.ensureSession(session_id);
        try session.events.append(self.allocator, .{
            .seq = session.next_seq,
            .stream_seq = stream_seq,
            .execution_id = if (execution_id) |value| try self.allocator.dupe(u8, value) else null,
            .ts_unix_ms = std.time.milliTimestamp(),
            .kind = try self.allocator.dupe(u8, kind),
            .payload_json = try self.allocator.dupe(u8, payload_json),
        });
        session.next_seq += 1;
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

    pub fn snapshotAfterSeq(self: *const Self, allocator: std.mem.Allocator, session_id: []const u8, after_seq: u64) anyerror![]SessionEvent {
        const session = self.find(session_id) orelse return allocator.alloc(SessionEvent, 0);
        var start_index: usize = session.events.items.len;
        for (session.events.items, 0..) |event, index| {
            if (event.seq > after_seq) {
                start_index = index;
                break;
            }
        }
        return cloneEvents(allocator, session.events.items, start_index);
    }

    pub fn snapshotAfterStreamSeq(self: *const Self, allocator: std.mem.Allocator, session_id: []const u8, after_seq: u64) anyerror![]SessionEvent {
        const session = self.find(session_id) orelse return allocator.alloc(SessionEvent, 0);
        var start_index: usize = session.events.items.len;
        for (session.events.items, 0..) |event, index| {
            if (event.stream_seq != null and event.stream_seq.? > after_seq) {
                start_index = index;
                break;
            }
        }
        return cloneEvents(allocator, session.events.items, start_index);
    }

    pub fn snapshotMeta(self: *const Self, allocator: std.mem.Allocator, session_id: []const u8) anyerror!SessionSnapshot {
        const session = self.find(session_id) orelse return .{
            .session_id = try allocator.dupe(u8, session_id),
            .event_count = 0,
        };
        return snapshot_helper.buildSnapshotMeta(allocator, session_id, session);
    }

    pub fn recentTurns(self: *const Self, allocator: std.mem.Allocator, session_id: []const u8, limit: usize) anyerror![]RecentTurnSnapshot {
        const session = self.find(session_id) orelse return allocator.alloc(RecentTurnSnapshot, 0);
        return snapshot_helper.buildRecentTurns(allocator, session, limit);
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
    try std.testing.expectEqual(@as(u64, 1), store.find("sess_01").?.events.items[0].seq);
    try std.testing.expect(store.find("sess_01").?.events.items[0].stream_seq == null);
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
    try std.testing.expectEqual(@as(u64, 1), snapshot.first_event_seq);
    try std.testing.expectEqual(@as(u64, 2), snapshot.last_event_seq);
}

test "session store tracks latest turn metadata and tool trace summary" {
    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();
    try store.appendEvent("sess_turn", "tool.call.started", "{\"toolId\":\"echo\"}");
    try store.appendEvent("sess_turn", "tool.result", "{\"ok\":true}");
    try store.appendEvent("sess_turn", "assistant.response", "hello back");
    try store.appendEvent("sess_turn", "session.turn.completed", "{\"providerId\":\"mock_openai\",\"model\":\"gpt-4o-mini\",\"allowProviderTools\":true,\"promptProfile\":\"default\",\"responseMode\":\"standard\",\"toolId\":\"echo\",\"toolRounds\":1,\"maxToolRounds\":4,\"providerRoundBudget\":4,\"providerRoundsRemaining\":2,\"providerAttemptBudget\":8,\"providerAttemptsRemaining\":6,\"toolCallBudget\":3,\"toolCallsRemaining\":1,\"providerRetryBudget\":1,\"totalDeadlineMs\":250,\"providerLatencyMs\":42,\"memoryEntriesUsed\":3,\"promptTokens\":12,\"completionTokens\":8,\"totalTokens\":20}");

    var snapshot = try store.snapshotMeta(std.testing.allocator, "sess_turn");
    defer snapshot.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 4), snapshot.event_count);
    try std.testing.expectEqual(@as(usize, 1), snapshot.tool_trace_count);
    try std.testing.expectEqual(@as(usize, 1), snapshot.turn_count);
    try std.testing.expectEqual(@as(usize, 1), snapshot.assistant_response_count);
    try std.testing.expectEqualStrings("hello back", snapshot.latest_assistant_response.?);
    try std.testing.expectEqualStrings("mock_openai", snapshot.latest_provider_id.?);
    try std.testing.expectEqualStrings("gpt-4o-mini", snapshot.latest_model.?);
    try std.testing.expectEqual(true, snapshot.latest_allow_provider_tools.?);
    try std.testing.expectEqualStrings("default", snapshot.latest_prompt_profile.?);
    try std.testing.expectEqualStrings("standard", snapshot.latest_response_mode.?);
    try std.testing.expectEqualStrings("echo", snapshot.latest_tool_id.?);
    try std.testing.expectEqual(@as(usize, 1), snapshot.latest_tool_rounds);
    try std.testing.expectEqual(@as(usize, 4), snapshot.latest_max_tool_rounds);
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
    try std.testing.expectEqual(@as(u64, 12), snapshot.latest_prompt_tokens.?);
    try std.testing.expectEqual(@as(u64, 8), snapshot.latest_completion_tokens.?);
    try std.testing.expectEqual(@as(u64, 20), snapshot.latest_total_tokens.?);
    try std.testing.expectEqual(@as(u64, 12), snapshot.cumulative_prompt_tokens);
    try std.testing.expectEqual(@as(u64, 8), snapshot.cumulative_completion_tokens);
    try std.testing.expectEqual(@as(u64, 20), snapshot.cumulative_total_tokens);
    try std.testing.expectEqual(@as(usize, 1), snapshot.usage_turn_count);
}

test "session store accumulates usage across completed turns" {
    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();
    try store.appendEvent("sess_usage", "session.turn.completed", "{\"providerId\":\"mock_openai\",\"promptTokens\":12,\"completionTokens\":8,\"totalTokens\":20}");
    try store.appendEvent("sess_usage", "session.turn.completed", "{\"providerId\":\"mock_openai\",\"promptTokens\":5,\"completionTokens\":7,\"totalTokens\":12}");

    var snapshot = try store.snapshotMeta(std.testing.allocator, "sess_usage");
    defer snapshot.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), snapshot.turn_count);
    try std.testing.expectEqual(@as(usize, 2), snapshot.usage_turn_count);
    try std.testing.expectEqual(@as(u64, 17), snapshot.cumulative_prompt_tokens);
    try std.testing.expectEqual(@as(u64, 15), snapshot.cumulative_completion_tokens);
    try std.testing.expectEqual(@as(u64, 32), snapshot.cumulative_total_tokens);
    try std.testing.expectEqual(@as(u64, 5), snapshot.latest_prompt_tokens.?);
    try std.testing.expectEqual(@as(u64, 7), snapshot.latest_completion_tokens.?);
    try std.testing.expectEqual(@as(u64, 12), snapshot.latest_total_tokens.?);
}

test "session store can replay after seq" {
    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();
    try store.appendEventWithMeta("sess_replay", "exec_1", 5, "user.prompt", "{\"text\":\"hello\"}");
    try store.appendEventWithMeta("sess_replay", "exec_1", 6, "assistant.response", "{\"text\":\"world\"}");
    try store.appendEventWithMeta("sess_replay", "exec_1", 7, "session.turn.completed", "{\"providerId\":\"openai\"}");

    const replay = try store.snapshotAfterStreamSeq(std.testing.allocator, "sess_replay", 5);
    defer {
        for (replay) |*event| event.deinit(std.testing.allocator);
        std.testing.allocator.free(replay);
    }
    try std.testing.expectEqual(@as(usize, 2), replay.len);
    try std.testing.expectEqual(@as(?u64, 6), replay[0].stream_seq);
    try std.testing.expectEqualStrings("exec_1", replay[0].execution_id.?);
}

test "session store returns recent completed turns in chronological order" {
    var store = SessionStore.init(std.testing.allocator);
    defer store.deinit();
    try store.appendEventWithMeta("sess_recent_turns", "exec_1", 1, "session.turn.completed", "{\"providerId\":\"mock_a\",\"model\":\"model-a\",\"promptTokens\":10,\"completionTokens\":5,\"totalTokens\":15}");
    try store.appendEventWithMeta("sess_recent_turns", "exec_2", 2, "session.turn.completed", "{\"providerId\":\"mock_b\",\"model\":\"model-b\",\"promptTokens\":20,\"completionTokens\":7,\"totalTokens\":27}");
    try store.appendEventWithMeta("sess_recent_turns", "exec_3", 3, "session.turn.completed", "{\"providerId\":\"mock_c\",\"model\":\"model-c\",\"promptTokens\":30,\"completionTokens\":9,\"totalTokens\":39}");

    const turns = try store.recentTurns(std.testing.allocator, "sess_recent_turns", 2);
    defer {
        for (turns) |*turn| turn.deinit(std.testing.allocator);
        std.testing.allocator.free(turns);
    }

    try std.testing.expectEqual(@as(usize, 2), turns.len);
    try std.testing.expectEqual(@as(u64, 2), turns[0].seq);
    try std.testing.expectEqual(@as(u64, 3), turns[1].seq);
    try std.testing.expectEqualStrings("exec_2", turns[0].execution_id.?);
    try std.testing.expectEqualStrings("exec_3", turns[1].execution_id.?);
    try std.testing.expectEqual(@as(u64, 20), turns[0].prompt_tokens.?);
    try std.testing.expectEqual(@as(u64, 39), turns[1].total_tokens.?);
}
