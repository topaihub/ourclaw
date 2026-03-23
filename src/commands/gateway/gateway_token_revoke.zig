const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "gateway.token.revoke",
        .method = "gateway.token.revoke",
        .description = "Revoke the shared gateway token",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const changed = services.secret_store.delete("gateway:shared_token");
    return std.fmt.allocPrint(ctx.allocator, "{{\"revoked\":{s},\"configured\":false}}", .{if (changed) "true" else "false"});
}
