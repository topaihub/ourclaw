const std = @import("std");
const heartbeat = @import("../heartbeat.zig");
const cron = @import("../cron.zig");
const gateway_host = @import("../gateway_host.zig");
const runtime_host = @import("../runtime_host.zig");
const service_manager = @import("../service_manager.zig");
const daemon = @import("../daemon.zig");

pub fn initHeartbeat(allocator: std.mem.Allocator) anyerror!*heartbeat.Heartbeat {
    const heartbeat_ref = try allocator.create(heartbeat.Heartbeat);
    heartbeat_ref.* = heartbeat.Heartbeat.init();
    return heartbeat_ref;
}

pub fn initCronScheduler(allocator: std.mem.Allocator) anyerror!*cron.CronScheduler {
    const scheduler = try allocator.create(cron.CronScheduler);
    scheduler.* = cron.CronScheduler.init(allocator);
    try scheduler.registerBuiltins();
    return scheduler;
}

pub fn initGatewayHost(allocator: std.mem.Allocator) anyerror!*gateway_host.GatewayHost {
    const gateway = try allocator.create(gateway_host.GatewayHost);
    gateway.* = try gateway_host.GatewayHost.init(allocator, "127.0.0.1", 8080);
    return gateway;
}

pub fn initRuntimeHost(
    allocator: std.mem.Allocator,
    gateway: *gateway_host.GatewayHost,
    heartbeat_ref: *heartbeat.Heartbeat,
    scheduler: *cron.CronScheduler,
) anyerror!*runtime_host.RuntimeHost {
    const runtime_host_ref = try allocator.create(runtime_host.RuntimeHost);
    runtime_host_ref.* = runtime_host.RuntimeHost.init(gateway, heartbeat_ref, scheduler);
    return runtime_host_ref;
}

pub fn initServiceManager(allocator: std.mem.Allocator, runtime_host_ref: *runtime_host.RuntimeHost) anyerror!*service_manager.ServiceManager {
    const manager = try allocator.create(service_manager.ServiceManager);
    manager.* = service_manager.ServiceManager.init(runtime_host_ref);
    return manager;
}

pub fn initDaemon(allocator: std.mem.Allocator, manager: *service_manager.ServiceManager) anyerror!*daemon.Daemon {
    const daemon_ref = try allocator.create(daemon.Daemon);
    daemon_ref.* = daemon.Daemon.init(manager);
    return daemon_ref;
}
