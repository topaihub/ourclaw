const std = @import("std");

pub const HardwareHealthState = enum {
    ready,
    broken,

    pub fn asText(self: HardwareHealthState) []const u8 {
        return switch (self) {
            .ready => "ready",
            .broken => "broken",
        };
    }
};

pub const HardwareNode = struct {
    id: []u8,
    label: []u8,
    kind: []u8,
    registered_at_ms: i64,
    probe_count: usize = 0,
    last_checked_ms: ?i64 = null,
    last_error_code: ?[]u8 = null,
    health_state: HardwareHealthState = .ready,
    health_message: []const u8 = "ready",

    pub fn deinit(self: *HardwareNode, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.label);
        allocator.free(self.kind);
        if (self.last_error_code) |value| allocator.free(value);
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
        const owned_id = try self.allocator.dupe(u8, id);
        const owned_label = self.allocator.dupe(u8, label) catch |err| {
            self.allocator.free(owned_id);
            return err;
        };
        const kind = detectKind(self.allocator, id) catch |err| {
            self.allocator.free(owned_label);
            self.allocator.free(owned_id);
            return err;
        };
        var node = HardwareNode{
            .id = owned_id,
            .label = owned_label,
            .kind = kind,
            .registered_at_ms = std.time.milliTimestamp(),
        };
        errdefer node.deinit(self.allocator);
        try probeNode(self.allocator, &node);
        try self.nodes.append(self.allocator, node);
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

    pub fn findMutable(self: *Self, id: []const u8) ?*HardwareNode {
        for (self.nodes.items) |*node| {
            if (std.mem.eql(u8, node.id, id)) return node;
        }
        return null;
    }

    pub fn probeById(self: *Self, id: []const u8) anyerror!*const HardwareNode {
        const node = self.findMutable(id) orelse return error.HardwareNodeNotFound;
        if (node.last_error_code) |value| {
            self.allocator.free(value);
            node.last_error_code = null;
        }
        probeNode(self.allocator, node) catch |err| switch (err) {
            error.HardwareNodeOffline => {},
            else => return err,
        };
        return node;
    }

    fn detectKind(allocator: std.mem.Allocator, id: []const u8) anyerror![]u8 {
        if (std.mem.startsWith(u8, id, "gpu")) return allocator.dupe(u8, "gpu");
        if (std.mem.startsWith(u8, id, "sensor")) return allocator.dupe(u8, "sensor");
        if (std.mem.startsWith(u8, id, "camera")) return allocator.dupe(u8, "camera");
        if (std.mem.startsWith(u8, id, "mic")) return allocator.dupe(u8, "microphone");
        return error.HardwareUnsupportedKind;
    }

    fn probeNode(allocator: std.mem.Allocator, node: *HardwareNode) anyerror!void {
        node.probe_count += 1;
        node.last_checked_ms = std.time.milliTimestamp();
        if (std.mem.indexOf(u8, node.id, "offline") != null) {
            node.health_state = .broken;
            node.health_message = "device_offline";
            node.last_error_code = try allocator.dupe(u8, "HardwareNodeOffline");
            return error.HardwareNodeOffline;
        }
        node.health_state = .ready;
        node.health_message = "device_ready";
    }
};

test "hardware registry registers node" {
    var registry = HardwareRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register("gpu0", "Primary GPU");
    try std.testing.expectEqual(@as(usize, 1), registry.count());
}

test "hardware registry maps offline node failure" {
    var registry = HardwareRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try std.testing.expectError(error.HardwareNodeOffline, registry.register("gpu_offline", "Offline GPU"));
}

test "hardware registry probe by id updates node" {
    var registry = HardwareRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register("gpu0", "Primary GPU");
    const before = registry.find("gpu0").?.probe_count;
    const node = try registry.probeById("gpu0");
    try std.testing.expect(node.probe_count > before);
}
