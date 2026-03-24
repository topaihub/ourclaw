const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "mcp.list",
        .method = "mcp.list",
        .description = "List MCP servers",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.writeByte('[');
    for (services.mcp_runtime.servers.items, 0..) |server, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("{{\"id\":\"{s}\",\"transport\":\"{s}\",\"endpoint\":", .{ server.id, server.transport });
        if (server.endpoint) |value| {
            try writer.print("\"{s}\"", .{value});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"registeredAtMs\":{d},\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"lastErrorCode\":", .{ server.registered_at_ms, server.health_state.asText(), server.health_message });
        if (server.last_error_code) |value| {
            try writer.print("\"{s}\"", .{value});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"probeCount\":{d},\"lastCheckedMs\":{?},\"lastConnectedMs\":{?}}}", .{ server.probe_count, server.last_checked_ms, server.last_connected_ms });
    }
    try writer.writeByte(']');
    return ctx.allocator.dupe(u8, buf.items);
}
