const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "service.status",
        .method = "service.status",
        .description = "Return service/daemon/runtime host status",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const service = services.app_context_ptr.?; // just ensure available
    _ = service;
    const app = services.app_context_ptr.?;
    const runtime_app: *const @import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(app));
    const service_status = runtime_app.service_manager.status();
    const daemon_status = runtime_app.daemon.status();
    const gateway_status = runtime_app.gateway_host.status();
    const host_status = runtime_app.runtime_host.status();
    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"serviceState\":\"{s}\",\"installed\":{s},\"enabled\":{s},\"daemonState\":\"{s}\",\"daemonProjected\":true,\"gatewayRunning\":{s},\"hostRunning\":{s},\"hostLoopActive\":{s},\"gatewayHandlerAttached\":{s},\"bindHost\":\"{s}\",\"bindPort\":{d},\"installCount\":{d},\"startCount\":{d},\"stopCount\":{d},\"restartCount\":{d},\"hostStartCount\":{d},\"hostTickCount\":{d}}}",
        .{
            service_status.state.asText(),
            if (service_status.installed) "true" else "false",
            if (service_status.enabled) "true" else "false",
            daemon_status.state,
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
        },
    );
}
