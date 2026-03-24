const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

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
    const observer_events = try services.framework_context.memory_observer.snapshot(ctx.allocator);
    defer {
        for (observer_events) |*event| event.deinit(ctx.allocator);
        ctx.allocator.free(observer_events);
    }

    var last_execution_id: ?[]const u8 = null;
    var last_session_id: ?[]const u8 = null;
    var correlated_stream_events: usize = 0;
    var index = observer_events.len;
    while (index > 0) {
        index -= 1;
        const event = observer_events[index];
        if (std.mem.eql(u8, event.topic, "stream.output")) {
            if (extractJsonStringField(event.payload_json, "executionId") != null) correlated_stream_events += 1;
            if (last_execution_id == null) last_execution_id = extractJsonStringField(event.payload_json, "executionId");
            if (last_session_id == null) last_session_id = extractJsonStringField(event.payload_json, "sessionId");
        }
    }

    const last_execution_json = if (last_execution_id) |value|
        try std.fmt.allocPrint(ctx.allocator, "\"{s}\"", .{value})
    else
        try ctx.allocator.dupe(u8, "null");
    defer ctx.allocator.free(last_execution_json);

    const last_session_json = if (last_session_id) |value|
        try std.fmt.allocPrint(ctx.allocator, "\"{s}\"", .{value})
    else
        try ctx.allocator.dupe(u8, "null");
    defer ctx.allocator.free(last_session_json);

    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"totalEvents\":{d},\"commandStarted\":{d},\"commandAccepted\":{d},\"commandCompleted\":{d},\"commandFailed\":{d},\"activeTasks\":{d},\"queueDepth\":{d},\"maxQueueDepth\":{d},\"configChanged\":{d},\"taskQueued\":{d},\"taskRunning\":{d},\"taskSucceeded\":{d},\"taskFailed\":{d},\"taskResultsWritten\":{d},\"subscriptionCount\":{d},\"correlatedStreamEvents\":{d},\"lastExecutionId\":{s},\"lastSessionId\":{s}}}",
        .{ snapshot.total_events, snapshot.command_started, snapshot.command_accepted, snapshot.command_completed, snapshot.command_failed, snapshot.active_tasks, snapshot.queue_depth, snapshot.max_queue_depth, snapshot.config_changed, snapshot.task_queued, snapshot.task_running, snapshot.task_succeeded, snapshot.task_failed, snapshot.task_results_written, services.framework_context.event_bus.subscriptionCount(), correlated_stream_events, last_execution_json, last_session_json },
    );
}

fn extractJsonStringField(payload_json: []const u8, key: []const u8) ?[]const u8 {
    var marker_buf: [128]u8 = undefined;
    const marker = std.fmt.bufPrint(&marker_buf, "\"{s}\":\"", .{key}) catch return null;
    const start = std.mem.indexOf(u8, payload_json, marker) orelse return null;
    const value_start = start + marker.len;
    const rest = payload_json[value_start..];
    const end = std.mem.indexOfScalar(u8, rest, '"') orelse return null;
    return rest[0..end];
}
