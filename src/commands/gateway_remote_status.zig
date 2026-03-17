const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "gateway.remote.status",
        .method = "gateway.remote.status",
        .description = "Show remote gateway readiness and tunnel state",
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
    const tunnel = app.tunnel_runtime;
    const token = services.secret_store.get("gateway:shared_token");
    const base_url = try std.fmt.allocPrint(ctx.allocator, "http://{s}:{d}/", .{ gateway.bind_host, gateway.bind_port });
    defer ctx.allocator.free(base_url);

    const next_action: []const u8 = if (!tunnel.active)
        "activate_tunnel"
    else if (token == null)
        "generate_gateway_token"
    else
        "remote_ready";

    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"tunnelActive\":{s},\"tunnelKind\":\"{s}\",\"tunnelEndpoint\":\"{s}\",\"tunnelHealthState\":\"{s}\",\"tunnelHealthMessage\":\"{s}\",\"sharedTokenConfigured\":{s},\"localAccessUrl\":\"{s}\",\"nextAction\":\"{s}\"}}",
        .{
            if (tunnel.active) "true" else "false",
            tunnel.kind.asText(),
            tunnel.endpoint,
            tunnel.health_state.asText(),
            tunnel.health_message,
            if (token != null) "true" else "false",
            base_url,
            next_action,
        },
    );
}
