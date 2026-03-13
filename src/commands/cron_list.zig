const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "cron.list",
        .method = "cron.list",
        .description = "List cron jobs",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *const @import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.writeByte('[');
    for (app.cron_scheduler.jobs.items, 0..) |job, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("{{\"id\":\"{s}\",\"schedule\":\"{s}\",\"command\":\"{s}\",\"runCount\":{d},\"schedulerTickCount\":{d},\"executedJobCount\":{d},\"lastRunMs\":", .{ job.id, job.schedule, job.command, job.run_count, app.cron_scheduler.tick_count, app.cron_scheduler.executed_job_count });
        if (job.last_run_ms) |value| {
            try writer.print("{d}", .{value});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
    return ctx.allocator.dupe(u8, buf.items);
}
