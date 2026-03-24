const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "device.pair.reject",
        .method = "device.pair.reject",
        .description = "Reject a pending device pairing request",
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
    const decision = app.pairing_registry.reject(id);
    return std.fmt.allocPrint(ctx.allocator, "{{\"id\":\"{s}\",\"changed\":{s},\"state\":\"{s}\",\"pendingCount\":{d}}}", .{ id, if (decision.changed) "true" else "false", decision.state.asText(), app.pairing_registry.pendingCount() });
}
