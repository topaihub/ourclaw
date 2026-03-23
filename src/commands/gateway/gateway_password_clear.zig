const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "gateway.password.clear",
        .method = "gateway.password.clear",
        .description = "Clear gateway password",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const changed = services.secret_store.delete("gateway:password");
    return std.fmt.allocPrint(ctx.allocator, "{{\"cleared\":{s},\"configured\":false}}", .{if (changed) "true" else "false"});
}
