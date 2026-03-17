const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

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
    const app: *const @import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const gateway = app.gateway_host.status();
    const token = services.secret_store.get("gateway:shared_token");
    const base_url = try std.fmt.allocPrint(ctx.allocator, "http://{s}:{d}/", .{ gateway.bind_host, gateway.bind_port });
    defer ctx.allocator.free(base_url);
    const access_url = if (token) |value|
        try std.fmt.allocPrint(ctx.allocator, "{s}?token={s}", .{ base_url, value })
    else
        try ctx.allocator.dupe(u8, base_url);
    defer ctx.allocator.free(access_url);

    return std.fmt.allocPrint(ctx.allocator, "{{\"url\":\"{s}\",\"requiresToken\":{s},\"gatewayRunning\":{s}}}", .{ access_url, if (token != null) "true" else "false", if (gateway.running) "true" else "false" });
}
