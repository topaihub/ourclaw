const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "gateway.password.set",
        .method = "gateway.password.set",
        .description = "Set gateway password",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{.{ .key = "password", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} }},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const password = ctx.param("password").?.value.string;
    try services.secret_store.put("gateway:password", password);
    return std.fmt.allocPrint(ctx.allocator, "{{\"configured\":true,\"length\":{d}}}", .{password.len});
}
