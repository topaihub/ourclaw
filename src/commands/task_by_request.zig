const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");
const task_get = @import("task_get.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "task.by_request",
        .method = "task.by_request",
        .description = "Get task summary by request id",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{.{ .key = "request_id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} }},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const request_id = ctx.param("request_id").?.value.string;
    const summary = try services.framework_context.task_runner.snapshotByRequestId(ctx.allocator, request_id) orelse return error.TaskNotFound;
    defer {
        var mutable = summary;
        mutable.deinit(ctx.allocator);
    }
    return task_get.renderTaskSummary(ctx.allocator, summary);
}
