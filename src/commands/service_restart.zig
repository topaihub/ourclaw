const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "service.restart", .method = "service.restart", .description = "Restart service", .authority = .admin, .user_data = @ptrCast(command_services), .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *@import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const restart = app.service_manager.restart();
    const status = app.service_manager.status();
    return std.fmt.allocPrint(ctx.allocator, "{{\"restarted\":true,\"runtimeRunning\":{s},\"restartCount\":{d},\"stopCount\":{d},\"stopApplied\":{s},\"startApplied\":{s}}}", .{ if (status.runtime_running) "true" else "false", status.restart_count, status.stop_count, if (restart.stop_changed) "true" else "false", if (restart.start_changed) "true" else "false" });
}
