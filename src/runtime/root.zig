const std = @import("std");

pub const MODULE_NAME = "runtime";
pub const app_context = @import("app_context.zig");
pub const heartbeat = @import("heartbeat.zig");
pub const cron = @import("cron.zig");
pub const gateway_host = @import("gateway_host.zig");
pub const runtime_host = @import("runtime_host.zig");
pub const service_manager = @import("service_manager.zig");
pub const daemon = @import("daemon.zig");

pub const AppBootstrapConfig = app_context.AppBootstrapConfig;
pub const AppContext = app_context.AppContext;
pub const Heartbeat = heartbeat.Heartbeat;
pub const HeartbeatSnapshot = heartbeat.HeartbeatSnapshot;
pub const CronScheduler = cron.CronScheduler;
pub const CronJob = cron.CronJob;
pub const GatewayHost = gateway_host.GatewayHost;
pub const GatewayStatus = gateway_host.GatewayStatus;
pub const RuntimeHost = runtime_host.RuntimeHost;
pub const ServiceManager = service_manager.ServiceManager;
pub const ServiceState = service_manager.ServiceState;
pub const ServiceStatus = service_manager.ServiceStatus;
pub const Daemon = daemon.Daemon;
pub const DaemonStatus = daemon.DaemonStatus;

test "runtime exports are stable" {
    try std.testing.expectEqualStrings("runtime", MODULE_NAME);
    _ = AppContext;
    _ = RuntimeHost;
}
