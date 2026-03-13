const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "hardware.register", .method = "hardware.register", .description = "Register hardware node", .authority = .admin, .user_data = @ptrCast(command_services), .params = &.{
        .{ .key = "id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
        .{ .key = "label", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
    }, .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const id = ctx.param("id").?.value.string;
    const label = ctx.param("label").?.value.string;
    try services.hardware_registry.register(id, label);
    const node = services.hardware_registry.find(id).?;
    return std.fmt.allocPrint(ctx.allocator, "{{\"registered\":true,\"id\":\"{s}\",\"registeredAtMs\":{d}}}", .{ id, node.registered_at_ms });
}
