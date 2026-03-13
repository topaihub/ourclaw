const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "skills.run", .method = "skills.run", .description = "Run installed skill entry command", .authority = .operator, .user_data = @ptrCast(command_services), .params = &.{.{ .key = "skill_id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} }}, .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const skill_id = ctx.param("skill_id").?.value.string;
    const skill = services.skill_registry.find(skill_id) orelse return error.SkillNotFound;
    const app: *@import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = ctx.request.request_id,
        .method = skill.entry_command,
        .params = &.{},
        .source = ctx.request.source,
        .authority = ctx.request.authority,
    }, false);
    services.skill_registry.markRun(skill_id);
    const updated = services.skill_registry.find(skill_id).?;

    if (!envelope.ok) {
        return std.fmt.allocPrint(ctx.allocator, "{{\"skillId\":\"{s}\",\"entryCommand\":\"{s}\",\"status\":\"failed\",\"errorCode\":\"{s}\",\"runCount\":{d}}}", .{ skill.id, skill.entry_command, envelope.app_error.?.code, updated.run_count });
    }

    return switch (envelope.result.?) {
        .success_json => |json| blk: {
            defer ctx.allocator.free(json);
            break :blk std.fmt.allocPrint(ctx.allocator, "{{\"skillId\":\"{s}\",\"entryCommand\":\"{s}\",\"status\":\"completed\",\"runCount\":{d},\"result\":{s}}}", .{ skill.id, skill.entry_command, updated.run_count, json });
        },
        .task_accepted => |accepted| std.fmt.allocPrint(ctx.allocator, "{{\"skillId\":\"{s}\",\"entryCommand\":\"{s}\",\"status\":\"accepted\",\"runCount\":{d},\"taskId\":\"{s}\"}}", .{ skill.id, skill.entry_command, updated.run_count, accepted.task_id }),
    };
}
