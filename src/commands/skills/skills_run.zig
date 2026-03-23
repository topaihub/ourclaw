const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "skills.run", .method = "skills.run", .description = "Run installed skill entry command", .authority = .operator, .user_data = @ptrCast(command_services), .params = &.{.{ .key = "skill_id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} }}, .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const skill_id = ctx.param("skill_id").?.value.string;
    const skill = services.skill_registry.find(skill_id) orelse return error.SkillNotFound;
    if (services.framework_context.command_registry.findByMethod(skill.entry_command) == null) {
        try services.skill_registry.markRunFailure(skill_id, "SKILL_ENTRY_COMMAND_MISSING");
        const updated_missing = services.skill_registry.find(skill_id).?;
        const health_missing = @import("../../domain/skills.zig").SkillRegistry.health(updated_missing, false);
        return std.fmt.allocPrint(ctx.allocator, "{{\"skillId\":\"{s}\",\"entryCommand\":\"{s}\",\"status\":\"failed\",\"errorCode\":\"SKILL_ENTRY_COMMAND_MISSING\",\"runCount\":{d},\"healthState\":\"{s}\",\"healthMessage\":\"{s}\"}}", .{ skill.id, skill.entry_command, updated_missing.run_count, health_missing.state.asText(), health_missing.message });
    }
    const app: *@import("../../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = ctx.request.request_id,
        .method = skill.entry_command,
        .params = &.{},
        .source = ctx.request.source,
        .authority = ctx.request.authority,
    }, false);

    if (!envelope.ok) {
        try services.skill_registry.markRunFailure(skill_id, envelope.app_error.?.code);
        const failed = services.skill_registry.find(skill_id).?;
        const health = @import("../../domain/skills.zig").SkillRegistry.health(failed, true);
        return std.fmt.allocPrint(ctx.allocator, "{{\"skillId\":\"{s}\",\"entryCommand\":\"{s}\",\"status\":\"failed\",\"errorCode\":\"{s}\",\"runCount\":{d},\"healthState\":\"{s}\",\"healthMessage\":\"{s}\"}}", .{ skill.id, skill.entry_command, envelope.app_error.?.code, failed.run_count, health.state.asText(), health.message });
    }

    services.skill_registry.markRunSuccess(skill_id);
    const updated = services.skill_registry.find(skill_id).?;
    const health = @import("../../domain/skills.zig").SkillRegistry.health(updated, true);

    return switch (envelope.result.?) {
        .success_json => |json| blk: {
            defer ctx.allocator.free(json);
            break :blk std.fmt.allocPrint(ctx.allocator, "{{\"skillId\":\"{s}\",\"entryCommand\":\"{s}\",\"status\":\"completed\",\"runCount\":{d},\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"result\":{s}}}", .{ skill.id, skill.entry_command, updated.run_count, health.state.asText(), health.message, json });
        },
        .task_accepted => |accepted| std.fmt.allocPrint(ctx.allocator, "{{\"skillId\":\"{s}\",\"entryCommand\":\"{s}\",\"status\":\"accepted\",\"runCount\":{d},\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"taskId\":\"{s}\"}}", .{ skill.id, skill.entry_command, updated.run_count, health.state.asText(), health.message, accepted.task_id }),
    };
}
