const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "tunnel.status",
        .method = "tunnel.status",
        .description = "Return tunnel runtime status",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const tunnel = services.tunnel_runtime;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.print("{{\"active\":{s},\"kind\":\"{s}\",\"endpoint\":\"{s}\",\"activationCount\":{d},\"lastActivatedMs\":", .{
        if (tunnel.active) "true" else "false",
        tunnel.kind.asText(),
        tunnel.endpoint,
        tunnel.activation_count,
    });
    if (tunnel.last_activated_ms) |value| {
        try writer.print("{d}", .{value});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"lastDeactivatedMs\":");
    if (tunnel.last_deactivated_ms) |value| {
        try writer.print("{d}", .{value});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeByte('}');
    return ctx.allocator.dupe(u8, buf.items);
}
