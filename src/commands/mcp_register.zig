const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "mcp.register", .method = "mcp.register", .description = "Register MCP server", .authority = .admin, .user_data = @ptrCast(command_services), .params = &.{
        .{ .key = "id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
        .{ .key = "transport", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
    }, .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const id = ctx.param("id").?.value.string;
    const transport = ctx.param("transport").?.value.string;
    try services.mcp_runtime.register(id, transport);
    const server = services.mcp_runtime.find(id).?;
    return std.fmt.allocPrint(ctx.allocator, "{{\"registered\":true,\"id\":\"{s}\",\"registeredAtMs\":{d}}}", .{ id, server.registered_at_ms });
}
