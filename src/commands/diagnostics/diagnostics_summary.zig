const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "diagnostics.summary",
        .method = "diagnostics.summary",
        .description = "Return runtime diagnostics summary",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const metrics = services.framework_context.metrics_observer.snapshot();
    const latest_seq = services.framework_context.event_bus.latestSeq();
    const task_count = services.framework_context.task_runner.count();
    const running_tasks = services.framework_context.task_runner.countByState(.running);
    const queued_tasks = services.framework_context.task_runner.countByState(.queued);
    const app: *const @import("../../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const host_status = app.runtime_host.status();
    const service_status = app.service_manager.status();

    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"providers\":{d},\"channels\":{d},\"tools\":{d},\"commands\":{d},\"configEntries\":{d},\"sessions\":{d},\"memoryEntries\":{d},\"observerEvents\":{d},\"tasks\":{{\"total\":{d},\"queued\":{d},\"running\":{d}}},\"events\":{{\"latestSeq\":{d},\"subscriptions\":{d}}},\"runtimeHost\":{{\"running\":{s},\"gatewayRunning\":{s},\"loopActive\":{s}}},\"service\":{{\"installed\":{s},\"state\":\"{s}\"}},\"metrics\":{{\"totalEvents\":{d},\"activeTasks\":{d},\"queueDepth\":{d},\"configChanged\":{d}}}}}",
        .{
            services.provider_registry.count(),
            services.channel_registry.count(),
            services.tool_registry.count(),
            services.framework_context.command_registry.count(),
            services.framework_context.config_store.count(),
            services.session_store.count(),
            services.memory_runtime.count(),
            services.framework_context.memory_observer.count(),
            task_count,
            queued_tasks,
            running_tasks,
            latest_seq,
            services.framework_context.event_bus.subscriptionCount(),
            if (host_status.running) "true" else "false",
            if (host_status.gateway_running) "true" else "false",
            if (host_status.loop_active) "true" else "false",
            if (service_status.installed) "true" else "false",
            service_status.state.asText(),
            metrics.total_events,
            metrics.active_tasks,
            metrics.queue_depth,
            metrics.config_changed,
        },
    );
}
