const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "metrics.summary",
        .method = "metrics.summary",
        .description = "Return metrics snapshot",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const snapshot = services.framework_context.metrics_observer.snapshot();
    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"totalEvents\":{d},\"commandStarted\":{d},\"commandAccepted\":{d},\"commandCompleted\":{d},\"commandFailed\":{d},\"activeTasks\":{d},\"queueDepth\":{d},\"maxQueueDepth\":{d},\"configChanged\":{d},\"taskQueued\":{d},\"taskRunning\":{d},\"taskSucceeded\":{d},\"taskFailed\":{d},\"taskResultsWritten\":{d}}}",
        .{ snapshot.total_events, snapshot.command_started, snapshot.command_accepted, snapshot.command_completed, snapshot.command_failed, snapshot.active_tasks, snapshot.queue_depth, snapshot.max_queue_depth, snapshot.config_changed, snapshot.task_queued, snapshot.task_running, snapshot.task_succeeded, snapshot.task_failed, snapshot.task_results_written },
    );
}
