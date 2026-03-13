const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

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
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.writeByte('[');
    for (services.skill_registry.skills.items, 0..) |skill, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("{{\"id\":\"{s}\",\"label\":\"{s}\",\"entryCommand\":\"{s}\",\"installedAtMs\":{d},\"runCount\":{d},\"lastRunMs\":", .{ skill.id, skill.label, skill.entry_command, skill.installed_at_ms, skill.run_count });
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
