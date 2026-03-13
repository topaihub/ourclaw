const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "gateway.reload", .method = "gateway.reload", .description = "Reload gateway host", .authority = .admin, .user_data = @ptrCast(command_services), .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *@import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    app.runtime_host.reloadGateway();
    const status = app.gateway_host.status();
    return std.fmt.allocPrint(ctx.allocator, "{{\"running\":{s},\"listenerReady\":{s},\"reloadCount\":{d}}}", .{
        if (status.running) "true" else "false",
        if (status.listener_ready) "true" else "false",
        status.reload_count,
    });
}
