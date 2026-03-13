const std = @import("std");
const runtime_host = @import("runtime_host.zig");

pub const ServiceState = enum {
    stopped,
    running,

    pub fn asText(self: ServiceState) []const u8 {
        return switch (self) {
            .stopped => "stopped",
            .running => "running",
        };
    }
};

pub const ServiceStatus = struct {
    state: ServiceState,
    installed: bool,
    enabled: bool,
    runtime_running: bool,
    install_count: usize,
    start_count: usize,
    stop_count: usize,
    restart_count: usize,
    last_transition_ms: ?i64,
};

pub const ServiceManager = struct {
    installed: bool = false,
    enabled: bool = false,
    state: ServiceState = .stopped,
    host: *runtime_host.RuntimeHost,
    install_count: usize = 0,
    start_count: usize = 0,
    stop_count: usize = 0,
    restart_count: usize = 0,
    last_transition_ms: ?i64 = null,

    pub fn init(host: *runtime_host.RuntimeHost) ServiceManager {
        return .{ .host = host };
    }

    pub fn install(self: *ServiceManager) void {
        self.installed = true;
        self.enabled = true;
        self.install_count += 1;
        self.last_transition_ms = std.time.milliTimestamp();
    }

    pub fn start(self: *ServiceManager) void {
        if (!self.installed) self.install();
        if (self.state == .running and self.host.running) return;
        self.state = .running;
        self.start_count += 1;
        self.last_transition_ms = std.time.milliTimestamp();
        self.host.start();
    }

    pub fn stop(self: *ServiceManager) void {
        if (self.state == .stopped and !self.host.running) return;
        self.state = .stopped;
        self.stop_count += 1;
        self.last_transition_ms = std.time.milliTimestamp();
        self.host.stop();
    }

    pub fn restart(self: *ServiceManager) void {
        self.restart_count += 1;
        self.stop();
        self.start();
    }

    pub fn status(self: *const ServiceManager) ServiceStatus {
        return .{
            .state = self.state,
            .installed = self.installed,
            .enabled = self.enabled,
            .runtime_running = self.host.running,
            .install_count = self.install_count,
            .start_count = self.start_count,
            .stop_count = self.stop_count,
            .restart_count = self.restart_count,
            .last_transition_ms = self.last_transition_ms,
        };
    }
};

test "service manager tracks service state" {
    var gateway_host = try @import("gateway_host.zig").GatewayHost.init(std.testing.allocator, "127.0.0.1", 8080);
    defer gateway_host.deinit();
    var hb = @import("heartbeat.zig").Heartbeat.init();
    var scheduler = @import("cron.zig").CronScheduler.init(std.testing.allocator);
    defer scheduler.deinit();
    var host = runtime_host.RuntimeHost.init(&gateway_host, &hb, &scheduler);
    var service = ServiceManager.init(&host);
    service.install();
    service.start();
    try std.testing.expectEqualStrings("running", service.status().state.asText());
    service.stop();
    try std.testing.expectEqual(@as(usize, 1), service.status().stop_count);
}
