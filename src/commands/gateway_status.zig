const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "gateway.status",
        .method = "gateway.status",
        .description = "Return gateway host status",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *const @import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const status = app.gateway_host.status();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.print("{{\"running\":{s},\"bindHost\":\"{s}\",\"bindPort\":{d},\"requestCount\":{d},\"streamSubscriptions\":{d},\"handlerAttached\":{s},\"lastStartedMs\":", .{
        if (status.running) "true" else "false",
        status.bind_host,
        status.bind_port,
        status.request_count,
        status.stream_subscriptions,
        if (status.handler_attached) "true" else "false",
    });
    if (status.last_started_ms) |value| {
        try writer.print("{d}", .{value});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"lastStoppedMs\":");
    if (status.last_stopped_ms) |value| {
        try writer.print("{d}", .{value});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeByte('}');
    return ctx.allocator.dupe(u8, buf.items);
}
