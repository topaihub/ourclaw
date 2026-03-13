const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "gateway.start", .method = "gateway.start", .description = "Start gateway host", .authority = .admin, .user_data = @ptrCast(command_services), .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *@import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    app.runtime_host.start();
    const status = app.runtime_host.status();
    return std.fmt.allocPrint(ctx.allocator, "{{\"running\":true,\"hostRunning\":{s},\"gatewayRunning\":{s},\"startCount\":{d}}}", .{
        if (status.running) "true" else "false",
        if (status.gateway_running) "true" else "false",
        status.start_count,
    });
}
