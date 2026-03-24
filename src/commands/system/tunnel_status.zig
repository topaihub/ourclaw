const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

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
    try writer.print("{{\"active\":{s},\"kind\":\"{s}\",\"endpoint\":\"{s}\",\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"lastErrorCode\":", .{
        if (tunnel.active) "true" else "false",
        tunnel.kind.asText(),
        tunnel.endpoint,
        tunnel.health_state.asText(),
        tunnel.health_message,
    });
    if (tunnel.last_error_code) |value| {
        try writer.print("\"{s}\"", .{value});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(",\"activationCount\":{d},\"probeCount\":{d},\"lastProbeMs\":", .{ tunnel.activation_count, tunnel.probe_count });
    if (tunnel.last_probe_ms) |value| {
        try writer.print("{d}", .{value});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"lastProbeStatusCode\":");
    if (tunnel.last_probe_status_code) |value| {
        try writer.print("{d}", .{value});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"lastActivatedMs\":");
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
