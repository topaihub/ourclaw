const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "heartbeat.status",
        .method = "heartbeat.status",
        .description = "Return heartbeat snapshot",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *const @import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const snapshot = app.heartbeat.snapshot();
    return std.fmt.allocPrint(ctx.allocator, "{{\"beatCount\":{d},\"healthy\":{s}}}", .{ snapshot.beat_count, if (snapshot.healthy) "true" else "false" });
}
