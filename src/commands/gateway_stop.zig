const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "gateway.stop", .method = "gateway.stop", .description = "Stop gateway host", .authority = .admin, .user_data = @ptrCast(command_services), .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *@import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    app.runtime_host.stop();
    const status = app.runtime_host.status();
    return std.fmt.allocPrint(ctx.allocator, "{{\"running\":false,\"hostRunning\":{s},\"gatewayRunning\":{s},\"stopCount\":{d}}}", .{
        if (status.running) "true" else "false",
        if (status.gateway_running) "true" else "false",
        status.stop_count,
    });
}
