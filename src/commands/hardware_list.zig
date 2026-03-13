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
        try writer.print("{{\"id\":\"{s}\",\"label\":\"{s}\",\"registeredAtMs\":{d}}}", .{ node.id, node.label, node.registered_at_ms });
    }
    try writer.writeAll("]}");
    return ctx.allocator.dupe(u8, buf.items);
}
