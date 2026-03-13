const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "cron.tick", .method = "cron.tick", .description = "Tick cron scheduler", .authority = .admin, .user_data = @ptrCast(command_services), .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *@import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const executed = app.runtime_host.tick();
    const tick_ms = app.cron_scheduler.last_tick_ms;
    const heartbeat = app.heartbeat.snapshot();

    var dispatcher = app.makeDispatcher();
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.print("{{\"executed\":{d},\"tickCount\":{d},\"executedJobCount\":{d},\"heartbeatBeatCount\":{d},\"jobs\":[", .{ executed, app.cron_scheduler.tick_count, app.cron_scheduler.executed_job_count, heartbeat.beat_count });
    var emitted_jobs: usize = 0;
    for (app.cron_scheduler.jobs.items, 0..) |job, index| {
        if (tick_ms == null or job.last_run_ms == null or job.last_run_ms.? != tick_ms.?) continue;
        _ = index;
        if (emitted_jobs > 0) try writer.writeByte(',');
        const envelope = try dispatcher.dispatch(.{
            .request_id = ctx.request.request_id,
            .method = job.command,
            .params = &.{},
            .source = ctx.request.source,
            .authority = ctx.request.authority,
        }, false);
        if (envelope.ok) {
            switch (envelope.result.?) {
                .success_json => |json| {
                    defer ctx.allocator.free(json);
                    try writer.print("{{\"id\":\"{s}\",\"status\":\"completed\",\"result\":{s}}}", .{ job.id, json });
                },
                .task_accepted => |accepted| {
                    try writer.print("{{\"id\":\"{s}\",\"status\":\"accepted\",\"taskId\":\"{s}\"}}", .{ job.id, accepted.task_id });
                },
            }
        } else {
            try writer.print("{{\"id\":\"{s}\",\"status\":\"failed\",\"errorCode\":\"{s}\"}}", .{ job.id, envelope.app_error.?.code });
        }
        emitted_jobs += 1;
    }
    try writer.writeAll("]}");
    return ctx.allocator.dupe(u8, buf.items);
}
