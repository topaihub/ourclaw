const std = @import("std");
const service_manager = @import("service_manager.zig");

pub const DaemonStatus = struct {
    installed: bool,
    enabled: bool,
    state: []const u8,
    install_count: usize,
    start_count: usize,
    stop_count: usize,
    restart_count: usize,
    runtime_running: bool,
    last_transition_ms: ?i64,
};

pub const Daemon = struct {
    manager: *service_manager.ServiceManager,

    pub fn init(manager: *service_manager.ServiceManager) Daemon {
        return .{ .manager = manager };
    }

    pub fn install(self: *Daemon) void {
        self.manager.install();
    }

    pub fn start(self: *Daemon) void {
        self.manager.start();
    }

    pub fn stop(self: *Daemon) void {
        self.manager.stop();
    }

    pub fn restart(self: *Daemon) void {
        self.manager.restart();
    }

    pub fn status(self: *const Daemon) DaemonStatus {
        const current = self.manager.status();
        return .{
            .installed = current.installed,
            .enabled = current.enabled,
            .state = current.state.asText(),
            .install_count = current.install_count,
            .start_count = current.start_count,
            .stop_count = current.stop_count,
            .restart_count = current.restart_count,
            .runtime_running = current.runtime_running,
            .last_transition_ms = current.last_transition_ms,
        };
    }
};

test "daemon reflects service status" {
    var gateway_host = try @import("gateway_host.zig").GatewayHost.init(std.testing.allocator, "127.0.0.1", 8080);
    defer gateway_host.deinit();
    var hb = @import("heartbeat.zig").Heartbeat.init();
    var scheduler = @import("cron.zig").CronScheduler.init(std.testing.allocator);
    defer scheduler.deinit();
    var host = @import("runtime_host.zig").RuntimeHost.init(&gateway_host, &hb, &scheduler);
    var manager = service_manager.ServiceManager.init(&host);
    var daemon = Daemon.init(&manager);
    daemon.install();
    try std.testing.expect(daemon.status().installed);
}
