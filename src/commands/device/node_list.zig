const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "node.list",
        .method = "node.list",
        .description = "List connected runtime nodes",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    var approved_pairing_count: usize = 0;
    for (services.pairing_registry.items()) |request| {
        if (request.state == .approved) approved_pairing_count += 1;
    }

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);

    try writer.print("{{\"count\":{d},\"approvedPairingCount\":{d},\"items\":[", .{ services.hardware_registry.count(), approved_pairing_count });
    for (services.hardware_registry.nodes.items, 0..) |node, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("{{\"id\":\"{s}\",\"label\":\"{s}\",\"kind\":\"{s}\",\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"registeredAtMs\":{d},\"probeCount\":{d},\"lastCheckedMs\":{?},\"lastErrorCode\":", .{ node.id, node.label, node.kind, node.health_state.asText(), node.health_message, node.registered_at_ms, node.probe_count, node.last_checked_ms });
        if (node.last_error_code) |value| {
            try writer.print("\"{s}\"", .{value});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeByte('}');
    }
    try writer.writeAll("]}");
    return ctx.allocator.dupe(u8, buf.items);
}
