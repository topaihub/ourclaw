const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "device.pair.list",
        .method = "device.pair.list",
        .description = "List device pairing requests",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *const @import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);

    try writer.print("{{\"count\":{d},\"pendingCount\":{d},\"requirePairing\":{s},\"items\":[", .{ app.pairing_registry.count(), app.pairing_registry.pendingCount(), if (app.effective_gateway_require_pairing) "true" else "false" });
    for (app.pairing_registry.items(), 0..) |request, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("{{\"id\":\"{s}\",\"channel\":\"{s}\",\"requester\":\"{s}\",\"code\":\"{s}\",\"state\":\"{s}\",\"requestedAtMs\":{d},\"decidedAtMs\":", .{ request.id, request.channel, request.requester, request.code, request.state.asText(), request.requested_at_ms });
        if (request.decided_at_ms) |value| {
            try writer.print("{d}", .{value});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeByte('}');
    }
    try writer.writeAll("]}");
    return ctx.allocator.dupe(u8, buf.items);
}
