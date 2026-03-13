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
    return std.fmt.allocPrint(ctx.allocator, "{{\"installed\":true,\"skillId\":\"{s}\",\"installedAtMs\":{d}}}", .{ skill_id, skill.installed_at_ms });
}
