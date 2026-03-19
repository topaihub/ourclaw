const std = @import("std");

pub const IngressMode = enum {
    idle,
    webhook,
    polling,

    pub fn asText(self: IngressMode) []const u8 {
        return switch (self) {
            .idle => "idle",
            .webhook => "webhook",
            .polling => "polling",
        };
    }
};

pub const IngressHealth = enum {
    idle,
    ready,
    degraded,

    pub fn asText(self: IngressHealth) []const u8 {
        return switch (self) {
            .idle => "idle",
            .ready => "ready",
            .degraded => "degraded",
        };
    }
};

pub const ChannelIngressSnapshot = struct {
    active: bool,
    channel: ?[]const u8,
    mode: IngressMode,
    health: IngressHealth,
    endpoint: ?[]const u8,
    last_error_code: ?[]const u8,
    start_count: usize,
    stop_count: usize,
};

pub const ChannelIngressRuntime = struct {
    allocator: std.mem.Allocator,
    active: bool = false,
    channel: ?[]u8 = null,
    mode: IngressMode = .idle,
    health: IngressHealth = .idle,
    endpoint: ?[]u8 = null,
    last_error_code: ?[]u8 = null,
    start_count: usize = 0,
    stop_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) ChannelIngressRuntime {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ChannelIngressRuntime) void {
        if (self.channel) |value| self.allocator.free(value);
        if (self.endpoint) |value| self.allocator.free(value);
        if (self.last_error_code) |value| self.allocator.free(value);
    }

    pub fn start(self: *ChannelIngressRuntime, channel: []const u8, mode: IngressMode, endpoint: []const u8) anyerror!void {
        if (self.channel) |value| self.allocator.free(value);
        if (self.endpoint) |value| self.allocator.free(value);
        if (self.last_error_code) |value| {
            self.allocator.free(value);
            self.last_error_code = null;
        }
        self.channel = try self.allocator.dupe(u8, channel);
        self.endpoint = try self.allocator.dupe(u8, endpoint);
        self.mode = mode;
        self.active = true;
        self.health = .ready;
        self.start_count += 1;
    }

    pub fn stop(self: *ChannelIngressRuntime) void {
        self.active = false;
        self.health = .idle;
        self.mode = .idle;
        self.stop_count += 1;
    }

    pub fn noteFailure(self: *ChannelIngressRuntime, error_code: []const u8) anyerror!void {
        if (self.last_error_code) |value| self.allocator.free(value);
        self.last_error_code = try self.allocator.dupe(u8, error_code);
        self.health = .degraded;
    }

    pub fn snapshot(self: *const ChannelIngressRuntime) ChannelIngressSnapshot {
        return .{
            .active = self.active,
            .channel = self.channel,
            .mode = self.mode,
            .health = self.health,
            .endpoint = self.endpoint,
            .last_error_code = self.last_error_code,
            .start_count = self.start_count,
            .stop_count = self.stop_count,
        };
    }
};

test "channel ingress runtime start stop and degrade" {
    var runtime = ChannelIngressRuntime.init(std.testing.allocator);
    defer runtime.deinit();
    try runtime.start("telegram", .webhook, "https://example.test/hook");
    try std.testing.expect(runtime.snapshot().active);
    try std.testing.expectEqualStrings("webhook", runtime.snapshot().mode.asText());
    try runtime.noteFailure("WEBHOOK_FAILED");
    try std.testing.expectEqualStrings("degraded", runtime.snapshot().health.asText());
    runtime.stop();
    try std.testing.expect(!runtime.snapshot().active);
}
