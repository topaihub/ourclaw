const std = @import("std");

pub const PeripheralDevice = struct {
    id: []u8,
    kind: []u8,

    pub fn deinit(self: *PeripheralDevice, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.kind);
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
        try self.devices.append(self.allocator, .{
            .id = try self.allocator.dupe(u8, id),
            .kind = try self.allocator.dupe(u8, kind),
        });
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
};

test "peripheral registry registers device" {
    var registry = PeripheralRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register("camera", "video");
    try std.testing.expectEqual(@as(usize, 1), registry.count());
}
