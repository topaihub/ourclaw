const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "skills.list",
        .method = "skills.list",
        .description = "List installed skills",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const skills_model = @import("../../domain/skills.zig");
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.writeByte('[');
    for (services.skill_registry.skills.items, 0..) |skill, index| {
        if (index > 0) try writer.writeByte(',');
        const command_exists = services.framework_context.command_registry.findByMethod(skill.entry_command) != null;
        const health = skills_model.SkillRegistry.health(&skill, command_exists);
        try writer.print("{{\"id\":\"{s}\",\"label\":\"{s}\",\"entryCommand\":\"{s}\",\"source\":\"{s}\",\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"lastRunStatus\":\"{s}\",\"lastErrorCode\":", .{ skill.id, skill.label, skill.entry_command, skill.source.asText(), health.state.asText(), health.message, skill.last_run_status.asText() });
        if (skill.last_error_code) |value| {
            try writer.print("\"{s}\"", .{value});
        } else {
            try writer.writeAll("null");
        }
        try writer.print(",\"installedAtMs\":{d},\"runCount\":{d},\"lastRunMs\":", .{ skill.installed_at_ms, skill.run_count });
        if (skill.last_run_ms) |value| {
            try writer.print("{d}", .{value});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
    return ctx.allocator.dupe(u8, buf.items);
}
