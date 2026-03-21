const std = @import("std");

pub const PeripheralHealthState = enum {
    ready,
    broken,

    pub fn asText(self: PeripheralHealthState) []const u8 {
        return switch (self) {
            .ready => "ready",
            .broken => "broken",
        };
    }
};

pub const PeripheralDevice = struct {
    id: []u8,
    kind: []u8,
    registered_at_ms: i64,
    probe_count: usize = 0,
    last_checked_ms: ?i64 = null,
    last_error_code: ?[]u8 = null,
    health_state: PeripheralHealthState = .ready,
    health_message: []const u8 = "ready",

    pub fn deinit(self: *PeripheralDevice, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.kind);
        if (self.last_error_code) |value| allocator.free(value);
    }
};

pub const PeripheralRegistry = struct {
    allocator: std.mem.Allocator,
    devices: std.ArrayListUnmanaged(PeripheralDevice) = .empty,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.devices.items) |*device| device.deinit(self.allocator);
        self.devices.deinit(self.allocator);
    }

    pub fn register(self: *Self, id: []const u8, kind: []const u8) anyerror!void {
        for (self.devices.items) |device| {
            if (std.mem.eql(u8, device.id, id)) return error.DuplicatePeripheral;
        }
        var device = PeripheralDevice{
            .id = try self.allocator.dupe(u8, id),
            .kind = try self.allocator.dupe(u8, kind),
            .registered_at_ms = std.time.milliTimestamp(),
        };
        errdefer device.deinit(self.allocator);
        try probeDevice(self.allocator, &device);
        try self.devices.append(self.allocator, device);
    }

    pub fn count(self: *const Self) usize {
        return self.devices.items.len;
    }

    pub fn find(self: *const Self, id: []const u8) ?*const PeripheralDevice {
        for (self.devices.items) |*device| {
            if (std.mem.eql(u8, device.id, id)) return device;
        }
        return null;
    }

    fn probeDevice(allocator: std.mem.Allocator, device: *PeripheralDevice) anyerror!void {
        device.probe_count += 1;
        device.last_checked_ms = std.time.milliTimestamp();
        const supported = std.mem.eql(u8, device.kind, "video") or std.mem.eql(u8, device.kind, "audio") or std.mem.eql(u8, device.kind, "input");
        if (!supported) {
            device.health_state = .broken;
            device.health_message = "unsupported_kind";
            device.last_error_code = try allocator.dupe(u8, "PeripheralUnsupportedKind");
            return error.PeripheralUnsupportedKind;
        }
        if (std.mem.indexOf(u8, device.id, "offline") != null) {
            device.health_state = .broken;
            device.health_message = "device_offline";
            device.last_error_code = try allocator.dupe(u8, "PeripheralOffline");
            return error.PeripheralOffline;
        }
        device.health_state = .ready;
        device.health_message = "device_ready";
    }
};

test "peripheral registry registers device" {
    var registry = PeripheralRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register("camera", "video");
    try std.testing.expectEqual(@as(usize, 1), registry.count());
}

test "peripheral registry rejects unsupported kind" {
    var registry = PeripheralRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try std.testing.expectError(error.PeripheralUnsupportedKind, registry.register("camera1", "serial"));
}
