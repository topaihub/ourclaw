const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "hardware.list",
        .method = "hardware.list",
        .description = "List hardware and peripheral inventory",
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
    try writer.print("{{\"hardwareCount\":{d},\"peripheralCount\":{d},\"nodes\":[", .{ services.hardware_registry.count(), services.peripheral_registry.count() });
    for (services.hardware_registry.nodes.items, 0..) |node, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("{{\"id\":\"{s}\",\"label\":\"{s}\",\"kind\":\"{s}\",\"registeredAtMs\":{d},\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"lastErrorCode\":", .{ node.id, node.label, node.kind, node.registered_at_ms, node.health_state.asText(), node.health_message });
        if (node.last_error_code) |value| {
            try writer.print("\"{s}\"", .{value});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"probeCount\":{d},\"lastCheckedMs\":{?}}}", .{ node.probe_count, node.last_checked_ms });
    }
    try writer.writeAll("],\"peripherals\":[");
    for (services.peripheral_registry.devices.items, 0..) |device, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("{{\"id\":\"{s}\",\"kind\":\"{s}\",\"registeredAtMs\":{d},\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"lastErrorCode\":", .{ device.id, device.kind, device.registered_at_ms, device.health_state.asText(), device.health_message });
        if (device.last_error_code) |value| {
            try writer.print("\"{s}\"", .{value});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"probeCount\":{d},\"lastCheckedMs\":{?}}}", .{ device.probe_count, device.last_checked_ms });
    }
    try writer.writeAll("]}");
    return ctx.allocator.dupe(u8, buf.items);
}
