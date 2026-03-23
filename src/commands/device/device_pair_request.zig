const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "device.pair.request",
        .method = "device.pair.request",
        .description = "Create a pending device pairing request",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "channel", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "requester", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "code", .required = false, .value_kind = .string, .rules = &.{.non_empty_string} },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *@import("../../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const channel = ctx.param("channel").?.value.string;
    const requester = ctx.param("requester").?.value.string;
    const code = if (ctx.param("code")) |field| field.value.string else null;
    const created = try app.pairing_registry.create(channel, requester, code);
    return std.fmt.allocPrint(ctx.allocator, "{{\"id\":\"{s}\",\"channel\":\"{s}\",\"requester\":\"{s}\",\"code\":\"{s}\",\"state\":\"pending\",\"pendingCount\":{d}}}", .{ created.id, channel, requester, created.code, app.pairing_registry.pendingCount() });
}
