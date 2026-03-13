const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");
const tunnel = @import("../domain/tunnel_runtime.zig");

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
    services.tunnel_runtime.activate(kind, endpoint);
    return std.fmt.allocPrint(ctx.allocator, "{{\"active\":true,\"kind\":\"{s}\",\"activationCount\":{d}}}", .{ kind.asText(), services.tunnel_runtime.activation_count });
}
