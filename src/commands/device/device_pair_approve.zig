const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "device.pair.approve",
        .method = "device.pair.approve",
        .description = "Approve a pending device pairing request",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{.{ .key = "id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} }},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *@import("../../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const id = ctx.param("id").?.value.string;
    const decision = app.pairing_registry.approve(id);
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.print("{{\"id\":\"{s}\",\"changed\":{s},\"state\":\"{s}\",\"pendingCount\":{d},\"token\":", .{ id, if (decision.changed) "true" else "false", decision.state.asText(), app.pairing_registry.pendingCount() });
    if (decision.token) |value| {
        try writer.print("\"{s}\"", .{value});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeByte('}');
    return ctx.allocator.dupe(u8, buf.items);
}
