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
    last_event_kind: ?[]u8 = null,
    latest_summary_text: ?[]u8 = null,

    pub fn deinit(self: *SessionSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.session_id);
        if (self.last_event_kind) |value| allocator.free(value);
        if (self.latest_summary_text) |value| allocator.free(value);
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
        var index = session.events.items.len;
        while (index > 0) {
            index -= 1;
            const event = session.events.items[index];
            if (std.mem.eql(u8, event.kind, "session.summary")) {
                latest_summary_text = try allocator.dupe(u8, event.payload_json);
                break;
            }
        }

        return .{
            .session_id = try allocator.dupe(u8, session.id),
            .event_count = session.events.items.len,
            .last_event_kind = if (session.events.items.len > 0)
                try allocator.dupe(u8, session.events.items[session.events.items.len - 1].kind)
            else
                null,
            .latest_summary_text = latest_summary_text,
        };
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
