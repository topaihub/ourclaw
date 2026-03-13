const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "service.start", .method = "service.start", .description = "Start service", .authority = .admin, .user_data = @ptrCast(command_services), .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *@import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    app.service_manager.start();
    const status = app.service_manager.status();
    return std.fmt.allocPrint(ctx.allocator, "{{\"started\":true,\"runtimeRunning\":{s},\"startCount\":{d}}}", .{ if (status.runtime_running) "true" else "false", status.start_count });
}
