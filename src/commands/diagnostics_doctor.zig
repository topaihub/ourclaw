const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "diagnostics.doctor",
        .method = "diagnostics.doctor",
        .description = "Run basic runtime health checks",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *const @import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const gateway_status = app.gateway_host.status();
    const service_status = app.service_manager.status();
    const tunnel = services.tunnel_runtime;
    const shared_token_configured = services.secret_store.get("gateway:shared_token") != null;

    var issues: std.ArrayListUnmanaged([]const u8) = .empty;
    defer issues.deinit(ctx.allocator);

    var healthy_provider_count: usize = 0;
    var unhealthy_provider_count: usize = 0;
    for (services.provider_registry.definitions.items) |provider_def| {
        var health = services.provider_registry.health(ctx.allocator, provider_def.id) catch {
            unhealthy_provider_count += 1;
            continue;
        };
        defer health.deinit(ctx.allocator);
        if (health.healthy) {
            healthy_provider_count += 1;
        } else {
            unhealthy_provider_count += 1;
        }
    }

    var broken_hardware_count: usize = 0;
    for (services.hardware_registry.nodes.items) |node| {
        if (node.health_state != .ready) broken_hardware_count += 1;
    }

    var broken_peripheral_count: usize = 0;
    for (services.peripheral_registry.devices.items) |device| {
        if (device.health_state != .ready) broken_peripheral_count += 1;
    }

    if (services.secret_store.count() == 0) try issues.append(ctx.allocator, "no secrets configured");
    if (services.provider_registry.count() == 0) try issues.append(ctx.allocator, "provider registry is empty");
    if (services.channel_registry.count() == 0) try issues.append(ctx.allocator, "channel registry is empty");
    if (services.tool_registry.count() == 0) try issues.append(ctx.allocator, "tool registry is empty");
    if (services.framework_context.command_registry.count() == 0) try issues.append(ctx.allocator, "command registry is empty");
    if (!app.effective_gateway_require_pairing) try issues.append(ctx.allocator, "gateway pairing protection is disabled");
    if (gateway_status.running and !gateway_status.listener_ready) try issues.append(ctx.allocator, "gateway listener is not ready");
    if (gateway_status.running and !gateway_status.handler_attached) try issues.append(ctx.allocator, "gateway handler is not attached");
    if (service_status.restart_budget_exhausted) try issues.append(ctx.allocator, "service restart budget exhausted");
    if (service_status.stale_process_detected) try issues.append(ctx.allocator, "stale service process detected");
    if (shared_token_configured and !tunnel.active) try issues.append(ctx.allocator, "remote access token exists but tunnel is not active");
    if (tunnel.active and tunnel.health_state != .ready) try issues.append(ctx.allocator, "remote tunnel is unhealthy");
    if (unhealthy_provider_count > 0) try issues.append(ctx.allocator, "one or more providers are unhealthy");
    if (broken_hardware_count > 0) try issues.append(ctx.allocator, "one or more hardware nodes are unhealthy");
    if (broken_peripheral_count > 0) try issues.append(ctx.allocator, "one or more peripherals are unhealthy");

    var maybe_openai_health = services.provider_registry.health(ctx.allocator, "openai") catch null;
    defer if (maybe_openai_health) |*health| health.deinit(ctx.allocator);
    if (maybe_openai_health == null or !maybe_openai_health.?.healthy) {
        try issues.append(ctx.allocator, "openai provider is not healthy");
    }

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.writeByte('{');
    try writer.print("\"status\":\"{s}\"", .{if (issues.items.len == 0) "ok" else "degraded"});
    try writer.writeAll(",\"issueCount\":");
    try writer.print("{d}", .{issues.items.len});
    try writer.writeAll(",\"issues\":[");
    for (issues.items, 0..) |issue, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("\"{s}\"", .{issue});
    }
    try writer.writeByte(']');
    try writer.writeAll(",\"checks\":{");
    try writer.print("\"providerCount\":{d},\"healthyProviderCount\":{d},\"unhealthyProviderCount\":{d},\"channelCount\":{d},\"toolCount\":{d},\"commandCount\":{d},\"secretCount\":{d},\"hardwareCount\":{d},\"brokenHardwareCount\":{d},\"peripheralCount\":{d},\"brokenPeripheralCount\":{d},\"gatewayRequirePairing\":{s},\"gatewayRunning\":{s},\"gatewayListenerReady\":{s},\"gatewayHandlerAttached\":{s},\"sharedTokenConfigured\":{s},\"tunnelActive\":{s},\"tunnelHealthState\":\"{s}\",\"serviceState\":\"{s}\",\"restartBudgetExhausted\":{s},\"staleProcessDetected\":{s},\"recoveryAction\":\"{s}\"", .{
        services.provider_registry.count(),
        healthy_provider_count,
        unhealthy_provider_count,
        services.channel_registry.count(),
        services.tool_registry.count(),
        services.framework_context.command_registry.count(),
        services.secret_store.count(),
        services.hardware_registry.count(),
        broken_hardware_count,
        services.peripheral_registry.count(),
        broken_peripheral_count,
        if (app.effective_gateway_require_pairing) "true" else "false",
        if (gateway_status.running) "true" else "false",
        if (gateway_status.listener_ready) "true" else "false",
        if (gateway_status.handler_attached) "true" else "false",
        if (shared_token_configured) "true" else "false",
        if (tunnel.active) "true" else "false",
        tunnel.health_state.asText(),
        service_status.state.asText(),
        if (service_status.restart_budget_exhausted) "true" else "false",
        if (service_status.stale_process_detected) "true" else "false",
        service_status.recovery_action,
    });
    try writer.writeByte('}');
    try writer.writeByte('}');
    return ctx.allocator.dupe(u8, buf.items);
}
