const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "device.unpair",
        .method = "device.unpair",
        .description = "Unpair an approved device and revoke its token",
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
    const decision = app.pairing_registry.unpair(id);
    return std.fmt.allocPrint(ctx.allocator, "{{\"id\":\"{s}\",\"changed\":{s},\"state\":\"{s}\",\"token\":null,\"pendingCount\":{d}}}", .{ id, if (decision.changed) "true" else "false", decision.state.asText(), app.pairing_registry.pendingCount() });
}
