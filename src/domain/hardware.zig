const std = @import("std");

pub const HardwareNode = struct {
    id: []u8,
    label: []u8,
    registered_at_ms: i64,

    pub fn deinit(self: *HardwareNode, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.label);
    }
};

pub const HardwareRegistry = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayListUnmanaged(HardwareNode) = .empty,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.nodes.items) |*node| node.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
    }

    pub fn register(self: *Self, id: []const u8, label: []const u8) anyerror!void {
        for (self.nodes.items) |node| {
            if (std.mem.eql(u8, node.id, id)) return error.DuplicateHardwareNode;
        }
        try self.nodes.append(self.allocator, .{
            .id = try self.allocator.dupe(u8, id),
            .label = try self.allocator.dupe(u8, label),
            .registered_at_ms = std.time.milliTimestamp(),
        });
    }

    pub fn count(self: *const Self) usize {
        return self.nodes.items.len;
    }

    pub fn find(self: *const Self, id: []const u8) ?*const HardwareNode {
        for (self.nodes.items) |*node| {
            if (std.mem.eql(u8, node.id, id)) return node;
        }
        return null;
    }
};

test "hardware registry registers node" {
    var registry = HardwareRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register("gpu0", "Primary GPU");
    try std.testing.expectEqual(@as(usize, 1), registry.count());
}
