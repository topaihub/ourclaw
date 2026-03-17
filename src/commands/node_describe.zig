const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "node.describe",
        .method = "node.describe",
        .description = "Describe a specific runtime node",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{.{ .key = "id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} }},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const id = ctx.param("id").?.value.string;
    const node = services.hardware_registry.find(id) orelse return error.HardwareNodeNotFound;

    var approved_pairing_count: usize = 0;
    for (services.pairing_registry.items()) |request| {
        if (request.state == .approved) approved_pairing_count += 1;
    }

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.print("{{\"id\":\"{s}\",\"label\":\"{s}\",\"kind\":\"{s}\",\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"registeredAtMs\":{d},\"probeCount\":{d},\"lastCheckedMs\":{?},\"lastErrorCode\":", .{
        node.id,
        node.label,
        node.kind,
        node.health_state.asText(),
        node.health_message,
        node.registered_at_ms,
        node.probe_count,
        node.last_checked_ms,
    });
    if (node.last_error_code) |value| {
        try writer.print("\"{s}\"", .{value});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(",\"approvedPairingCount\":{d}}}", .{approved_pairing_count});
    return ctx.allocator.dupe(u8, buf.items);
}
