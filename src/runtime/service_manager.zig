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

pub const RestartStatus = struct {
    stop_changed: bool,
    start_changed: bool,
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

    pub fn install(self: *ServiceManager) bool {
        if (self.installed and self.enabled) return false;
        self.installed = true;
        self.enabled = true;
        self.install_count += 1;
        self.last_transition_ms = std.time.milliTimestamp();
        return true;
    }

    pub fn start(self: *ServiceManager) bool {
        _ = if (!self.installed) self.install() else false;
        if (self.state == .running and self.host.running) return false;
        self.state = .running;
        self.start_count += 1;
        self.last_transition_ms = std.time.milliTimestamp();
        self.host.start();
        return true;
    }

    pub fn stop(self: *ServiceManager) bool {
        if (self.state == .stopped and !self.host.running) return false;
        self.state = .stopped;
        self.stop_count += 1;
        self.last_transition_ms = std.time.milliTimestamp();
        self.host.stop();
        return true;
    }

    pub fn restart(self: *ServiceManager) RestartStatus {
        self.restart_count += 1;
        const stop_changed = self.stop();
        const start_changed = self.start();
        return .{
            .stop_changed = stop_changed,
            .start_changed = start_changed,
        };
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
    try std.testing.expect(service.install());
    try std.testing.expect(service.start());
    try std.testing.expectEqualStrings("running", service.status().state.asText());
    try std.testing.expect(service.stop());
    try std.testing.expectEqual(@as(usize, 1), service.status().stop_count);
}

test "service manager lifecycle methods are idempotent where appropriate" {
    var gateway_host = try @import("gateway_host.zig").GatewayHost.init(std.testing.allocator, "127.0.0.1", 8080);
    defer gateway_host.deinit();
    var hb = @import("heartbeat.zig").Heartbeat.init();
    var scheduler = @import("cron.zig").CronScheduler.init(std.testing.allocator);
    defer scheduler.deinit();
    var host = runtime_host.RuntimeHost.init(&gateway_host, &hb, &scheduler);
    var service = ServiceManager.init(&host);

    try std.testing.expect(service.install());
    try std.testing.expect(!service.install());
    try std.testing.expectEqual(@as(usize, 1), service.status().install_count);

    try std.testing.expect(service.start());
    try std.testing.expect(!service.start());
    try std.testing.expectEqual(@as(usize, 1), service.status().start_count);

    try std.testing.expect(service.stop());
    try std.testing.expect(!service.stop());
    try std.testing.expectEqual(@as(usize, 1), service.status().stop_count);

    const restart = service.restart();
    try std.testing.expect(!restart.stop_changed);
    try std.testing.expect(restart.start_changed);
    try std.testing.expectEqual(@as(usize, 1), service.status().restart_count);
    try std.testing.expectEqual(@as(usize, 2), service.status().start_count);
}
