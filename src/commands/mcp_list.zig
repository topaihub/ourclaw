const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

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
        try writer.print("{{\"id\":\"{s}\",\"transport\":\"{s}\",\"registeredAtMs\":{d}}}", .{ server.id, server.transport, server.registered_at_ms });
    }
    try writer.writeByte(']');
    return ctx.allocator.dupe(u8, buf.items);
}
