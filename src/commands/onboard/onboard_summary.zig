const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "onboard.summary",
        .method = "onboard.summary",
        .description = "Show current onboarding readiness and next steps",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *const @import("../../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const service_status = app.service_manager.status();

    const secrets_configured = services.secret_store.count() > 0;
    const providers_available = services.provider_registry.count() > 0;
    const gateway_pairing_enabled = app.effective_gateway_require_pairing;
    const service_installed = service_status.installed;
    const devices_ready = services.hardware_registry.count() > 0 and services.peripheral_registry.count() > 0;
    const ready_count: usize = @as(usize, @intFromBool(secrets_configured)) + @as(usize, @intFromBool(providers_available)) + @as(usize, @intFromBool(gateway_pairing_enabled)) + @as(usize, @intFromBool(service_installed)) + @as(usize, @intFromBool(devices_ready));

    const next_step: []const u8 = if (!service_installed)
        "install_service"
    else if (!gateway_pairing_enabled)
        "enable_pairing"
    else if (app.pairing_registry.pendingCount() > 0)
        "approve_pairing_requests"
    else if (!devices_ready)
        "register_devices"
    else
        "system_ready";

    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"readyCount\":{d},\"totalChecks\":5,\"secretsConfigured\":{s},\"providersAvailable\":{s},\"gatewayPairingEnabled\":{s},\"serviceInstalled\":{s},\"devicesReady\":{s},\"pendingPairingCount\":{d},\"nextStep\":\"{s}\"}}",
        .{
            ready_count,
            if (secrets_configured) "true" else "false",
            if (providers_available) "true" else "false",
            if (gateway_pairing_enabled) "true" else "false",
            if (service_installed) "true" else "false",
            if (devices_ready) "true" else "false",
            app.pairing_registry.pendingCount(),
            next_step,
        },
    );
}
