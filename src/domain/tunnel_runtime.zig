const std = @import("std");

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

pub const TunnelRuntime = struct {
    active: bool = false,
    kind: TunnelKind = .custom,
    endpoint: []const u8 = "",
    activation_count: usize = 0,
    last_activated_ms: ?i64 = null,
    last_deactivated_ms: ?i64 = null,

    pub fn init() TunnelRuntime {
        return .{};
    }

    pub fn activate(self: *TunnelRuntime, kind: TunnelKind, endpoint: []const u8) void {
        self.active = true;
        self.kind = kind;
        self.endpoint = endpoint;
        self.activation_count += 1;
        self.last_activated_ms = std.time.milliTimestamp();
    }

    pub fn deactivate(self: *TunnelRuntime) void {
        self.active = false;
        self.endpoint = "";
        self.last_deactivated_ms = std.time.milliTimestamp();
    }
};

test "tunnel runtime activates endpoint" {
    var runtime = TunnelRuntime.init();
    runtime.activate(.cloudflare, "https://demo.example.com");
    try std.testing.expect(runtime.active);
}
