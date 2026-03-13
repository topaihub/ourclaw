const std = @import("std");
const framework = @import("framework");
const session_state = @import("session_state.zig");

pub const EventBus = framework.EventBus;
pub const Observer = framework.Observer;
pub const SessionStore = session_state.SessionStore;

pub const Projector = struct {
    ptr: *anyopaque,
    on_event: *const fn (
        ptr: *anyopaque,
        seq: u64,
        execution_id: ?[]const u8,
        session_id: []const u8,
        kind: []const u8,
        payload_json: []const u8,
    ) anyerror!void,
};

pub const StreamOutput = struct {
    allocator: std.mem.Allocator,
    session_store: *SessionStore,
    observer: ?Observer = null,
    event_bus: ?EventBus = null,
    projectors: std.ArrayListUnmanaged(ProjectorRegistration) = .empty,
    next_projector_id: u64 = 1,
    mutex: std.Thread.Mutex = .{},

    const Self = @This();

    const ProjectorRegistration = struct {
        id: u64,
        projector: Projector,
    };

    pub fn init(allocator: std.mem.Allocator, session_store: *SessionStore, observer: ?Observer, event_bus: ?EventBus) Self {
        return .{
            .allocator = allocator,
            .session_store = session_store,
            .observer = observer,
            .event_bus = event_bus,
        };
    }

    pub const ProjectorGuard = struct {
        output: *StreamOutput,
        id: u64,

        pub fn deinit(self: *ProjectorGuard) void {
            self.output.mutex.lock();
            defer self.output.mutex.unlock();

            for (self.output.projectors.items, 0..) |registration, index| {
                if (registration.id != self.id) continue;
                _ = self.output.projectors.orderedRemove(index);
                break;
            }
        }
    };

    pub fn beginProjection(self: *Self, projector: Projector) anyerror!ProjectorGuard {
        self.mutex.lock();
        defer self.mutex.unlock();

        const id = self.next_projector_id;
        self.next_projector_id += 1;
        try self.projectors.append(self.allocator, .{ .id = id, .projector = projector });
        return .{ .output = self, .id = id };
    }

    pub fn publish(self: *Self, session_id: []const u8, kind: []const u8, payload_json: []const u8) anyerror!u64 {
        return self.publishWithExecution(session_id, null, kind, payload_json);
    }

    pub fn publishWithExecution(
        self: *Self,
        session_id: []const u8,
        execution_id: ?[]const u8,
        kind: []const u8,
        payload_json: []const u8,
    ) anyerror!u64 {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.session_store.appendEvent(session_id, kind, payload_json);

        const envelope = if (execution_id) |actual_execution_id|
            try std.fmt.allocPrint(
                self.allocator,
                "{{\"executionId\":\"{s}\",\"sessionId\":\"{s}\",\"kind\":\"{s}\",\"payload\":{s}}}",
                .{ actual_execution_id, session_id, kind, payload_json },
            )
        else
            try std.fmt.allocPrint(
                self.allocator,
                "{{\"sessionId\":\"{s}\",\"kind\":\"{s}\",\"payload\":{s}}}",
                .{ session_id, kind, payload_json },
            );
        defer self.allocator.free(envelope);

        var seq: u64 = 0;
        if (self.event_bus) |event_bus| {
            seq = try event_bus.publish("stream.output", envelope);
        }
        for (self.projectors.items) |registration| {
            try registration.projector.on_event(
                registration.projector.ptr,
                seq,
                execution_id,
                session_id,
                kind,
                payload_json,
            );
        }
        if (self.observer) |observer| {
            try observer.record("stream.output", envelope);
        }
        return seq;
    }

    pub fn deinit(self: *Self) void {
        self.projectors.deinit(self.allocator);
    }
};

test "stream output stores session events and emits runtime event" {
    var store = session_state.SessionStore.init(std.testing.allocator);
    defer store.deinit();
    var event_bus = framework.MemoryEventBus.init(std.testing.allocator);
    defer event_bus.deinit();

    var output = StreamOutput.init(std.testing.allocator, &store, null, event_bus.asEventBus());
    _ = try output.publish("sess_01", "text.delta", "{\"text\":\"hello\"}");
    output.deinit();

    try std.testing.expectEqual(@as(usize, 1), store.find("sess_01").?.events.items.len);
    try std.testing.expectEqual(@as(usize, 1), event_bus.count());
}
