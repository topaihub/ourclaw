const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "voice.status", .method = "voice.status", .description = "Return voice runtime status", .authority = .operator, .user_data = @ptrCast(command_services), .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const voice = services.voice_runtime;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.print("{{\"active\":{s},\"peripheralId\":", .{if (voice.active) "true" else "false"});
    if (voice.attached_peripheral_id.len > 0) {
        try writer.print("\"{s}\"", .{voice.attached_peripheral_id});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(",\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"lastErrorCode\":", .{ voice.health_state.asText(), voice.health_message });
    if (voice.last_error_code) |value| {
        try writer.print("\"{s}\"", .{value});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(",\"attachCount\":{d},\"lastAttachedMs\":{?},\"lastDetachedMs\":{?},\"lastCheckedMs\":{?}}}", .{ voice.attach_count, voice.last_attached_ms, voice.last_detached_ms, voice.last_checked_ms });
    return ctx.allocator.dupe(u8, buf.items);
}
