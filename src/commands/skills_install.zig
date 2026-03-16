const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "skills.install",
        .method = "skills.install",
        .description = "Install builtin skill",
        .authority = .admin,
        .user_data = @ptrCast(command_services),
        .params = &.{.{ .key = "skill_id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} }},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const skill_id = ctx.param("skill_id").?.value.string;
    try services.skillforge.installBuiltin(skill_id);
    const skill = services.skill_registry.find(skill_id).?;
    const health = @import("../domain/skills.zig").SkillRegistry.health(skill, services.framework_context.command_registry.findByMethod(skill.entry_command) != null);
    return std.fmt.allocPrint(ctx.allocator, "{{\"installed\":true,\"skillId\":\"{s}\",\"source\":\"{s}\",\"installedAtMs\":{d},\"healthState\":\"{s}\",\"healthMessage\":\"{s}\"}}", .{ skill_id, skill.source.asText(), skill.installed_at_ms, health.state.asText(), health.message });
}
