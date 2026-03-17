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

    const providers_status = try dispatcher.dispatch(.{
        .request_id = "req_providers_status_after_refresh",
        .method = "providers.status",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (providers_status.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(providers_status.ok);
    try std.testing.expect(std.mem.indexOf(u8, providers_status.result.?.success_json, "\"refreshCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, providers_status.result.?.success_json, "\"lastRefreshReason\":\"providers.openai.model\"") != null);
}

test "config notify runtime updates pairing and max tool rounds" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    var dispatcher = app.makeDispatcher();
    const pairing_params = [_]framework.ValidationField{
        .{ .key = "path", .value = .{ .string = "gateway.require_pairing" } },
        .{ .key = "value", .value = .{ .string = "false" } },
        .{ .key = "confirm_risk", .value = .{ .boolean = true } },
    };
    const set_pairing = try dispatcher.dispatch(.{ .request_id = "req_config_set_pairing", .method = "config.set", .params = pairing_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (set_pairing.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(set_pairing.ok);
    try std.testing.expect(!app.effective_gateway_require_pairing);

    const max_tool_rounds_params = [_]framework.ValidationField{
        .{ .key = "path", .value = .{ .string = "runtime.max_tool_rounds" } },
        .{ .key = "value", .value = .{ .string = "2" } },
    };
    const set_max_tool_rounds = try dispatcher.dispatch(.{ .request_id = "req_config_set_max_tool_rounds", .method = "config.set", .params = max_tool_rounds_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (set_max_tool_rounds.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(set_max_tool_rounds.ok);
    try std.testing.expectEqual(@as(usize, 2), app.effective_runtime_max_tool_rounds);

    try app.provider_registry.register(.{
        .id = "mock_openai_runtime_max_tool_rounds",
        .label = "Mock OpenAI Runtime Max Tool Rounds",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    });

    const run_params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_runtime_max_tool_rounds" } },
        .{ .key = "prompt", .value = .{ .string = "hello" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_runtime_max_tool_rounds" } },
    };
    const run = try dispatcher.dispatch(.{ .request_id = "req_agent_run_runtime_max_tool_rounds", .method = "agent.run", .params = run_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (run.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(run.ok);

    const get_params = [_]framework.ValidationField{.{ .key = "session_id", .value = .{ .string = "sess_runtime_max_tool_rounds" } }};
    const get = try dispatcher.dispatch(.{ .request_id = "req_session_get_runtime_max_tool_rounds", .method = "session.get", .params = get_params[0..], .source = .@"test", .authority = .admin }, false);
    defer switch (get.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(get.ok);
    try std.testing.expect(std.mem.indexOf(u8, get.result.?.success_json, "\"maxToolRounds\":2") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"unknownPaths\":[") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"aliasRewriteCount\":2") != null);
}

test "config migrate apply and compat import apply expose governance summary" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    var dispatcher = app.makeDispatcher();

    const migrate_params = [_]framework.ValidationField{
        .{ .key = "config_json", .value = .{ .string = "{\"version\":1,\"config\":{\"server\":{\"port\":9092},\"logging\":{\"level\":\"debug\"}}}" } },
        .{ .key = "confirm_risk", .value = .{ .boolean = true } },
    };
    const migrate_apply = try dispatcher.dispatch(.{
        .request_id = "req_config_migrate_apply_governance",
        .method = "config.migrate_apply",
        .params = migrate_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (migrate_apply.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(migrate_apply.ok);
    try std.testing.expect(std.mem.indexOf(u8, migrate_apply.result.?.success_json, "\"fromVersion\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, migrate_apply.result.?.success_json, "\"toVersion\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, migrate_apply.result.?.success_json, "\"unknownCount\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, migrate_apply.result.?.success_json, "\"requiresRestart\":") != null);

    const compat_apply_params = [_]framework.ValidationField{
        .{ .key = "source_json", .value = .{ .string = "{\"log\":{\"level\":\"warn\"},\"service\":{\"auto_start\":true}}" } },
        .{ .key = "source_kind", .value = .{ .string = "nullclaw" } },
        .{ .key = "confirm_risk", .value = .{ .boolean = true } },
    };
    const compat_apply = try dispatcher.dispatch(.{
        .request_id = "req_config_compat_import_apply",
        .method = "config.compat_import",
        .params = compat_apply_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (compat_apply.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(compat_apply.ok);
    try std.testing.expect(std.mem.indexOf(u8, compat_apply.result.?.success_json, "\"preview\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, compat_apply.result.?.success_json, "\"fromVersion\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, compat_apply.result.?.success_json, "\"toVersion\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, compat_apply.result.?.success_json, "\"mappedCount\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, compat_apply.result.?.success_json, "\"requiresRestart\":") != null);
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

test "agent run command supports provider retry budget" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_retry_once_cmd",
        .label = "Mock OpenAI Retry Once",
        .endpoint = "mock://openai/chat_retry_once",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    });

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_agent_retry" } },
        .{ .key = "prompt", .value = .{ .string = "hello retry" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_retry_once_cmd" } },
        .{ .key = "provider_retry_budget", .value = .{ .integer = 1 } },
    };

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_agent_run_retry",
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
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "mock openai response") != null);
}

test "agent run command rejects provider round budget exhaustion" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_round_budget_cmd",
        .label = "Mock OpenAI Round Budget",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_agent_round_budget" } },
        .{ .key = "prompt", .value = .{ .string = "CALL_TOOL:echo" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_round_budget_cmd" } },
        .{ .key = "provider_round_budget", .value = .{ .integer = 1 } },
    };

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_agent_run_round_budget",
        .method = "agent.run",
        .params = params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);

    try std.testing.expect(!envelope.ok);
    var snapshot = try app.session_store.snapshotMeta(std.testing.allocator, "sess_agent_round_budget");
    defer snapshot.deinit(std.testing.allocator);
    try std.testing.expect(snapshot.last_error_code != null);
    try std.testing.expectEqualStrings("PROVIDER_ROUND_BUDGET_EXCEEDED", snapshot.last_error_code.?);
}

test "agent run command denies high-risk tool without confirmation" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_agent_risk_denied" } },
        .{ .key = "prompt", .value = .{ .string = "hello risk" } },
        .{ .key = "provider_id", .value = .{ .string = "provider_unused" } },
        .{ .key = "tool_id", .value = .{ .string = "shell" } },
        .{ .key = "tool_input_json", .value = .{ .string = "{\"command\":\"echo hello\"}" } },
    };

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_agent_run_risk_denied",
        .method = "agent.run",
        .params = params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);

    try std.testing.expect(!envelope.ok);
    var snapshot = try app.session_store.snapshotMeta(std.testing.allocator, "sess_agent_risk_denied");
    defer snapshot.deinit(std.testing.allocator);
    try std.testing.expect(snapshot.last_error_code != null);
    try std.testing.expectEqualStrings("TOOL_RISK_CONFIRMATION_REQUIRED", snapshot.last_error_code.?);
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
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "provider_native") != null);

    const sub_params = [_]framework.ValidationField{
        .{ .key = "topic_prefix", .value = .{ .string = "stream.output" } },
        .{ .key = "after_seq", .value = .{ .integer = 0 } },
    };
    const subscribe = try dispatcher.dispatch(.{ .request_id = "req_events_subscribe_corr", .method = "events.subscribe", .params = sub_params[0..], .source = .@"test", .authority = .admin }, false);
    defer switch (subscribe.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(subscribe.ok);
    try std.testing.expect(std.mem.indexOf(u8, subscribe.result.?.success_json, "\"topicPrefix\":\"stream.output\"") != null);

    const poll_params = [_]framework.ValidationField{
        .{ .key = "subscription_id", .value = .{ .integer = 2 } },
        .{ .key = "session_id", .value = .{ .string = "sess_agent_stream" } },
    };
    const poll = try dispatcher.dispatch(.{ .request_id = "req_events_poll_corr", .method = "events.poll", .params = poll_params[0..], .source = .@"test", .authority = .admin }, false);
    defer switch (poll.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(poll.ok);
    try std.testing.expect(std.mem.indexOf(u8, poll.result.?.success_json, "\"sessionId\":\"sess_agent_stream\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, poll.result.?.success_json, "\"subscriptionId\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, poll.result.?.success_json, "provider_native") != null);

    const observer = try dispatcher.dispatch(.{ .request_id = "req_observer_recent_corr", .method = "observer.recent", .params = &.{.{ .key = "session_id", .value = .{ .string = "sess_agent_stream" } }}, .source = .@"test", .authority = .admin }, false);
    defer switch (observer.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(observer.ok);
    try std.testing.expect(std.mem.indexOf(u8, observer.result.?.success_json, "\"sessionId\":\"sess_agent_stream\"") != null);

    const metrics = try dispatcher.dispatch(.{ .request_id = "req_metrics_summary_corr", .method = "metrics.summary", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (metrics.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(metrics.ok);
    try std.testing.expect(std.mem.indexOf(u8, metrics.result.?.success_json, "\"correlatedStreamEvents\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, metrics.result.?.success_json, "\"lastSessionId\":sess_agent_stream") == null);
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
    try std.testing.expect(std.mem.indexOf(u8, compact_envelope.result.?.success_json, "\"removedCount\":") != null);

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
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"firstEventSeq\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"lastEventSeq\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"turnCount\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"assistantResponseCount\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"providerLatencyMs\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"providerRoundBudget\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"providerRoundsRemaining\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"providerAttemptBudget\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"providerAttemptsRemaining\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"toolCallBudget\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"toolCallsRemaining\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"providerRetryBudget\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"promptTokens\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"completionTokens\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"totalTokens\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"replay\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"latestTurn\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"counts\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"usage\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"recentTurns\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_envelope.result.?.success_json, "\"totalDeadlineMs\":") != null);

    const rerun_params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_summary_01" } },
        .{ .key = "prompt", .value = .{ .string = "PROMPT_ASSEMBLY_PROBE" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_session_summary" } },
        .{ .key = "allow_provider_tools", .value = .{ .boolean = false } },
        .{ .key = "prompt_profile", .value = .{ .string = "concise_operator" } },
        .{ .key = "response_mode", .value = .{ .string = "terse" } },
        .{ .key = "max_tool_rounds", .value = .{ .integer = 1 } },
    };
    const rerun_envelope = try dispatcher.dispatch(.{
        .request_id = "req_session_summary_rerun",
        .method = "agent.run",
        .params = rerun_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer if (rerun_envelope.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(rerun_envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, rerun_envelope.result.?.success_json, "prompt assembly summary-first ok") != null);

    const get_after_rerun = try dispatcher.dispatch(.{
        .request_id = "req_session_get_after_rerun",
        .method = "session.get",
        .params = get_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer if (get_after_rerun.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(get_after_rerun.ok);
    try std.testing.expect(std.mem.indexOf(u8, get_after_rerun.result.?.success_json, "\"usage\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_after_rerun.result.?.success_json, "\"recentTurns\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_after_rerun.result.?.success_json, "\"allowProviderTools\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_after_rerun.result.?.success_json, "\"promptProfile\":\"concise_operator\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_after_rerun.result.?.success_json, "\"responseMode\":\"terse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_after_rerun.result.?.success_json, "\"maxToolRounds\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_after_rerun.result.?.success_json, "\"recovery\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_after_rerun.result.?.success_json, "\"executionCursor\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_after_rerun.result.?.success_json, "\"promptTokens\":36") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_after_rerun.result.?.success_json, "\"completionTokens\":12") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_after_rerun.result.?.success_json, "\"totalTokens\":48") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_after_rerun.result.?.success_json, "\"turnCount\":2") != null);
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

test "channels status exposes routing groups" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.channel_registry.recordCliRequest("agent.run", "sess_channels_cli");
    try app.channel_registry.recordBridgeRequest("config.get", null);
    try app.channel_registry.recordHttpStream("/v1/agent/stream/sse", "sess_channels_http");

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_channels_status",
        .method = "channels.status",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (envelope.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"count\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"lastRouteGroup\":\"agent\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"lastRouteGroup\":\"config\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"healthState\":\"active\"") != null);
}

test "providers status exposes capability surface" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_providers_status",
        .method = "providers.status",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (envelope.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"count\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"supportsStreaming\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"supportsTools\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"modelCount\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"healthMessage\":") != null);
}

test "onboard summary exposes readiness and next step" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_onboard_summary",
        .method = "onboard.summary",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (envelope.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"readyCount\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"gatewayPairingEnabled\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"nextStep\":") != null);
}

test "onboard apply defaults updates runtime and service state" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();
    app.effective_gateway_require_pairing = false;
    app.effective_runtime_max_tool_rounds = 2;

    var dispatcher = app.makeDispatcher();
    const params = [_]framework.ValidationField{.{ .key = "install_service", .value = .{ .boolean = true } }};
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_onboard_apply_defaults",
        .method = "onboard.apply_defaults",
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
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"serviceChanged\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"gatewayRequirePairing\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"runtimeMaxToolRounds\":4") != null);
}

test "status all exposes product overview" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();
    try app.pairing_registry.create("telegram", "user_a", "123456");

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_status_all",
        .method = "status.all",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (envelope.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"gateway\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"providers\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"pairing\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"nextAction\":") != null);
}

test "gateway auth status exposes access summary" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();
    try app.pairing_registry.create("telegram", "user_a", "123456");

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_gateway_auth_status",
        .method = "gateway.auth.status",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (envelope.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"requirePairing\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"pendingPairings\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"sharedTokenSupported\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"nextAction\":\"approve_pairing_requests\"") != null);

    const token = try dispatcher.dispatch(.{
        .request_id = "req_gateway_token_generate",
        .method = "gateway.token.generate",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (token.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(token.ok);
    try std.testing.expect(std.mem.indexOf(u8, token.result.?.success_json, "\"generated\":true") != null);
    try std.testing.expect(app.secret_store.get("gateway:shared_token") != null);

    const envelope_after_token = try dispatcher.dispatch(.{
        .request_id = "req_gateway_auth_status_after_token",
        .method = "gateway.auth.status",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (envelope_after_token.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(envelope_after_token.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope_after_token.result.?.success_json, "\"sharedTokenConfigured\":true") != null);
}

test "device pair control-plane commands manage pending requests" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.pairing_registry.create("telegram", "user_a", "123456");
    try app.pairing_registry.create("discord", "user_b", "654321");

    var dispatcher = app.makeDispatcher();
    const listed = try dispatcher.dispatch(.{
        .request_id = "req_device_pair_list",
        .method = "device.pair.list",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (listed.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(listed.ok);
    try std.testing.expect(std.mem.indexOf(u8, listed.result.?.success_json, "\"pendingCount\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, listed.result.?.success_json, "\"requirePairing\":true") != null);

    const approve_params = [_]framework.ValidationField{.{ .key = "id", .value = .{ .string = "pair_1" } }};
    const approved = try dispatcher.dispatch(.{
        .request_id = "req_device_pair_approve",
        .method = "device.pair.approve",
        .params = approve_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (approved.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(approved.ok);
    try std.testing.expect(std.mem.indexOf(u8, approved.result.?.success_json, "\"state\":\"approved\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, approved.result.?.success_json, "\"pendingCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, approved.result.?.success_json, "\"token\":\"devtok_") != null);

    const reject_params = [_]framework.ValidationField{.{ .key = "id", .value = .{ .string = "pair_2" } }};
    const rejected = try dispatcher.dispatch(.{
        .request_id = "req_device_pair_reject",
        .method = "device.pair.reject",
        .params = reject_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (rejected.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(rejected.ok);
    try std.testing.expect(std.mem.indexOf(u8, rejected.result.?.success_json, "\"state\":\"rejected\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rejected.result.?.success_json, "\"pendingCount\":0") != null);

    const rotate_params = [_]framework.ValidationField{.{ .key = "id", .value = .{ .string = "pair_1" } }};
    const rotated = try dispatcher.dispatch(.{
        .request_id = "req_device_token_rotate",
        .method = "device.token.rotate",
        .params = rotate_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (rotated.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(rotated.ok);
    try std.testing.expect(std.mem.indexOf(u8, rotated.result.?.success_json, "\"token\":\"devtok_") != null);

    const revoked = try dispatcher.dispatch(.{
        .request_id = "req_device_token_revoke",
        .method = "device.token.revoke",
        .params = rotate_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (revoked.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(revoked.ok);
    try std.testing.expect(std.mem.indexOf(u8, revoked.result.?.success_json, "\"token\":null") != null);
}

test "node list exposes runtime node surface" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.pairing_registry.create("telegram", "user_a", "123456");
    _ = app.pairing_registry.approve("pair_1");

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_node_list",
        .method = "node.list",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (envelope.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"count\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"approvedPairingCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"healthState\":\"ready\"") != null);
}

test "node describe exposes single node detail" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.pairing_registry.create("telegram", "user_a", "123456");
    _ = app.pairing_registry.approve("pair_1");

    var dispatcher = app.makeDispatcher();
    const params = [_]framework.ValidationField{.{ .key = "id", .value = .{ .string = "gpu0" } }};
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_node_describe",
        .method = "node.describe",
        .params = params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (envelope.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"id\":\"gpu0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"kind\":\"gpu\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"approvedPairingCount\":1") != null);
}

test "devices list aggregates pairing node and peripheral state" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.pairing_registry.create("telegram", "user_a", "123456");
    _ = app.pairing_registry.approve("pair_1");

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = "req_devices_list",
        .method = "devices.list",
        .params = &.{},
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (envelope.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"approved\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"nodes\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, envelope.result.?.success_json, "\"peripherals\":{") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, doctor.result.?.success_json, "\"healthyProviderCount\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, doctor.result.?.success_json, "\"gatewayRequirePairing\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, doctor.result.?.success_json, "\"serviceState\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, doctor.result.?.success_json, "\"hardwareCount\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, doctor.result.?.success_json, "\"brokenPeripheralCount\":") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, cron.result.?.success_json, "\"tickCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, cron.result.?.success_json, "\"heartbeatBeatCount\":1") != null);

    const cron_list = try dispatcher.dispatch(.{ .request_id = "req_cron_list_rich", .method = "cron.list", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer if (cron_list.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(cron_list.ok);
    try std.testing.expect(std.mem.indexOf(u8, cron_list.result.?.success_json, "\"runCount\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, cron_list.result.?.success_json, "\"schedulerTickCount\":1") != null);

    const tunnel_activate_params = [_]framework.ValidationField{
        .{ .key = "kind", .value = .{ .string = "cloudflare" } },
        .{ .key = "endpoint", .value = .{ .string = "mock://tunnel/healthy" } },
    };
    const tunnel_activate = try dispatcher.dispatch(.{ .request_id = "req_tunnel_activate_rich", .method = "tunnel.activate", .params = tunnel_activate_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (tunnel_activate.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(tunnel_activate.ok);
    try std.testing.expect(std.mem.indexOf(u8, tunnel_activate.result.?.success_json, "\"activationCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, tunnel_activate.result.?.success_json, "\"healthState\":\"ready\"") != null);

    const tunnel_status = try dispatcher.dispatch(.{ .request_id = "req_tunnel_status_rich", .method = "tunnel.status", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer if (tunnel_status.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(tunnel_status.ok);
    try std.testing.expect(std.mem.indexOf(u8, tunnel_status.result.?.success_json, "\"lastActivatedMs\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, tunnel_status.result.?.success_json, "\"probeCount\":1") != null);

    const tunnel_bad_params = [_]framework.ValidationField{
        .{ .key = "kind", .value = .{ .string = "cloudflare" } },
        .{ .key = "endpoint", .value = .{ .string = "mock://tunnel/down" } },
    };
    const tunnel_bad = try dispatcher.dispatch(.{ .request_id = "req_tunnel_activate_bad", .method = "tunnel.activate", .params = tunnel_bad_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (tunnel_bad.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(tunnel_bad.ok);
    try std.testing.expect(std.mem.indexOf(u8, tunnel_bad.result.?.success_json, "\"status\":\"failed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, tunnel_bad.result.?.success_json, "TunnelEndpointUnreachable") != null);

    const mcp_register_params = [_]framework.ValidationField{
        .{ .key = "id", .value = .{ .string = "remote" } },
        .{ .key = "transport", .value = .{ .string = "sse" } },
        .{ .key = "endpoint", .value = .{ .string = "mock://mcp/healthy" } },
    };
    const mcp_register = try dispatcher.dispatch(.{ .request_id = "req_mcp_register_rich", .method = "mcp.register", .params = mcp_register_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (mcp_register.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(mcp_register.ok);
    try std.testing.expect(std.mem.indexOf(u8, mcp_register.result.?.success_json, "\"registeredAtMs\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, mcp_register.result.?.success_json, "\"healthState\":\"ready\"") != null);

    const mcp_list = try dispatcher.dispatch(.{ .request_id = "req_mcp_list_rich", .method = "mcp.list", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer if (mcp_list.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(mcp_list.ok);
    try std.testing.expect(std.mem.indexOf(u8, mcp_list.result.?.success_json, "\"registeredAtMs\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, mcp_list.result.?.success_json, "\"probeCount\":") != null);

    const mcp_bad_params = [_]framework.ValidationField{
        .{ .key = "id", .value = .{ .string = "remote_bad" } },
        .{ .key = "transport", .value = .{ .string = "sse" } },
        .{ .key = "endpoint", .value = .{ .string = "mock://mcp/down" } },
    };
    const mcp_bad = try dispatcher.dispatch(.{ .request_id = "req_mcp_register_bad", .method = "mcp.register", .params = mcp_bad_params[0..], .source = .@"test", .authority = .admin }, false);
    try std.testing.expect(!mcp_bad.ok);
    try std.testing.expect(mcp_bad.app_error != null);
    try std.testing.expectEqualStrings("CORE_INTERNAL_ERROR", mcp_bad.app_error.?.code);
    try std.testing.expectEqualStrings("McpServerUnreachable", mcp_bad.app_error.?.message);

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
    try std.testing.expect(std.mem.indexOf(u8, hardware_register.result.?.success_json, "\"healthState\":\"ready\"") != null);

    const peripheral_register_params = [_]framework.ValidationField{
        .{ .key = "id", .value = .{ .string = "camera1" } },
        .{ .key = "kind", .value = .{ .string = "video" } },
    };
    const peripheral_register = try dispatcher.dispatch(.{ .request_id = "req_peripheral_register_rich", .method = "peripheral.register", .params = peripheral_register_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (peripheral_register.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(peripheral_register.ok);
    try std.testing.expect(std.mem.indexOf(u8, peripheral_register.result.?.success_json, "\"healthState\":\"ready\"") != null);

    const peripheral_bad_params = [_]framework.ValidationField{
        .{ .key = "id", .value = .{ .string = "camera_bad" } },
        .{ .key = "kind", .value = .{ .string = "serial" } },
    };
    const peripheral_bad = try dispatcher.dispatch(.{ .request_id = "req_peripheral_register_bad", .method = "peripheral.register", .params = peripheral_bad_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (peripheral_bad.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(peripheral_bad.ok);
    try std.testing.expect(std.mem.indexOf(u8, peripheral_bad.result.?.success_json, "\"status\":\"failed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, peripheral_bad.result.?.success_json, "PeripheralUnsupportedKind") != null);

    const hardware_bad_params = [_]framework.ValidationField{
        .{ .key = "id", .value = .{ .string = "mystery0" } },
        .{ .key = "label", .value = .{ .string = "Mystery Device" } },
    };
    const hardware_bad = try dispatcher.dispatch(.{ .request_id = "req_hardware_register_bad", .method = "hardware.register", .params = hardware_bad_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (hardware_bad.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(hardware_bad.ok);
    try std.testing.expect(std.mem.indexOf(u8, hardware_bad.result.?.success_json, "\"status\":\"failed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, hardware_bad.result.?.success_json, "HardwareUnsupportedKind") != null);

    const hardware_list = try dispatcher.dispatch(.{ .request_id = "req_hardware_list_rich", .method = "hardware.list", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer if (hardware_list.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(hardware_list.ok);
    try std.testing.expect(std.mem.indexOf(u8, hardware_list.result.?.success_json, "\"nodes\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, hardware_list.result.?.success_json, "\"registeredAtMs\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, hardware_list.result.?.success_json, "\"peripherals\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, hardware_list.result.?.success_json, "\"healthState\":\"ready\"") != null);

    const voice_attach_bad_params = [_]framework.ValidationField{.{ .key = "peripheral_id", .value = .{ .string = "camera1" } }};
    const voice_bad = try dispatcher.dispatch(.{ .request_id = "req_voice_attach_bad", .method = "voice.attach", .params = voice_attach_bad_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (voice_bad.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(voice_bad.ok);
    try std.testing.expect(std.mem.indexOf(u8, voice_bad.result.?.success_json, "VoiceUnsupportedPeripheralKind") != null);

    const voice_peripheral_params = [_]framework.ValidationField{
        .{ .key = "id", .value = .{ .string = "mic0" } },
        .{ .key = "kind", .value = .{ .string = "audio" } },
    };
    const voice_peripheral = try dispatcher.dispatch(.{ .request_id = "req_peripheral_register_voice", .method = "peripheral.register", .params = voice_peripheral_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (voice_peripheral.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(voice_peripheral.ok);

    const voice_attach_params = [_]framework.ValidationField{.{ .key = "peripheral_id", .value = .{ .string = "mic0" } }};
    const voice_attach = try dispatcher.dispatch(.{ .request_id = "req_voice_attach", .method = "voice.attach", .params = voice_attach_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (voice_attach.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(voice_attach.ok);
    try std.testing.expect(std.mem.indexOf(u8, voice_attach.result.?.success_json, "\"healthState\":\"ready\"") != null);

    const voice_status = try dispatcher.dispatch(.{ .request_id = "req_voice_status", .method = "voice.status", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer if (voice_status.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(voice_status.ok);
    try std.testing.expect(std.mem.indexOf(u8, voice_status.result.?.success_json, "\"peripheralId\":\"mic0\"") != null);

    const voice_detach = try dispatcher.dispatch(.{ .request_id = "req_voice_detach", .method = "voice.detach", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer if (voice_detach.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(voice_detach.ok);
    try std.testing.expect(std.mem.indexOf(u8, voice_detach.result.?.success_json, "\"healthState\":\"inactive\"") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, migrate_envelope.result.?.success_json, "\"snapshotJson\":\"{\\\"version\\\":2") != null);
}

test "memory snapshot export exposes import-ready roundtrip" {
    var source_app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer source_app.destroy();

    try source_app.memory_runtime.appendUserPrompt("sess_mem_roundtrip", "hello \"roundtrip\" memory");
    try source_app.memory_runtime.appendToolResult("sess_mem_roundtrip", "http_request", "{\"status\":200,\"body\":{\"nested\":true}}");
    try source_app.memory_runtime.appendAssistantResponse("sess_mem_roundtrip", "roundtrip memory is ready");
    source_app.memory_runtime.entries.items[0].ts_unix_ms = 777001;
    const compact_params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_mem_roundtrip" } },
        .{ .key = "keep_last", .value = .{ .integer = 3 } },
    };
    const compact_envelope = try source_app.makeDispatcher().dispatch(.{
        .request_id = "req_memory_roundtrip_compact",
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

    var source_dispatcher = source_app.makeDispatcher();
    const export_envelope = try source_dispatcher.dispatch(.{
        .request_id = "req_memory_snapshot_export_roundtrip",
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
    try std.testing.expect(std.mem.indexOf(u8, export_envelope.result.?.success_json, "\"snapshotJson\":\"{\\\"version\\\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, export_envelope.result.?.success_json, "\"tsUnixMs\":777001") != null);
    try std.testing.expect(std.mem.indexOf(u8, export_envelope.result.?.success_json, "\"embeddingProvider\":\"local\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, export_envelope.result.?.success_json, "\"embeddingModel\":\"local-bow-v1\"") != null);

    const snapshot_json = try source_app.memory_runtime.exportSnapshotJson(std.testing.allocator);
    defer std.testing.allocator.free(snapshot_json);

    var imported_app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer imported_app.destroy();
    var imported_dispatcher = imported_app.makeDispatcher();

    const import_params = [_]framework.ValidationField{.{ .key = "snapshot_json", .value = .{ .string = snapshot_json } }};
    const import_envelope = try imported_dispatcher.dispatch(.{
        .request_id = "req_memory_snapshot_import_roundtrip",
        .method = "memory.snapshot_import",
        .params = import_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer if (import_envelope.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(import_envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, import_envelope.result.?.success_json, "\"importedCount\":4") != null);

    const imported_snapshot_json = try imported_app.memory_runtime.exportSnapshotJson(std.testing.allocator);
    defer std.testing.allocator.free(imported_snapshot_json);
    try std.testing.expect(std.mem.indexOf(u8, imported_snapshot_json, "\"tsUnixMs\":777001") != null);
    try std.testing.expect(std.mem.indexOf(u8, imported_snapshot_json, "\"embeddingProvider\":\"local\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, imported_snapshot_json, "\"embeddingModel\":\"local-bow-v1\"") != null);

    const summary_params = [_]framework.ValidationField{.{ .key = "session_id", .value = .{ .string = "sess_mem_roundtrip" } }};
    const summary_envelope = try imported_dispatcher.dispatch(.{
        .request_id = "req_memory_summary_roundtrip",
        .method = "memory.summary",
        .params = summary_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer if (summary_envelope.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(summary_envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, summary_envelope.result.?.success_json, "sess_mem_roundtrip") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary_envelope.result.?.success_json, "roundtrip memory") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary_envelope.result.?.success_json, "nested") != null);

    const retrieve_params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_mem_roundtrip" } },
        .{ .key = "query", .value = .{ .string = "roundtrip" } },
    };
    const retrieve_envelope = try imported_dispatcher.dispatch(.{
        .request_id = "req_memory_retrieve_roundtrip",
        .method = "memory.retrieve",
        .params = retrieve_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer if (retrieve_envelope.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(retrieve_envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, retrieve_envelope.result.?.success_json, "\"rank\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, retrieve_envelope.result.?.success_json, "assistant_response") != null);

    const nested_retrieve_params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_mem_roundtrip" } },
        .{ .key = "query", .value = .{ .string = "nested" } },
    };
    const nested_retrieve_envelope = try imported_dispatcher.dispatch(.{
        .request_id = "req_memory_retrieve_roundtrip_nested",
        .method = "memory.retrieve",
        .params = nested_retrieve_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer if (nested_retrieve_envelope.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(nested_retrieve_envelope.ok);
    try std.testing.expect(std.mem.indexOf(u8, nested_retrieve_envelope.result.?.success_json, "http_request") != null);
    try std.testing.expect(std.mem.indexOf(u8, nested_retrieve_envelope.result.?.success_json, "nested") != null);
}

test "memory commands expose summary and retrieval" {
    var app = try ourclaw.runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    var dispatcher = app.makeDispatcher();
    const embedding_provider_params = [_]framework.ValidationField{
        .{ .key = "path", .value = .{ .string = "memory.embedding_provider" } },
        .{ .key = "value", .value = .{ .string = "openai" } },
    };
    const set_embedding_provider = try dispatcher.dispatch(.{
        .request_id = "req_memory_embedding_provider",
        .method = "config.set",
        .params = embedding_provider_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (set_embedding_provider.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(set_embedding_provider.ok);

    const embedding_model_params = [_]framework.ValidationField{
        .{ .key = "path", .value = .{ .string = "memory.embedding_model" } },
        .{ .key = "value", .value = .{ .string = "text-embedding-3-small" } },
    };
    const set_embedding_model = try dispatcher.dispatch(.{
        .request_id = "req_memory_embedding_model",
        .method = "config.set",
        .params = embedding_model_params[0..],
        .source = .@"test",
        .authority = .admin,
    }, false);
    defer switch (set_embedding_model.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(set_embedding_model.ok);

    const descriptor = app.memory_runtime.embeddingDescriptor();
    try std.testing.expectEqualStrings("openai", descriptor.provider_id.?);
    try std.testing.expectEqualStrings("text-embedding-3-small", descriptor.model.?);

    try app.memory_runtime.appendUserPrompt("sess_mem", "hello memory");
    try app.memory_runtime.appendAssistantResponse("sess_mem", "memory answer");
    try app.memory_runtime.appendToolResult("sess_mem", "echo", "{\"message\":\"memory tool\"}");

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

    const exported = try dispatcher.dispatch(.{ .request_id = "req_memory_export", .method = "memory.snapshot_export", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer if (exported.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(exported.ok);
    try std.testing.expect(std.mem.indexOf(u8, exported.result.?.success_json, "\"entryCount\":") != null);

    const import_params = [_]framework.ValidationField{.{ .key = "snapshot_json", .value = .{ .string = "{\"version\":2,\"entries\":[{\"sessionId\":\"sess_import_smoke\",\"kind\":\"user_prompt\",\"content\":{\"text\":\"hello\"},\"tsUnixMs\":888001,\"embeddingProvider\":null,\"embeddingModel\":null}]}" } }};
    const imported = try dispatcher.dispatch(.{ .request_id = "req_memory_import", .method = "memory.snapshot_import", .params = import_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (imported.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(imported.ok);
    try std.testing.expect(std.mem.indexOf(u8, imported.result.?.success_json, "\"importedCount\":1") != null);

    const re_exported = try dispatcher.dispatch(.{ .request_id = "req_memory_export_after_import", .method = "memory.snapshot_export", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer if (re_exported.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(re_exported.ok);
    try std.testing.expect(std.mem.indexOf(u8, re_exported.result.?.success_json, "\"tsUnixMs\":888001") != null);
    try std.testing.expect(std.mem.indexOf(u8, re_exported.result.?.success_json, "\"embeddingProvider\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, re_exported.result.?.success_json, "\"embeddingModel\":null") != null);

    const imported_summary_params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_import_smoke" } },
    };
    const imported_summary = try dispatcher.dispatch(.{ .request_id = "req_memory_summary_imported", .method = "memory.summary", .params = imported_summary_params[0..], .source = .@"test", .authority = .admin }, false);
    defer if (imported_summary.result) |result| switch (result) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(imported_summary.ok);
    try std.testing.expect(std.mem.indexOf(u8, imported_summary.result.?.success_json, "sess_import_smoke") != null);

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
    try std.testing.expect(std.mem.indexOf(u8, retrieve.result.?.success_json, "\"rank\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, retrieve.result.?.success_json, "\"reason\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, retrieve.result.?.success_json, "\"embeddingStrategy\":\"provider_proxy_v1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, retrieve.result.?.success_json, "\"embeddingProvider\":\"openai\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, retrieve.result.?.success_json, "\"embeddingModel\":\"text-embedding-3-small\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, retrieve.result.?.success_json, "\"keywordOverlap\":") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, install.result.?.success_json, "\"autostart\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, install.result.?.success_json, "\"action\":\"install\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, install.result.?.success_json, "\"restartBudgetRemaining\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, install.result.?.success_json, "\"heartbeatHealthy\":") != null);

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
    try std.testing.expect(std.mem.indexOf(u8, start.result.?.success_json, "\"lockHeld\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, start.result.?.success_json, "\"action\":\"start\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, start.result.?.success_json, "\"hostRunning\":true") != null);

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
    try std.testing.expect(std.mem.indexOf(u8, service_status.result.?.success_json, "\"autostart\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, service_status.result.?.success_json, "\"restartBudgetRemaining\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, service_status.result.?.success_json, "\"heartbeatHealthy\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, service_status.result.?.success_json, "\"heartbeatStaleAfterMs\":") != null);

    const stop = try dispatcher.dispatch(.{ .request_id = "req_service_stop", .method = "service.stop", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (stop.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(stop.ok);
    try std.testing.expect(std.mem.indexOf(u8, stop.result.?.success_json, "\"changed\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, stop.result.?.success_json, "\"action\":\"stop\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, stop.result.?.success_json, "\"hostRunning\":false") != null);

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
    try std.testing.expect(std.mem.indexOf(u8, restart.result.?.success_json, "\"restartBudgetRemaining\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, restart.result.?.success_json, "\"budgetExhausted\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, restart.result.?.success_json, "\"action\":\"restart\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, restart.result.?.success_json, "\"gatewayHandlerAttached\":") != null);

    const restart_second = try dispatcher.dispatch(.{ .request_id = "req_service_restart_2", .method = "service.restart", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (restart_second.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(restart_second.ok);

    const restart_third = try dispatcher.dispatch(.{ .request_id = "req_service_restart_3", .method = "service.restart", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (restart_third.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(restart_third.ok);
    const restart_denied = try dispatcher.dispatch(.{ .request_id = "req_service_restart_4", .method = "service.restart", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (restart_denied.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(restart_denied.ok);
    try std.testing.expect(std.mem.indexOf(u8, restart_denied.result.?.success_json, "\"budgetExhausted\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, restart_denied.result.?.success_json, "\"restartBudgetRemaining\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, restart_denied.result.?.success_json, "\"stopApplied\":false") != null);

    app.service_manager.markStaleProcess();
    const service_status_after_stale = try dispatcher.dispatch(.{ .request_id = "req_service_status_after_stale", .method = "service.status", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (service_status_after_stale.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(service_status_after_stale.ok);
    try std.testing.expect(std.mem.indexOf(u8, service_status_after_stale.result.?.success_json, "\"staleProcessDetected\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, service_status_after_stale.result.?.success_json, "\"recoveryEligible\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, service_status_after_stale.result.?.success_json, "\"recoveryAction\":\"blocked\"") != null);

    const gateway_status = try dispatcher.dispatch(.{ .request_id = "req_gateway_status", .method = "gateway.status", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (gateway_status.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(gateway_status.ok);
    try std.testing.expect(std.mem.indexOf(u8, gateway_status.result.?.success_json, "\"running\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway_status.result.?.success_json, "\"listenerReady\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway_status.result.?.success_json, "\"reloadCount\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway_status.result.?.success_json, "\"healthState\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway_status.result.?.success_json, "\"healthMessage\":") != null);

    const gateway_reload = try dispatcher.dispatch(.{ .request_id = "req_gateway_reload", .method = "gateway.reload", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (gateway_reload.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(gateway_reload.ok);
    try std.testing.expect(std.mem.indexOf(u8, gateway_reload.result.?.success_json, "\"reloadCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway_reload.result.?.success_json, "\"action\":\"reload\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway_reload.result.?.success_json, "\"healthState\":") != null);

    const gateway_subscribe = try dispatcher.dispatch(.{ .request_id = "req_gateway_stream_subscribe", .method = "gateway.stream_subscribe", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (gateway_subscribe.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(gateway_subscribe.ok);
    try std.testing.expect(std.mem.indexOf(u8, gateway_subscribe.result.?.success_json, "\"subscriptionId\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway_subscribe.result.?.success_json, "\"streamSubscriptions\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway_subscribe.result.?.success_json, "\"healthState\":") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, cron_tick.result.?.success_json, "\"heartbeatBeatCount\":1") != null);

    const heartbeat_status = try dispatcher.dispatch(.{ .request_id = "req_heartbeat_status", .method = "heartbeat.status", .params = &.{}, .source = .@"test", .authority = .admin }, false);
    defer switch (heartbeat_status.result.?) {
        .success_json => |json| std.testing.allocator.free(json),
        .task_accepted => {},
    };
    try std.testing.expect(heartbeat_status.ok);
    try std.testing.expect(std.mem.indexOf(u8, heartbeat_status.result.?.success_json, "\"ageMs\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, heartbeat_status.result.?.success_json, "\"staleAfterMs\":") != null);

    const tunnel_params = [_]framework.ValidationField{
        .{ .key = "kind", .value = .{ .string = "cloudflare" } },
        .{ .key = "endpoint", .value = .{ .string = "mock://tunnel/healthy" } },
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
        .{ .key = "endpoint", .value = .{ .string = "mock://mcp/healthy" } },
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
