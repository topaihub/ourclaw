const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "gateway.auth.status",
        .method = "gateway.auth.status",
        .description = "Show gateway access and pairing status",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *const @import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const gateway = app.gateway_host.status();

    var pending_pairings: usize = 0;
    var approved_pairings: usize = 0;
    for (app.pairing_registry.items()) |request| {
        switch (request.state) {
            .pending => pending_pairings += 1,
            .approved => approved_pairings += 1,
            .rejected => {},
        }
    }

    const next_action: []const u8 = if (!app.effective_gateway_require_pairing)
        "enable_pairing"
    else if (pending_pairings > 0)
        "approve_pairing_requests"
    else if (!gateway.running)
        "start_gateway"
    else
        "access_ready";

    const shared_token_configured = services.secret_store.get("gateway:shared_token") != null;

    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"requirePairing\":{s},\"pendingPairings\":{d},\"approvedPairings\":{d},\"sharedTokenSupported\":true,\"sharedTokenConfigured\":{s},\"passwordSupported\":false,\"passwordConfigured\":false,\"remoteAccessSupported\":false,\"bindHost\":\"{s}\",\"bindPort\":{d},\"gatewayRunning\":{s},\"nextAction\":\"{s}\"}}",
        .{
            if (app.effective_gateway_require_pairing) "true" else "false",
            pending_pairings,
            approved_pairings,
            if (shared_token_configured) "true" else "false",
            gateway.bind_host,
            gateway.bind_port,
            if (gateway.running) "true" else "false",
            next_action,
        },
    );
}
