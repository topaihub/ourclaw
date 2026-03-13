const std = @import("std");
const builtin = @import("builtin");
const gateway = @import("gateway_host.zig");
const heartbeat = @import("heartbeat.zig");
const cron = @import("cron.zig");

pub const RuntimeHostStatus = struct {
    running: bool,
    gateway_running: bool,
    gateway_handler_attached: bool,
    loop_active: bool,
    start_count: usize,
    stop_count: usize,
    tick_count: usize,
    last_started_ms: ?i64,
    last_stopped_ms: ?i64,
};

pub const RuntimeHost = struct {
    gateway: *gateway.GatewayHost,
    heartbeat: *heartbeat.Heartbeat,
    cron_scheduler: *cron.CronScheduler,
    running: bool = false,
    start_count: usize = 0,
    stop_count: usize = 0,
    tick_count: usize = 0,
    last_started_ms: ?i64 = null,
    last_stopped_ms: ?i64 = null,
    stop_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    loop_thread: ?std.Thread = null,
    mutex: std.Thread.Mutex = .{},

    pub fn init(gateway_host: *gateway.GatewayHost, hb: *heartbeat.Heartbeat, scheduler: *cron.CronScheduler) RuntimeHost {
        return .{
            .gateway = gateway_host,
            .heartbeat = hb,
            .cron_scheduler = scheduler,
        };
    }

    pub fn start(self: *RuntimeHost) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.running) return;
        self.running = true;
        self.start_count += 1;
        self.last_started_ms = std.time.milliTimestamp();
        self.stop_requested.store(false, .release);
        self.gateway.start();
        self.heartbeat.beat();
        if (!builtin.is_test) {
            self.loop_thread = std.Thread.spawn(.{}, loopMain, .{self}) catch null;
        }
    }

    pub fn stop(self: *RuntimeHost) void {
        self.mutex.lock();
        if (!self.running) {
            self.mutex.unlock();
            return;
        }
        self.running = false;
        self.stop_count += 1;
        self.last_stopped_ms = std.time.milliTimestamp();
        self.stop_requested.store(true, .release);
        const thread = self.loop_thread;
        self.loop_thread = null;
        self.mutex.unlock();

        self.gateway.stop();
        if (thread) |t| t.join();
    }

    pub fn tick(self: *RuntimeHost) usize {
        const executed = self.cron_scheduler.tick();
        self.tick_count += executed;
        self.heartbeat.beat();
        return executed;
    }

    pub fn status(self: *const RuntimeHost) RuntimeHostStatus {
        return .{
            .running = self.running,
            .gateway_running = self.gateway.running,
            .gateway_handler_attached = self.gateway.handler != null,
            .loop_active = self.loop_thread != null,
            .start_count = self.start_count,
            .stop_count = self.stop_count,
            .tick_count = self.tick_count,
            .last_started_ms = self.last_started_ms,
            .last_stopped_ms = self.last_stopped_ms,
        };
    }

    fn loopMain(self: *RuntimeHost) void {
        while (!self.stop_requested.load(.acquire)) {
            _ = self.tick();
            std.Thread.sleep(250 * std.time.ns_per_ms);
        }
    }
};

test "runtime host starts gateway and heartbeat" {
    var gateway_host = try gateway.GatewayHost.init(std.testing.allocator, "127.0.0.1", 8080);
    defer gateway_host.deinit();
    var hb = heartbeat.Heartbeat.init();
    var scheduler = cron.CronScheduler.init(std.testing.allocator);
    defer scheduler.deinit();
    var host = RuntimeHost.init(&gateway_host, &hb, &scheduler);
    host.start();
    try std.testing.expect(host.running);
    try std.testing.expect(hb.snapshot().healthy);
    const status = host.status();
    try std.testing.expect(status.gateway_running);
    try std.testing.expect(!status.loop_active or !builtin.is_test);
}
