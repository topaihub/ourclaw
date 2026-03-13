const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "service.install", .method = "service.install", .description = "Install service", .authority = .admin, .user_data = @ptrCast(command_services), .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *const @import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const mutable: *@import("../runtime/app_context.zig").AppContext = @constCast(app);
    const changed = mutable.service_manager.install();
    const status = mutable.service_manager.status();
    return std.fmt.allocPrint(ctx.allocator, "{{\"installed\":true,\"enabled\":{s},\"installCount\":{d},\"changed\":{s},\"daemonProjected\":true}}", .{ if (status.enabled) "true" else "false", status.install_count, if (changed) "true" else "false" });
}
