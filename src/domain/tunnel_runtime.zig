const std = @import("std");
const http_util = @import("../compat/http_util.zig");

pub const TunnelKind = enum {
    cloudflare,
    ngrok,
    tailscale,
    custom,

    pub fn asText(self: TunnelKind) []const u8 {
        return switch (self) {
            .cloudflare => "cloudflare",
            .ngrok => "ngrok",
            .tailscale => "tailscale",
            .custom => "custom",
        };
    }
};

pub const TunnelHealthState = enum {
    inactive,
    ready,
    broken,

    pub fn asText(self: TunnelHealthState) []const u8 {
        return switch (self) {
            .inactive => "inactive",
            .ready => "ready",
            .broken => "broken",
        };
    }
};

pub const TunnelProbe = struct {
    status_code: ?u16 = null,
};

pub const TunnelRuntime = struct {
    allocator: std.mem.Allocator,
    active: bool = false,
    kind: TunnelKind = .custom,
    endpoint: []const u8 = "",
    owns_endpoint: bool = false,
    activation_count: usize = 0,
    probe_count: usize = 0,
    last_activated_ms: ?i64 = null,
    last_deactivated_ms: ?i64 = null,
    last_probe_ms: ?i64 = null,
    last_probe_status_code: ?u16 = null,
    health_state: TunnelHealthState = .inactive,
    health_message: []const u8 = "inactive",
    last_error_code: ?[]u8 = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) TunnelRuntime {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        if (self.owns_endpoint) self.allocator.free(self.endpoint);
        if (self.last_error_code) |value| self.allocator.free(value);
    }

    pub fn activate(self: *Self, kind: TunnelKind, endpoint: []const u8) anyerror!void {
        const probe = try probeEndpoint(self.allocator, endpoint);
        try self.setEndpoint(endpoint);
        self.active = true;
        self.kind = kind;
        self.activation_count += 1;
        self.probe_count += 1;
        self.last_activated_ms = std.time.milliTimestamp();
        self.last_probe_ms = self.last_activated_ms;
        self.last_probe_status_code = probe.status_code;
        self.health_state = .ready;
        self.health_message = "endpoint_reachable";
        if (self.last_error_code) |value| {
            self.allocator.free(value);
            self.last_error_code = null;
        }
    }

    pub fn deactivate(self: *Self) void {
        self.active = false;
        if (self.owns_endpoint) {
            self.allocator.free(self.endpoint);
            self.owns_endpoint = false;
        }
        self.endpoint = "";
        self.last_deactivated_ms = std.time.milliTimestamp();
        self.health_state = .inactive;
        self.health_message = "deactivated";
    }

    pub fn noteActivationFailure(self: *Self, endpoint: []const u8, err: anyerror) anyerror!void {
        try self.setEndpoint(endpoint);
        self.active = false;
        self.probe_count += 1;
        self.last_probe_ms = std.time.milliTimestamp();
        self.last_probe_status_code = null;
        self.health_state = .broken;
        self.health_message = switch (err) {
            error.TunnelInvalidEndpoint => "invalid_endpoint",
            error.TunnelEndpointUnreachable => "endpoint_unreachable",
            else => "probe_failed",
        };
        if (self.last_error_code) |value| self.allocator.free(value);
        self.last_error_code = try self.allocator.dupe(u8, @errorName(err));
    }

    fn setEndpoint(self: *Self, endpoint: []const u8) anyerror!void {
        if (self.owns_endpoint) self.allocator.free(self.endpoint);
        self.endpoint = try self.allocator.dupe(u8, endpoint);
        self.owns_endpoint = true;
    }

    fn probeEndpoint(allocator: std.mem.Allocator, endpoint: []const u8) anyerror!TunnelProbe {
        if (std.mem.eql(u8, endpoint, "mock://tunnel/healthy")) return .{ .status_code = 200 };
        if (std.mem.eql(u8, endpoint, "mock://tunnel/down")) return error.TunnelEndpointUnreachable;
        if (!(std.mem.startsWith(u8, endpoint, "https://") or std.mem.startsWith(u8, endpoint, "http://") or std.mem.startsWith(u8, endpoint, "mock://tunnel/"))) {
            return error.TunnelInvalidEndpoint;
        }

        if (std.mem.startsWith(u8, endpoint, "mock://tunnel/")) {
            return .{ .status_code = 200 };
        }

        var response = try http_util.curlRequest(allocator, "GET", endpoint, &.{}, null, 5, null);
        defer response.deinit(allocator);
        if (response.status_code >= 500) return error.TunnelEndpointUnreachable;
        return .{ .status_code = response.status_code };
    }
};

test "tunnel runtime activates endpoint" {
    var runtime = TunnelRuntime.init(std.testing.allocator);
    defer runtime.deinit();
    try runtime.activate(.cloudflare, "mock://tunnel/healthy");
    try std.testing.expect(runtime.active);
    try std.testing.expectEqualStrings("ready", runtime.health_state.asText());
}

test "tunnel runtime records failed probe" {
    var runtime = TunnelRuntime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(error.TunnelEndpointUnreachable, runtime.activate(.cloudflare, "mock://tunnel/down"));
    try runtime.noteActivationFailure("mock://tunnel/down", error.TunnelEndpointUnreachable);
    try std.testing.expect(!runtime.active);
    try std.testing.expectEqualStrings("broken", runtime.health_state.asText());
    try std.testing.expectEqualStrings("TunnelEndpointUnreachable", runtime.last_error_code.?);
}
