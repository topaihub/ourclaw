const std = @import("std");

pub const PairingState = enum {
    pending,
    approved,
    rejected,

    pub fn asText(self: PairingState) []const u8 {
        return switch (self) {
            .pending => "pending",
            .approved => "approved",
            .rejected => "rejected",
        };
    }
};

pub const PairingRequest = struct {
    id: []u8,
    channel: []u8,
    requester: []u8,
    code: []u8,
    state: PairingState = .pending,
    requested_at_ms: i64,
    decided_at_ms: ?i64 = null,

    pub fn deinit(self: *PairingRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.channel);
        allocator.free(self.requester);
        allocator.free(self.code);
    }
};

pub const PairingDecision = struct {
    changed: bool,
    state: PairingState,
};

pub const PairingRegistry = struct {
    allocator: std.mem.Allocator,
    requests: std.ArrayListUnmanaged(PairingRequest) = .empty,
    next_id: usize = 1,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.requests.items) |*request| request.deinit(self.allocator);
        self.requests.deinit(self.allocator);
    }

    pub fn create(self: *Self, channel: []const u8, requester: []const u8, code: []const u8) anyerror!void {
        const id = try std.fmt.allocPrint(self.allocator, "pair_{d}", .{self.next_id});
        errdefer self.allocator.free(id);
        self.next_id += 1;
        try self.requests.append(self.allocator, .{
            .id = id,
            .channel = try self.allocator.dupe(u8, channel),
            .requester = try self.allocator.dupe(u8, requester),
            .code = try self.allocator.dupe(u8, code),
            .requested_at_ms = std.time.milliTimestamp(),
        });
    }

    pub fn count(self: *const Self) usize {
        return self.requests.items.len;
    }

    pub fn pendingCount(self: *const Self) usize {
        var total: usize = 0;
        for (self.requests.items) |request| {
            if (request.state == .pending) total += 1;
        }
        return total;
    }

    pub fn items(self: *const Self) []const PairingRequest {
        return self.requests.items;
    }

    pub fn approve(self: *Self, id: []const u8) PairingDecision {
        return self.transition(id, .approved);
    }

    pub fn reject(self: *Self, id: []const u8) PairingDecision {
        return self.transition(id, .rejected);
    }

    fn transition(self: *Self, id: []const u8, next: PairingState) PairingDecision {
        for (self.requests.items) |*request| {
            if (!std.mem.eql(u8, request.id, id)) continue;
            if (request.state == next) return .{ .changed = false, .state = request.state };
            request.state = next;
            request.decided_at_ms = std.time.milliTimestamp();
            return .{ .changed = true, .state = request.state };
        }
        return .{ .changed = false, .state = .pending };
    }
};

test "pairing registry creates and approves requests" {
    var registry = PairingRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.create("telegram", "user_a", "123456");
    try std.testing.expectEqual(@as(usize, 1), registry.count());
    try std.testing.expectEqual(@as(usize, 1), registry.pendingCount());
    const decision = registry.approve("pair_1");
    try std.testing.expect(decision.changed);
    try std.testing.expectEqual(PairingState.approved, decision.state);
    try std.testing.expectEqual(@as(usize, 0), registry.pendingCount());
}
