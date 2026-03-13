const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "peripheral.register", .method = "peripheral.register", .description = "Register peripheral device", .authority = .admin, .user_data = @ptrCast(command_services), .params = &.{
        .{ .key = "id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
        .{ .key = "kind", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
    }, .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const id = ctx.param("id").?.value.string;
    const kind = ctx.param("kind").?.value.string;
    try services.peripheral_registry.register(id, kind);
    return std.fmt.allocPrint(ctx.allocator, "{{\"registered\":true,\"id\":\"{s}\"}}", .{id});
}
