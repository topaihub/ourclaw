const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "service.stop", .method = "service.stop", .description = "Stop service", .authority = .admin, .user_data = @ptrCast(command_services), .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *@import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const changed = app.service_manager.stop();
    const status = app.service_manager.status();
    return std.fmt.allocPrint(ctx.allocator, "{{\"stopped\":true,\"runtimeRunning\":{s},\"pid\":{?},\"lockHeld\":{s},\"stopCount\":{d},\"changed\":{s}}}", .{ if (status.runtime_running) "true" else "false", status.pid, if (status.lock_held) "true" else "false", status.stop_count, if (changed) "true" else "false" });
}
