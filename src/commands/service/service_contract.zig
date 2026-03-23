const std = @import("std");
const app_context = @import("../../runtime/app_context.zig");

pub fn buildServiceSnapshotJson(allocator: std.mem.Allocator, app: *const app_context.AppContext, extra_fields_json: ?[]const u8) anyerror![]u8 {
    const service_status = app.service_manager.status();
    const daemon_status = app.daemon.status();
    const gateway_status = app.gateway_host.status();
    const host_status = app.runtime_host.status();
    const heartbeat_status = app.heartbeat.snapshot();

    return std.fmt.allocPrint(
        allocator,
        "{{\"serviceState\":\"{s}\",\"installed\":{s},\"enabled\":{s},\"autostart\":{s},\"daemonState\":\"{s}\",\"daemonProjected\":true,\"pid\":{?},\"lockHeld\":{s},\"restartBudgetRemaining\":{d},\"restartBudgetExhausted\":{s},\"staleProcessDetected\":{s},\"recoveryEligible\":{s},\"recoveryAction\":\"{s}\",\"heartbeatHealthy\":{s},\"heartbeatAgeMs\":{?},\"heartbeatStaleAfterMs\":{d},\"gatewayRunning\":{s},\"hostRunning\":{s},\"hostLoopActive\":{s},\"gatewayHandlerAttached\":{s},\"bindHost\":\"{s}\",\"bindPort\":{d},\"installCount\":{d},\"startCount\":{d},\"stopCount\":{d},\"restartCount\":{d},\"hostStartCount\":{d},\"hostTickCount\":{d},\"lastTransitionMs\":{?}{s}}}",
        .{
            service_status.state.asText(),
            if (service_status.installed) "true" else "false",
            if (service_status.enabled) "true" else "false",
            if (service_status.autostart) "true" else "false",
            daemon_status.state,
            daemon_status.pid,
            if (daemon_status.lock_held) "true" else "false",
            daemon_status.restart_budget_remaining,
            if (daemon_status.restart_budget_exhausted) "true" else "false",
            if (daemon_status.stale_process_detected) "true" else "false",
            if (daemon_status.recovery_eligible) "true" else "false",
            daemon_status.recovery_action,
            if (heartbeat_status.healthy) "true" else "false",
            heartbeat_status.age_ms,
            heartbeat_status.stale_after_ms,
            if (gateway_status.running) "true" else "false",
            if (host_status.running) "true" else "false",
            if (host_status.loop_active) "true" else "false",
            if (host_status.gateway_handler_attached) "true" else "false",
            gateway_status.bind_host,
            gateway_status.bind_port,
            service_status.install_count,
            service_status.start_count,
            service_status.stop_count,
            service_status.restart_count,
            host_status.start_count,
            host_status.tick_count,
            daemon_status.last_transition_ms,
            extra_fields_json orelse "",
        },
    );
}
