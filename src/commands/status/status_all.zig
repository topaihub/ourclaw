const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "status.all",
        .method = "status.all",
        .description = "Get product-level runtime status overview",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *const @import("../../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const gateway = app.gateway_host.status();
    const service = app.service_manager.status();

    var pending_pairings: usize = 0;
    var approved_pairings: usize = 0;
    for (app.pairing_registry.items()) |request| {
        switch (request.state) {
            .pending => pending_pairings += 1,
            .approved => approved_pairings += 1,
            .rejected => {},
        }
    }

    var healthy_providers: usize = 0;
    for (services.provider_registry.definitions.items) |provider_def| {
        var health = services.provider_registry.health(ctx.allocator, provider_def.id) catch continue;
        defer health.deinit(ctx.allocator);
        if (health.healthy) healthy_providers += 1;
    }

    const next_action: []const u8 = if (!service.installed)
        "install_service"
    else if (!app.effective_gateway_require_pairing)
        "enable_pairing"
    else if (pending_pairings > 0)
        "approve_pairing_requests"
    else if (!gateway.running)
        "start_gateway"
    else
        "ready";

    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"gateway\":{{\"running\":{s},\"listenerReady\":{s}}},\"service\":{{\"installed\":{s},\"state\":\"{s}\"}},\"providers\":{{\"total\":{d},\"healthy\":{d}}},\"devices\":{{\"nodes\":{d},\"peripherals\":{d}}},\"pairing\":{{\"required\":{s},\"pending\":{d},\"approved\":{d}}},\"nextAction\":\"{s}\"}}",
        .{
            if (gateway.running) "true" else "false",
            if (gateway.listener_ready) "true" else "false",
            if (service.installed) "true" else "false",
            service.state.asText(),
            services.provider_registry.count(),
            healthy_providers,
            services.hardware_registry.count(),
            services.peripheral_registry.count(),
            if (app.effective_gateway_require_pairing) "true" else "false",
            pending_pairings,
            approved_pairings,
            next_action,
        },
    );
}
