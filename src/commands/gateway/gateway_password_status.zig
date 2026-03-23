const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "gateway.password.status",
        .method = "gateway.password.status",
        .description = "Show gateway password status",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const password = services.secret_store.get("gateway:password");
    return std.fmt.allocPrint(ctx.allocator, "{{\"configured\":{s},\"length\":{d}}}", .{ if (password != null) "true" else "false", if (password) |value| value.len else 0 });
}
