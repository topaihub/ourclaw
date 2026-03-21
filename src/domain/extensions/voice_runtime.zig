const std = @import("std");
const peripherals = @import("peripherals.zig");

pub const VoiceHealthState = enum {
    inactive,
    ready,
    broken,

    pub fn asText(self: VoiceHealthState) []const u8 {
        return switch (self) {
            .inactive => "inactive",
            .ready => "ready",
            .broken => "broken",
        };
    }
};

pub const VoiceRuntime = struct {
    allocator: std.mem.Allocator,
    active: bool = false,
    attached_peripheral_id: []const u8 = "",
    owns_attached_peripheral_id: bool = false,
    attach_count: usize = 0,
    last_attached_ms: ?i64 = null,
    last_detached_ms: ?i64 = null,
    last_checked_ms: ?i64 = null,
    last_error_code: ?[]u8 = null,
    health_state: VoiceHealthState = .inactive,
    health_message: []const u8 = "inactive",

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        if (self.owns_attached_peripheral_id) self.allocator.free(self.attached_peripheral_id);
        if (self.last_error_code) |value| self.allocator.free(value);
    }

    pub fn attach(self: *Self, registry: *const peripherals.PeripheralRegistry, peripheral_id: []const u8) anyerror!void {
        const device = registry.find(peripheral_id) orelse return self.markFailure(error.VoicePeripheralNotFound, "peripheral_not_found");
        self.last_checked_ms = std.time.milliTimestamp();
        if (!std.mem.eql(u8, device.kind, "audio")) {
            return self.markFailure(error.VoiceUnsupportedPeripheralKind, "unsupported_peripheral_kind");
        }
        try self.setPeripheralId(peripheral_id);
        self.active = true;
        self.attach_count += 1;
        self.last_attached_ms = self.last_checked_ms;
        self.health_state = .ready;
        self.health_message = "audio_attached";
        if (self.last_error_code) |value| {
            self.allocator.free(value);
            self.last_error_code = null;
        }
    }

    pub fn detach(self: *Self) void {
        self.active = false;
        if (self.owns_attached_peripheral_id) {
            self.allocator.free(self.attached_peripheral_id);
            self.owns_attached_peripheral_id = false;
        }
        self.attached_peripheral_id = "";
        self.last_detached_ms = std.time.milliTimestamp();
        self.health_state = .inactive;
        self.health_message = "detached";
    }

    fn setPeripheralId(self: *Self, peripheral_id: []const u8) anyerror!void {
        if (self.owns_attached_peripheral_id) self.allocator.free(self.attached_peripheral_id);
        self.attached_peripheral_id = try self.allocator.dupe(u8, peripheral_id);
        self.owns_attached_peripheral_id = true;
    }

    fn markFailure(self: *Self, err: anyerror, message: []const u8) anyerror!void {
        self.active = false;
        self.health_state = .broken;
        self.health_message = message;
        self.last_checked_ms = std.time.milliTimestamp();
        if (self.last_error_code) |value| self.allocator.free(value);
        self.last_error_code = try self.allocator.dupe(u8, @errorName(err));
        return err;
    }
};

test "voice runtime attaches audio peripheral" {
    var registry = peripherals.PeripheralRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register("mic0", "audio");

    var runtime = VoiceRuntime.init(std.testing.allocator);
    defer runtime.deinit();
    try runtime.attach(&registry, "mic0");
    try std.testing.expect(runtime.active);
    try std.testing.expectEqualStrings("ready", runtime.health_state.asText());
}

test "voice runtime rejects non-audio peripheral" {
    var registry = peripherals.PeripheralRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register("camera0", "video");

    var runtime = VoiceRuntime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(error.VoiceUnsupportedPeripheralKind, runtime.attach(&registry, "camera0"));
}
