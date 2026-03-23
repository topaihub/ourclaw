const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "mcp.register", .method = "mcp.register", .description = "Register MCP server", .authority = .admin, .user_data = @ptrCast(command_services), .params = &.{
        .{ .key = "id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
        .{ .key = "transport", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
        .{ .key = "endpoint", .required = false, .value_kind = .string },
    }, .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const id = ctx.param("id").?.value.string;
    const transport = ctx.param("transport").?.value.string;
    const endpoint = if (ctx.param("endpoint")) |field| field.value.string else null;
    try services.mcp_runtime.register(id, transport, endpoint);
    const server = services.mcp_runtime.find(id).?;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.print("{{\"registered\":true,\"id\":\"{s}\",\"transport\":\"{s}\",\"endpoint\":", .{ id, server.transport });
    if (server.endpoint) |value| {
        try writer.print("\"{s}\"", .{value});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(",\"registeredAtMs\":{d},\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"probeCount\":{d},\"lastCheckedMs\":{?},\"lastConnectedMs\":{?}}}", .{ server.registered_at_ms, server.health_state.asText(), server.health_message, server.probe_count, server.last_checked_ms, server.last_connected_ms });
    return ctx.allocator.dupe(u8, buf.items);
}
