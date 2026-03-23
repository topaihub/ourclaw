const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "cron.register", .method = "cron.register", .description = "Register cron job", .authority = .admin, .user_data = @ptrCast(command_services), .params = &.{
        .{ .key = "id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
        .{ .key = "schedule", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
        .{ .key = "command", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
    }, .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *@import("../../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const id = ctx.param("id").?.value.string;
    const schedule = ctx.param("schedule").?.value.string;
    const command = ctx.param("command").?.value.string;
    try app.cron_scheduler.register(id, schedule, command);
    return std.fmt.allocPrint(ctx.allocator, "{{\"registered\":true,\"id\":\"{s}\"}}", .{id});
}
