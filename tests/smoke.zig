const std = @import("std");
const framework = @import("framework");
const ourclaw = @import("ourclaw");

test "external smoke test can import scaffold modules" {
    try std.testing.expectEqualStrings("framework", framework.PACKAGE_NAME);
    try std.testing.expectEqualStrings("ourclaw", ourclaw.APP_NAME);
    try std.testing.expectEqualStrings("commands", ourclaw.commands.MODULE_NAME);
    try std.testing.expectEqualStrings("domain", ourclaw.domain.MODULE_NAME);
    try std.testing.expectEqualStrings("compat", ourclaw.compat.MODULE_NAME);
    try std.testing.expectEqualStrings("interfaces", ourclaw.interfaces.MODULE_NAME);
    try std.testing.expectEqualStrings("providers", ourclaw.providers.MODULE_NAME);
    try std.testing.expectEqualStrings("channels", ourclaw.channels.MODULE_NAME);
    try std.testing.expectEqualStrings("tools", ourclaw.tools.MODULE_NAME);
    try std.testing.expectEqualStrings("runtime", ourclaw.runtime.MODULE_NAME);
}

test "app meta command returns expanded runtime metadata" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_app_meta_smoke",
        .method = "app.meta",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer if (envelope.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };

    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"build\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"capabilities\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"health\":{") != null);
}

test "config get supports batch output with metadata and source" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    const params = [_]framework.ValidationField{
        .{ .key = "paths", .value = .{ .string = "gateway.host,logging.level,missing.field" } },
    };

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_config_get_batch",
        .method = "config.get",
        .params = params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer if (envelope.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };

    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"count\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"metadata\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"category\":\"gateway\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"displayGroup\":\"network_bind\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"defaultValue\":\"127.0.0.1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"source\":\"bootstrap_default\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"errorCode\":\"CONFIG_FIELD_UNKNOWN\"") != null);
}

test "logs recent supports level subsystem and trace filters" {
    const TraceState = struct {
        trace_id: []const u8,
        request_id: []const u8,

        fn current(ptr: *anyopaque) framework.TraceContext {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            return .{
                .trace_id = self.trace_id,
                .request_id = self.request_id,
            };
        }
    };

    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    var trace_state = TraceState{
        .trace_id = "trc_logs_recent",
        .request_id = "req_logs_recent",
    };
    app.framework_context.logger.trace_context_provider = .{
        .ptr = @ptrCast(&trace_state),
        .current = TraceState.current,
    };

    app.framework_context.logger.child("providers/openai").info("provider log", &.{});
    app.framework_context.logger.child("config").warn("config log", &.{});

    const params = [_]framework.ValidationField{
        .{ .key = "limit", .value = .{ .integer = 10 } },
        .{ .key = "level", .value = .{ .string = "info" } },
        .{ .key = "subsystem", .value = .{ .string = "providers" } },
        .{ .key = "trace_id", .value = .{ .string = "trc_logs_recent" } },
    };

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_logs_recent_cmd",
        .method = "logs.recent",
        .params = params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer if (envelope.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };

    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"count\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"subsystem\":\"providers/openai\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"traceId\":\"trc_logs_recent\"") != null);
}

test "config set supports preview and diff details" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    const params = [_]framework.ValidationField{
        .{ .key = "path", .value = .{ .string = "gateway.port" } },
        .{ .key = "value", .value = .{ .string = "9090" } },
        .{ .key = "preview", .value = .{ .boolean = true } },
    };

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_config_set_preview",
        .method = "config.set",
        .params = params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer if (envelope.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };

    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"preview\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"sideEffectKind\":\"restart_required\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"allowedSources\":[\"bootstrap_default\",\"runtime_store\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"diff\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"newValue\":9090") != null);
    try std.testing.expectEqual(@as(i64, 8080), app.framework_context.config_store.get("gateway.port").?.integer);
}

test "config set writes summary and applies risk-confirmed change" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    const params = [_]framework.ValidationField{
        .{ .key = "path", .value = .{ .string = "gateway.host" } },
        .{ .key = "value", .value = .{ .string = "0.0.0.0" } },
        .{ .key = "confirm_risk", .value = .{ .boolean = true } },
    };

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_config_set_apply",
        .method = "config.set",
        .params = params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (envelope.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };

    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"applied\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"writeSummary\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"sideEffectKind\":\"restart_required\"") != null);
    try std.testing.expectEqualStrings("0.0.0.0", app.framework_context.config_store.get("gateway.host").?.string);
}

test "config set reloads logger level and triggers post-write heartbeat" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    const before_heartbeat = app.heartbeat.snapshot().beat_count;
    const params = [_]framework.ValidationField{
        .{ .key = "path", .value = .{ .string = "logging.level" } },
        .{ .key = "value", .value = .{ .string = "debug" } },
    };

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_config_set_logging_level",
        .method = "config.set",
        .params = params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (envelope.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };

    try std.testing.expect(envelope.ok);
    try std.testing.expectEqual(framework.LogLevel.debug, app.framework_context.logger.min_level);
    try std.testing.expect(app.heartbeat.snapshot().beat_count > before_heartbeat);
    try std.testing.expect(app.config_hooks.postWriteCount() >= 1);
}

test "config set provider field triggers real provider refresh state" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    const params = [_]framework.ValidationField{
        .{ .key = "path", .value = .{ .string = "providers.openai.model" } },
        .{ .key = "value", .value = .{ .string = "gpt-4.1-mini" } },
    };

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_config_set_provider_refresh",
        .method = "config.set",
        .params = params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (envelope.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };

    try std.testing.expect(envelope.ok);
    try std.testing.expectEqual(@as(usize, 1), app.provider_registry.refresh_count);
    try std.testing.expectEqualStrings("providers.openai.model", app.provider_registry.last_refresh_reason.?);
}

test "config migrate preview summarizes legacy alias rewrites" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    const params = [_]framework.ValidationField{
        .{ .key = "config_json", .value = .{ .string = "{\"version\":1,\"config\":{\"server\":{\"port\":9091},\"openai\":{\"api_key\":\"demo\"}}}" } },
    };

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_config_migrate_preview",
        .method = "config.migrate_preview",
        .params = params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (envelope.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };

    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"toVersion\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"aliasRewriteCount\":2") != null);
}

test "config compat import preview reports mapped legacy fields" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    const params = [_]framework.ValidationField{
        .{ .key = "source_json", .value = .{ .string = "{\"log\":{\"level\":\"debug\"},\"service\":{\"auto_start\":true}}" } },
        .{ .key = "source_kind", .value = .{ .string = "nullclaw" } },
        .{ .key = "preview", .value = .{ .boolean = true } },
    };

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_config_compat_import_preview",
        .method = "config.compat_import",
        .params = params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (envelope.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };

    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"sourceKind\":\"nullclaw\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"mappedCount\":2") != null);
}

test "agent run command drives tool orchestrator and provider runtime" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai",
        .label = "Mock OpenAI",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    });

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_agent_cmd" } },
        .{ .key = "prompt", .value = .{ .string = "hello from test" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai" } },
        .{ .key = "tool_id", .value = .{ .string = "echo" } },
        .{ .key = "tool_input_json", .value = .{ .string = "{\"message\":\"hello\"}" } },
    };

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_agent_run",
        .method = "agent.run",
        .params = params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (envelope.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };

    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"providerId\":\"mock_openai\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "final response after tool") != null);
    try std.testing.expect(app.session_store.find("sess_agent_cmd") != null);
}

test "agent stream command returns stream event snapshot" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_stream_cmd",
        .label = "Mock OpenAI Stream",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_agent_stream" } },
        .{ .key = "prompt", .value = .{ .string = "CALL_TOOL:echo" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_stream_cmd" } },
    };

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_agent_stream",
        .method = "agent.stream",
        .params = params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (envelope.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };

    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"subscriptionId\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"events\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "stream.output") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "final response after tool") != null);
}

test "task query commands return queued task summary" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    const accepted = try app.framework_context.task_runner.submit("diagnostics.doctor", "req_task_lookup");

    const params_by_id = [_]framework.ValidationField{
        .{ .key = "task_id", .value = .{ .string = accepted.task_id } },
    };
    var dispatcher = app.makeDispatcher();
    const by_id = try dispatcher.dispatch(.{
        .request_id = "req_task_get",
        .method = "task.get",
        .params = params_by_id[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (by_id.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(by_id.ok);
    try std.testing.expect(std.mem.indexOf(u8, by_id.result.?.success_json, accepted.task_id) != null);

    const params_by_request = [_]framework.ValidationField{
        .{ .key = "request_id", .value = .{ .string = "req_task_lookup" } },
    };
    const by_request = try dispatcher.dispatch(.{
        .request_id = "req_task_by_request",
        .method = "task.by_request",
        .params = params_by_request[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (by_request.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(by_request.ok);
    try std.testing.expect(std.mem.indexOf(u8, by_request.result.?.success_json, "req_task_lookup") != null);
}

test "session get and compact close the loop for session summary" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_session_summary",
        .label = "Mock OpenAI Session Summary",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    var dispatcher = app.makeDispatcher();
    const run_params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_summary_01" } },
        .{ .key = "prompt", .value = .{ .string = "hello summary" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_session_summary" } },
    };
    const run_envelope = try dispatcher.dispatch(.{
        .request_id = "req_session_summary_agent",
        .method = "agent.run",
        .params = run_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer if (run_envelope.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(run_envelope.ok);

    const compact_params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_summary_01" } },
        .{ .key = "keep_last", .value = .{ .integer = 1 } },
    };
    const compact_envelope = try dispatcher.dispatch(.{
        .request_id = "req_session_compact",
        .method = "session.compact",
        .params = compact_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer if (compact_envelope.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(compact_envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, compact_envelope.result.?.success_json, "\"summaryText\":") != null);

    const get_params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_summary_01" } },
    };
    const get_envelope = try dispatcher.dispatch(.{
        .request_id = "req_session_get",
        .method = "session.get",
        .params = get_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer if (get_envelope.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(get_envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"latestSummaryEvent\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"memoryEntryCount\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"providerId\":\"mock_openai_session_summary\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"toolTraceCount\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"providerLatencyMs\":") != null);
}

test "cli channel records real request semantics" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_cli_channel",
        .label = "Mock OpenAI CLI Channel",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    const rendered = try ourclaw.interfaces.cli_adapter.dispatchAndRenderJson(
        std.testing.allocator,
        app,
        &.{ "agent.run", "sess_cli_channel", "hello cli", "--provider", "mock_openai_cli_channel" },
    );
    defer std.testing.allocator.free(rendered);

    const snapshot = app.channel_registry.cliSnapshot();
    try std.testing.expect(std.mem.indexOf(u8, rendered, "mock openai response") != null);
    try std.testing.expectEqual(@as(usize, 1), snapshot.request_count);
    try std.testing.expectEqual(@as(usize, 0), snapshot.live_stream_count);
    try std.testing.expectEqualStrings("agent.run", snapshot.last_method.?);
    try std.testing.expectEqualStrings("sess_cli_channel", snapshot.last_session_id.?);
}

test "diagnostics commands return runtime summary and doctor checks" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    var dispatcher = app.makeDispatcher();
    const summary = try dispatcher.dispatch(.{
        .request_id = "req_diag_summary",
        .method = "diagnostics.summary",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (summary.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(summary.ok);
    try std.testing.expect(std.mem.indexOf(u8, summary.result.?.success_json, "\"providers\":") != null);

    const doctor = try dispatcher.dispatch(.{
        .request_id = "req_diag_doctor",
        .method = "diagnostics.doctor",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (doctor.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(doctor.ok);
    try std.testing.expect(std.mem.indexOf(u8, doctor.result.?.success_json, "\"status\":") != null);
}

test "events subscribe and poll commands work together" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    var dispatcher = app.makeDispatcher();
    const subscribe = try dispatcher.dispatch(.{
        .request_id = "req_events_subscribe",
        .method = "events.subscribe",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (subscribe.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(subscribe.ok);
    try std.testing.expect(std.mem.indexOf(u8, subscribe.result.?.success_json, "\"subscriptionId\":") != null);
}

test "service status and skills list commands return runtime data" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    var dispatcher = app.makeDispatcher();
    const service_status = try dispatcher.dispatch(.{
        .request_id = "req_service_status",
        .method = "service.status",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (service_status.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(service_status.ok);
    try std.testing.expect(std.mem.indexOf(u8, service_status.result.?.success_json, "\"serviceState\":") != null);

    const skills = try dispatcher.dispatch(.{
        .request_id = "req_skills_list",
        .method = "skills.list",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (skills.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(skills.ok);
    try std.testing.expect(std.mem.indexOf(u8, skills.result.?.success_json, "doctor") != null);
}

test "skills cron tunnel mcp hardware commands expose richer operational state" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    var dispatcher = app.makeDispatcher();

    const install_params = [_]framework.ValidationField{.{ .key = "skill_id", .value = .{ .string = "summary" } }};
    const install = try dispatcher.dispatch(.{ .request_id = "req_skill_install_summary", .method = "skills.install", .params = install_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (install.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(install.ok);
    try std.testing.expect(std.mem.indexOf(u8, install.result.?.success_json, "\"installedAtMs\":") != null);

    const run_params = [_]framework.ValidationField{.{ .key = "skill_id", .value = .{ .string = "summary" } }};
    const run = try dispatcher.dispatch(.{ .request_id = "req_skill_run_summary", .method = "skills.run", .params = run_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (run.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(run.ok);
    try std.testing.expect(std.mem.indexOf(u8, run.result.?.success_json, "\"runCount\":1") != null);

    const skills = try dispatcher.dispatch(.{ .request_id = "req_skills_list_rich", .method = "skills.list", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer if (skills.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(skills.ok);
    try std.testing.expect(std.mem.indexOf(u8, skills.result.?.success_json, "\"installedAtMs\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, skills.result.?.success_json, "\"runCount\":1") != null);

    const cron = try dispatcher.dispatch(.{ .request_id = "req_cron_tick_rich", .method = "cron.tick", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer if (cron.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(cron.ok);

    const cron_list = try dispatcher.dispatch(.{ .request_id = "req_cron_list_rich", .method = "cron.list", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer if (cron_list.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(cron_list.ok);
    try std.testing.expect(std.mem.indexOf(u8, cron_list.result.?.success_json, "\"runCount\":") != null);

    const tunnel_activate_params = [_]framework.ValidationField{
        .{ .key = "kind", .value = .{ .string = "cloudflare" } },
        .{ .key = "endpoint", .value = .{ .string = "https://demo.example.com" } },
    };
    const tunnel_activate = try dispatcher.dispatch(.{ .request_id = "req_tunnel_activate_rich", .method = "tunnel.activate", .params = tunnel_activate_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (tunnel_activate.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(tunnel_activate.ok);
    try std.testing.expect(std.mem.indexOf(u8, tunnel_activate.result.?.success_json, "\"activationCount\":1") != null);

    const tunnel_status = try dispatcher.dispatch(.{ .request_id = "req_tunnel_status_rich", .method = "tunnel.status", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer if (tunnel_status.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(tunnel_status.ok);
    try std.testing.expect(std.mem.indexOf(u8, tunnel_status.result.?.success_json, "\"lastActivatedMs\":") != null);

    const mcp_register_params = [_]framework.ValidationField{
        .{ .key = "id", .value = .{ .string = "remote" } },
        .{ .key = "transport", .value = .{ .string = "sse" } },
    };
    const mcp_register = try dispatcher.dispatch(.{ .request_id = "req_mcp_register_rich", .method = "mcp.register", .params = mcp_register_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (mcp_register.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(mcp_register.ok);
    try std.testing.expect(std.mem.indexOf(u8, mcp_register.result.?.success_json, "\"registeredAtMs\":") != null);

    const mcp_list = try dispatcher.dispatch(.{ .request_id = "req_mcp_list_rich", .method = "mcp.list", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer if (mcp_list.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(mcp_list.ok);
    try std.testing.expect(std.mem.indexOf(u8, mcp_list.result.?.success_json, "\"registeredAtMs\":") != null);

    const hardware_register_params = [_]framework.ValidationField{
        .{ .key = "id", .value = .{ .string = "gpu1" } },
        .{ .key = "label", .value = .{ .string = "Secondary GPU" } },
    };
    const hardware_register = try dispatcher.dispatch(.{ .request_id = "req_hardware_register_rich", .method = "hardware.register", .params = hardware_register_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (hardware_register.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(hardware_register.ok);
    try std.testing.expect(std.mem.indexOf(u8, hardware_register.result.?.success_json, "\"registeredAtMs\":") != null);

    const hardware_list = try dispatcher.dispatch(.{ .request_id = "req_hardware_list_rich", .method = "hardware.list", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer if (hardware_list.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(hardware_list.ok);
    try std.testing.expect(std.mem.indexOf(u8, hardware_list.result.?.success_json, "\"nodes\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, hardware_list.result.?.success_json, "\"registeredAtMs\":") != null);
}

test "memory snapshot export and migrate apply close retrieval route" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.memory_runtime.appendUserPrompt("sess_mem_export", "hello memory");
    try app.memory_runtime.appendAssistantResponse("sess_mem_export", "hi memory");

    var dispatcher = app.makeDispatcher();
    const export_envelope = try dispatcher.dispatch(.{
        .request_id = "req_memory_snapshot_export",
        .method = "memory.snapshot_export",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer if (export_envelope.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(export_envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, export_envelope.result.?.success_json, "\"version\":2") != null);

    const migrate_params = [_]framework.ValidationField{
        .{ .key = "snapshot_json", .value = .{ .string = "{\"version\":1,\"entries\":[]}" } },
    };
    const migrate_envelope = try dispatcher.dispatch(.{
        .request_id = "req_memory_migrate_apply",
        .method = "memory.migrate_apply",
        .params = migrate_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer if (migrate_envelope.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(migrate_envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, migrate_envelope.result.?.success_json, "\"toVersion\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, migrate_envelope.result.?.success_json, "\"snapshot\":{\"version\":2") != null);
}

test "memory commands expose summary and retrieval" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.memory_runtime.appendUserPrompt("sess_mem", "hello memory");
    try app.memory_runtime.appendAssistantResponse("sess_mem", "memory answer");

    var dispatcher = app.makeDispatcher();
    const summary_params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_mem" } },
    };
    const summary = try dispatcher.dispatch(.{
        .request_id = "req_memory_summary",
        .method = "memory.summary",
        .params = summary_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (summary.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(summary.ok);
    try std.testing.expect(std.mem.indexOf(u8, summary.result.?.success_json, "\"summaryText\":") != null);

    const retrieve_params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_mem" } },
        .{ .key = "query", .value = .{ .string = "memory" } },
    };
    const retrieve = try dispatcher.dispatch(.{
        .request_id = "req_memory_retrieve",
        .method = "memory.retrieve",
        .params = retrieve_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (retrieve.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(retrieve.ok);
    try std.testing.expect(std.mem.indexOf(u8, retrieve.result.?.success_json, "assistant_response") != null);
}

test "service and gateway control commands mutate runtime state" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    var dispatcher = app.makeDispatcher();

    const install = try dispatcher.dispatch(.{ .request_id = "req_service_install", .method = "service.install", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (install.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(install.ok);
    try std.testing.expect(std.mem.indexOf(u8, install.result.?.success_json, "\"installCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, install.result.?.success_json, "\"daemonProjected\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, install.result.?.success_json, "\"changed\":true") != null);

    const install_again = try dispatcher.dispatch(.{ .request_id = "req_service_install_again", .method = "service.install", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (install_again.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(install_again.ok);
    try std.testing.expect(std.mem.indexOf(u8, install_again.result.?.success_json, "\"installCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, install_again.result.?.success_json, "\"changed\":false") != null);

    const start = try dispatcher.dispatch(.{ .request_id = "req_service_start", .method = "service.start", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (start.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(start.ok);
    try std.testing.expect(std.mem.indexOf(u8, start.result.?.success_json, "\"changed\":true") != null);

    const start_again = try dispatcher.dispatch(.{ .request_id = "req_service_start_again", .method = "service.start", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (start_again.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(start_again.ok);
    try std.testing.expect(std.mem.indexOf(u8, start_again.result.?.success_json, "\"startCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, start_again.result.?.success_json, "\"changed\":false") != null);

    const service_status = try dispatcher.dispatch(.{ .request_id = "req_service_status", .method = "service.status", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (service_status.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(service_status.ok);
    try std.testing.expect(std.mem.indexOf(u8, service_status.result.?.success_json, "\"daemonProjected\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, service_status.result.?.success_json, "\"installCount\":1") != null);

    const stop = try dispatcher.dispatch(.{ .request_id = "req_service_stop", .method = "service.stop", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (stop.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(stop.ok);
    try std.testing.expect(std.mem.indexOf(u8, stop.result.?.success_json, "\"changed\":true") != null);

    const stop_again = try dispatcher.dispatch(.{ .request_id = "req_service_stop_again", .method = "service.stop", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (stop_again.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(stop_again.ok);
    try std.testing.expect(std.mem.indexOf(u8, stop_again.result.?.success_json, "\"stopCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, stop_again.result.?.success_json, "\"changed\":false") != null);

    const restart = try dispatcher.dispatch(.{ .request_id = "req_service_restart", .method = "service.restart", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (restart.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(restart.ok);
    try std.testing.expect(std.mem.indexOf(u8, restart.result.?.success_json, "\"restartCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, restart.result.?.success_json, "\"startApplied\":true") != null);

    const gateway_status = try dispatcher.dispatch(.{ .request_id = "req_gateway_status", .method = "gateway.status", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (gateway_status.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(gateway_status.ok);
    try std.testing.expect(std.mem.indexOf(u8, gateway_status.result.?.success_json, "\"running\":true") != null);
}

test "skills cron tunnel mcp hardware commands are operational" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    var dispatcher = app.makeDispatcher();

    const skill_run_params = [_]framework.ValidationField{.{ .key = "skill_id", .value = .{ .string = "doctor" } }};
    const skill_run = try dispatcher.dispatch(.{ .request_id = "req_skill_run", .method = "skills.run", .params = skill_run_params[0..], .source = .@"test", .authority = .admin }, false);
    defer switch (skill_run.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(skill_run.ok);
    try std.testing.expect(std.mem.indexOf(u8, skill_run.result.?.success_json, "\"status\":\"completed\"") != null);

    const cron_tick = try dispatcher.dispatch(.{ .request_id = "req_cron_tick", .method = "cron.tick", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (cron_tick.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(cron_tick.ok);
    try std.testing.expect(std.mem.indexOf(u8, cron_tick.result.?.success_json, "\"jobs\":[") != null);

    const tunnel_params = [_]framework.ValidationField{
        .{ .key = "kind", .value = .{ .string = "cloudflare" } },
        .{ .key = "endpoint", .value = .{ .string = "https://demo.example.com" } },
    };
    const tunnel_activate = try dispatcher.dispatch(.{ .request_id = "req_tunnel_activate", .method = "tunnel.activate", .params = tunnel_params[0..], .source = .@"test", .authority = .admin }, false);
    defer switch (tunnel_activate.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(tunnel_activate.ok);

    const mcp_params = [_]framework.ValidationField{
        .{ .key = "id", .value = .{ .string = "remote" } },
        .{ .key = "transport", .value = .{ .string = "http" } },
    };
    const mcp_register = try dispatcher.dispatch(.{ .request_id = "req_mcp_register", .method = "mcp.register", .params = mcp_params[0..], .source = .@"test", .authority = .admin }, false);
    defer switch (mcp_register.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(mcp_register.ok);

    const hardware_params = [_]framework.ValidationField{
        .{ .key = "id", .value = .{ .string = "sensor0" } },
        .{ .key = "label", .value = .{ .string = "Temperature Sensor" } },
    };
    const hardware_register = try dispatcher.dispatch(.{ .request_id = "req_hardware_register", .method = "hardware.register", .params = hardware_params[0..], .source = .@"test", .authority = .admin }, false);
    defer switch (hardware_register.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(hardware_register.ok);
}
