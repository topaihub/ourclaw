const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;
const tunnel = domain.tunnel_runtime;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "tunnel.activate", .method = "tunnel.activate", .description = "Activate tunnel runtime", .authority = .admin, .user_data = @ptrCast(command_services), .params = &.{
        .{ .key = "kind", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
        .{ .key = "endpoint", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
    }, .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const kind_text = ctx.param("kind").?.value.string;
    const endpoint = ctx.param("endpoint").?.value.string;
    const kind = if (std.mem.eql(u8, kind_text, "cloudflare")) tunnel.TunnelKind.cloudflare else if (std.mem.eql(u8, kind_text, "ngrok")) tunnel.TunnelKind.ngrok else if (std.mem.eql(u8, kind_text, "tailscale")) tunnel.TunnelKind.tailscale else tunnel.TunnelKind.custom;
    services.tunnel_runtime.activate(kind, endpoint) catch |err| {
        try services.tunnel_runtime.noteActivationFailure(endpoint, err);
        return std.fmt.allocPrint(ctx.allocator, "{{\"active\":false,\"kind\":\"{s}\",\"endpoint\":\"{s}\",\"status\":\"failed\",\"errorCode\":\"{s}\",\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"probeCount\":{d}}}", .{ kind.asText(), endpoint, @errorName(err), services.tunnel_runtime.health_state.asText(), services.tunnel_runtime.health_message, services.tunnel_runtime.probe_count });
    };
    return std.fmt.allocPrint(ctx.allocator, "{{\"active\":true,\"kind\":\"{s}\",\"endpoint\":\"{s}\",\"status\":\"ready\",\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"activationCount\":{d},\"probeCount\":{d},\"lastProbeStatusCode\":{?}}}", .{ kind.asText(), endpoint, services.tunnel_runtime.health_state.asText(), services.tunnel_runtime.health_message, services.tunnel_runtime.activation_count, services.tunnel_runtime.probe_count, services.tunnel_runtime.last_probe_status_code });
}
