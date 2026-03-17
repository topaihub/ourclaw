const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");
const tunnel = @import("../domain/tunnel_runtime.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "gateway.remote.enable",
        .method = "gateway.remote.enable",
        .description = "Enable minimal remote gateway access",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "endpoint", .required = false, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "kind", .required = false, .value_kind = .string, .rules = &.{.non_empty_string} },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *const @import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const endpoint = if (ctx.param("endpoint")) |field| field.value.string else "mock://tunnel/healthy";
    const kind_text = if (ctx.param("kind")) |field| field.value.string else "custom";
    const kind = if (std.mem.eql(u8, kind_text, "cloudflare")) tunnel.TunnelKind.cloudflare else if (std.mem.eql(u8, kind_text, "ngrok")) tunnel.TunnelKind.ngrok else if (std.mem.eql(u8, kind_text, "tailscale")) tunnel.TunnelKind.tailscale else tunnel.TunnelKind.custom;

    services.tunnel_runtime.activate(kind, endpoint) catch |err| {
        try services.tunnel_runtime.noteActivationFailure(endpoint, err);
        return std.fmt.allocPrint(ctx.allocator, "{{\"enabled\":false,\"errorCode\":\"{s}\"}}", .{@errorName(err)});
    };

    if (services.secret_store.get("gateway:shared_token") == null) {
        var bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&bytes);
        var token_buf: [32]u8 = undefined;
        encodeHexLower(&token_buf, &bytes);
        try services.secret_store.put("gateway:shared_token", token_buf[0..]);
    }

    const gateway = app.gateway_host.status();
    const token = services.secret_store.get("gateway:shared_token").?;
    const local_url = try std.fmt.allocPrint(ctx.allocator, "http://{s}:{d}/?token={s}", .{ gateway.bind_host, gateway.bind_port, token });
    defer ctx.allocator.free(local_url);
    const remote_url = try std.fmt.allocPrint(ctx.allocator, "{s}?token={s}", .{ services.tunnel_runtime.endpoint, token });
    defer ctx.allocator.free(remote_url);

    return std.fmt.allocPrint(ctx.allocator, "{{\"enabled\":true,\"kind\":\"{s}\",\"endpoint\":\"{s}\",\"localUrl\":\"{s}\",\"remoteUrl\":\"{s}\",\"preferredUrl\":\"{s}\"}}", .{ services.tunnel_runtime.kind.asText(), services.tunnel_runtime.endpoint, local_url, remote_url, remote_url });
}

fn encodeHexLower(out: *[32]u8, bytes: *const [16]u8) void {
    const alphabet = "0123456789abcdef";
    for (bytes.*, 0..) |byte, index| {
        out[index * 2] = alphabet[byte >> 4];
        out[index * 2 + 1] = alphabet[byte & 0x0f];
    }
}
