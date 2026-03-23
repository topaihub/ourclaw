const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "gateway.token.status",
        .method = "gateway.token.status",
        .description = "Show shared gateway token status",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const token = services.secret_store.get("gateway:shared_token");
    return std.fmt.allocPrint(ctx.allocator, "{{\"configured\":{s},\"length\":{d}}}", .{ if (token != null) "true" else "false", if (token) |value| value.len else 0 });
}
