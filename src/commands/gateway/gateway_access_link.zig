const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "gateway.access.link",
        .method = "gateway.access.link",
        .description = "Generate a gateway access link",
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
    const token = services.secret_store.get("gateway:shared_token");
    const local_url = try std.fmt.allocPrint(ctx.allocator, "http://{s}:{d}/", .{ gateway.bind_host, gateway.bind_port });
    defer ctx.allocator.free(local_url);
    const local_access_url = if (token) |value|
        try std.fmt.allocPrint(ctx.allocator, "{s}?token={s}", .{ local_url, value })
    else
        try ctx.allocator.dupe(u8, local_url);
    defer ctx.allocator.free(local_access_url);

    const remote_url = if (app.tunnel_runtime.active and app.tunnel_runtime.endpoint.len > 0)
        if (token) |value|
            try std.fmt.allocPrint(ctx.allocator, "{s}?token={s}", .{ app.tunnel_runtime.endpoint, value })
        else
            try ctx.allocator.dupe(u8, app.tunnel_runtime.endpoint)
    else
        null;
    defer if (remote_url) |value| ctx.allocator.free(value);

    const preferred_url = remote_url orelse local_access_url;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.print("{{\"url\":\"{s}\",\"localUrl\":\"{s}\",\"remoteUrl\":", .{ preferred_url, local_access_url });
    if (remote_url) |value| {
        try writer.print("\"{s}\"", .{value});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(",\"preferredUrl\":\"{s}\",\"requiresToken\":{s},\"gatewayRunning\":{s}}}", .{ preferred_url, if (token != null) "true" else "false", if (gateway.running) "true" else "false" });
    return ctx.allocator.dupe(u8, buf.items);
}
