const std = @import("std");
const framework = @import("framework");
const memory_runtime = @import("memory_runtime.zig");
const providers = @import("../providers/root.zig");
const session_state = @import("session_state.zig");
const stream_output = @import("stream_output.zig");
const tool_orchestrator = @import("tool_orchestrator.zig");
const prompt_assembly = @import("prompt_assembly.zig");

pub const ProviderRegistry = providers.ProviderRegistry;
pub const ProviderMessage = providers.ProviderMessage;
pub const MemoryRuntime = memory_runtime.MemoryRuntime;
pub const SessionEvent = session_state.SessionEvent;
pub const StreamOutput = stream_output.StreamOutput;
pub const SessionStore = session_state.SessionStore;
pub const ToolOrchestrator = tool_orchestrator.ToolOrchestrator;
pub const Authority = framework.Authority;

pub const AgentRunRequest = struct {
    session_id: []const u8,
    prompt: []const u8,
    provider_id: []const u8 = "openai",
    model: ?[]const u8 = null,
    tool_id: ?[]const u8 = null,
    tool_input_json: ?[]const u8 = null,
    stream_execution_id: ?[]const u8 = null,
    allow_provider_tools: bool = true,
    max_tool_rounds: usize = 4,
    authority: Authority = .operator,
    prompt_profile: prompt_assembly.PromptProfile = .default,
    channel_id: []const u8 = "runtime",
    identity_label: ?[]const u8 = null,
    response_mode: prompt_assembly.ResponseMode = .standard,
};

pub const AgentRunResult = struct {
    session_id: []u8,
    provider_id: []u8,
    model: []u8,
    response_text: []u8,
    tool_id: ?[]u8 = null,
    tool_result_json: ?[]u8 = null,
    tool_rounds: usize = 0,
    provider_latency_ms: u64,
    memory_entries_used: usize = 0,
    session_event_count: usize,

    pub fn deinit(self: *AgentRunResult, allocator: std.mem.Allocator) void {
        allocator.free(self.session_id);
        allocator.free(self.provider_id);
        allocator.free(self.model);
        allocator.free(self.response_text);
        if (self.tool_id) |tool_id| allocator.free(tool_id);
        if (self.tool_result_json) |tool_result_json| allocator.free(tool_result_json);
    }
};

pub const AgentStreamResult = struct {
    session_id: []u8,
    provider_id: []u8,
    model: []u8,
    final_response_text: []u8,
    tool_id: ?[]u8 = null,
    tool_result_json: ?[]u8 = null,
    tool_rounds: usize = 0,
    provider_latency_ms: u64,
    memory_entries_used: usize = 0,
    events: []SessionEvent,

    pub fn deinit(self: *AgentStreamResult, allocator: std.mem.Allocator) void {
        allocator.free(self.session_id);
        allocator.free(self.provider_id);
        allocator.free(self.model);
        allocator.free(self.final_response_text);
        if (self.tool_id) |tool_id| allocator.free(tool_id);
        if (self.tool_result_json) |tool_result_json| allocator.free(tool_result_json);
        for (self.events) |*event| event.deinit(allocator);
        allocator.free(self.events);
    }
};

pub const AgentRuntime = struct {
    allocator: std.mem.Allocator,
    provider_registry: *ProviderRegistry,
    memory_runtime: *MemoryRuntime,
    session_store: *SessionStore,
    stream_output: *StreamOutput,
    tool_orchestrator: *ToolOrchestrator,

    const Self = @This();
    const ToolRoundSource = enum {
        request_seed,
        provider_loop,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        provider_registry: *ProviderRegistry,
        memory_runtime_ref: *MemoryRuntime,
        session_store: *SessionStore,
        stream_output_ref: *StreamOutput,
        tool_orchestrator_ref: *ToolOrchestrator,
    ) Self {
        return .{
            .allocator = allocator,
            .provider_registry = provider_registry,
            .memory_runtime = memory_runtime_ref,
            .session_store = session_store,
            .stream_output = stream_output_ref,
            .tool_orchestrator = tool_orchestrator_ref,
        };
    }

    pub fn run(self: *Self, request: AgentRunRequest) anyerror!AgentRunResult {
        var stream_result = try self.runStream(request);
        defer stream_result.deinit(self.allocator);

        return .{
            .session_id = try self.allocator.dupe(u8, stream_result.session_id),
            .provider_id = try self.allocator.dupe(u8, stream_result.provider_id),
            .model = try self.allocator.dupe(u8, stream_result.model),
            .response_text = try self.allocator.dupe(u8, stream_result.final_response_text),
            .tool_id = if (stream_result.tool_id) |tool_id| try self.allocator.dupe(u8, tool_id) else null,
            .tool_result_json = if (stream_result.tool_result_json) |tool_result_json| try self.allocator.dupe(u8, tool_result_json) else null,
            .tool_rounds = stream_result.tool_rounds,
            .provider_latency_ms = stream_result.provider_latency_ms,
            .memory_entries_used = stream_result.memory_entries_used,
            .session_event_count = stream_result.events.len,
        };
    }

    pub fn runStream(self: *Self, request: AgentRunRequest) anyerror!AgentStreamResult {
        const started_at = std.time.milliTimestamp();
        const event_start_index = self.session_store.countEvents(request.session_id);

        errdefer |run_err| {
            self.publishRunFailure(request.session_id, request.stream_execution_id, run_err) catch {};
        }

        _ = try self.stream_output.publishWithExecution(
            request.session_id,
            request.stream_execution_id,
            "status.update",
            "{\"phase\":\"started\"}",
        );
        try self.session_store.appendEvent(request.session_id, "user.prompt", request.prompt);
        try self.memory_runtime.appendUserPrompt(request.session_id, request.prompt);

        var recall = try self.memory_runtime.recallForTurn(self.allocator, request.session_id, 6);
        defer recall.deinit(self.allocator);

        var tool_result_json: ?[]u8 = null;
        errdefer if (tool_result_json) |value| self.allocator.free(value);
        var tool_id_owned: ?[]u8 = null;
        errdefer if (tool_id_owned) |value| self.allocator.free(value);
        var final_text = try self.allocator.dupe(u8, "");
        defer self.allocator.free(final_text);
        var selected_model = try self.allocator.dupe(u8, request.model orelse "");
        defer self.allocator.free(selected_model);
        var tool_rounds: usize = 0;
        var provider_rounds: usize = 0;

        if (request.tool_id) |tool_id| {
            try self.executeToolRound(
                request,
                tool_id,
                request.tool_input_json orelse "{}",
                .request_seed,
                provider_rounds,
                &tool_id_owned,
                &tool_result_json,
                &tool_rounds,
            );
        }

        while (true) {
            provider_rounds += 1;
            const provider_supports_tools = self.provider_registry.supportsTools(request.provider_id) catch false;
            const provider_tools_enabled = request.allow_provider_tools and provider_supports_tools;

            const provider_round_started_payload = try std.fmt.allocPrint(
                self.allocator,
                "{{\"phase\":\"provider.round.started\",\"round\":{d},\"providerToolsEnabled\":{s}}}",
                .{ provider_rounds, if (provider_tools_enabled) "true" else "false" },
            );
            defer self.allocator.free(provider_round_started_payload);
            _ = try self.stream_output.publishWithExecution(
                request.session_id,
                request.stream_execution_id,
                "status.update",
                provider_round_started_payload,
            );

            var prompt_snapshot = try self.session_store.snapshotMeta(self.allocator, request.session_id);
            defer prompt_snapshot.deinit(self.allocator);

            var assembled = try prompt_assembly.build(self.allocator, .{
                .session_id = request.session_id,
                .user_prompt = request.prompt,
                .authority = request.authority,
                .profile = request.prompt_profile,
                .channel_id = request.channel_id,
                .identity_label = request.identity_label,
                .response_mode = request.response_mode,
                .session_event_count = prompt_snapshot.event_count,
                .tool_trace_count = prompt_snapshot.tool_trace_count,
                .recall_summary = if (recall.entry_count > 0) recall.summary_text else null,
                .tool_result_json = tool_result_json,
                .allow_provider_tools = provider_tools_enabled,
                .tool_registry = self.tool_orchestrator.tool_registry,
            });
            defer assembled.deinit(self.allocator);
            const messages = try assembled.asProviderMessages(self.allocator);
            defer self.allocator.free(messages);

            var provider_response = try self.provider_registry.chatOnce(self.allocator, .{
                .provider_id = request.provider_id,
                .model = request.model,
                .messages = messages[0..],
                .enable_tools = provider_tools_enabled,
            });
            defer provider_response.deinit(self.allocator);

            self.allocator.free(selected_model);
            selected_model = try self.allocator.dupe(u8, provider_response.model);

            const provider_round_completed_payload = try std.fmt.allocPrint(
                self.allocator,
                "{{\"round\":{d},\"providerId\":\"{s}\",\"model\":\"{s}\",\"toolRequested\":{s}}}",
                .{ provider_rounds, request.provider_id, provider_response.model, if (provider_response.tool_name != null) "true" else "false" },
            );
            defer self.allocator.free(provider_round_completed_payload);
            _ = try self.stream_output.publishWithExecution(
                request.session_id,
                request.stream_execution_id,
                "provider.round.completed",
                provider_round_completed_payload,
            );

            if (provider_response.tool_name) |provider_tool_name| {
                const tool_payload = provider_response.tool_input_json orelse "{}";
                const provider_tool_payload = try std.fmt.allocPrint(
                    self.allocator,
                    "{{\"round\":{d},\"toolId\":\"{s}\",\"toolInput\":{s}}}",
                    .{ provider_rounds, provider_tool_name, tool_payload },
                );
                defer self.allocator.free(provider_tool_payload);
                _ = try self.stream_output.publishWithExecution(
                    request.session_id,
                    request.stream_execution_id,
                    "provider.tool.call",
                    provider_tool_payload,
                );

                if (!provider_tools_enabled) {
                    return error.ProviderToolCallNotAllowed;
                }

                try self.executeToolRound(
                    request,
                    provider_tool_name,
                    tool_payload,
                    .provider_loop,
                    provider_rounds,
                    &tool_id_owned,
                    &tool_result_json,
                    &tool_rounds,
                );
                continue;
            }

            try self.publishProviderTextDeltas(request.session_id, request.stream_execution_id, provider_response.text);

            self.allocator.free(final_text);
            final_text = try self.allocator.dupe(u8, provider_response.text);

            const final_payload = try std.fmt.allocPrint(self.allocator, "{{\"text\":\"{s}\"}}", .{final_text});
            defer self.allocator.free(final_payload);
            _ = try self.stream_output.publishWithExecution(
                request.session_id,
                request.stream_execution_id,
                "final.result",
                final_payload,
            );
            try self.session_store.appendEvent(request.session_id, "assistant.response", final_text);
            try self.memory_runtime.appendAssistantResponse(request.session_id, final_text);
            break;
        }

        const provider_latency_ms: u64 = @intCast(@max(std.time.milliTimestamp() - started_at, 0));
        const turn_payload = if (tool_id_owned) |tool_id|
            try std.fmt.allocPrint(
                self.allocator,
                "{{\"providerId\":\"{s}\",\"model\":\"{s}\",\"providerRounds\":{d},\"toolId\":\"{s}\",\"toolRounds\":{d},\"providerLatencyMs\":{d},\"memoryEntriesUsed\":{d}}}",
                .{ request.provider_id, selected_model, provider_rounds, tool_id, tool_rounds, provider_latency_ms, recall.entry_count },
            )
        else
            try std.fmt.allocPrint(
                self.allocator,
                "{{\"providerId\":\"{s}\",\"model\":\"{s}\",\"providerRounds\":{d},\"toolId\":null,\"toolRounds\":{d},\"providerLatencyMs\":{d},\"memoryEntriesUsed\":{d}}}",
                .{ request.provider_id, selected_model, provider_rounds, tool_rounds, provider_latency_ms, recall.entry_count },
            );
        defer self.allocator.free(turn_payload);
        _ = try self.stream_output.publishWithExecution(
            request.session_id,
            request.stream_execution_id,
            "session.turn.completed",
            turn_payload,
        );

        var turn_snapshot = try self.session_store.snapshotMeta(self.allocator, request.session_id);
        defer turn_snapshot.deinit(self.allocator);
        const snapshot_status_payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"phase\":\"session.snapshot.updated\",\"eventCount\":{d},\"toolTraceCount\":{d},\"toolRounds\":{d}}}",
            .{ turn_snapshot.event_count, turn_snapshot.tool_trace_count, turn_snapshot.latest_tool_rounds },
        );
        defer self.allocator.free(snapshot_status_payload);
        _ = try self.stream_output.publishWithExecution(
            request.session_id,
            request.stream_execution_id,
            "status.update",
            snapshot_status_payload,
        );

        const events = try self.session_store.snapshotSince(self.allocator, request.session_id, event_start_index);
        const resolved_tool_rounds = if (turn_snapshot.latest_tool_rounds > 0)
            turn_snapshot.latest_tool_rounds
        else
            tool_rounds;
        const resolved_memory_entries_used = if (turn_snapshot.latest_memory_entries_used > 0)
            turn_snapshot.latest_memory_entries_used
        else
            recall.entry_count;
        return .{
            .session_id = try self.allocator.dupe(u8, request.session_id),
            .provider_id = try self.allocator.dupe(u8, request.provider_id),
            .model = try self.allocator.dupe(u8, selected_model),
            .final_response_text = try self.allocator.dupe(u8, final_text),
            .tool_id = if (tool_id_owned) |tool_id|
                tool_id
            else if (turn_snapshot.latest_tool_id) |snapshot_tool_id|
                try self.allocator.dupe(u8, snapshot_tool_id)
            else
                null,
            .tool_result_json = if (tool_result_json) |owned_tool_result|
                owned_tool_result
            else if (turn_snapshot.latest_tool_result_json) |snapshot_tool_result|
                try self.allocator.dupe(u8, snapshot_tool_result)
            else
                null,
            .tool_rounds = resolved_tool_rounds,
            .provider_latency_ms = provider_latency_ms,
            .memory_entries_used = resolved_memory_entries_used,
            .events = events,
        };
    }

    fn executeToolRound(
        self: *Self,
        request: AgentRunRequest,
        tool_id: []const u8,
        tool_input_json: []const u8,
        source: ToolRoundSource,
        provider_round: usize,
        tool_id_owned: *?[]u8,
        tool_result_json: *?[]u8,
        tool_rounds: *usize,
    ) anyerror!void {
        if (tool_rounds.* >= request.max_tool_rounds) {
            return error.ToolLoopLimitReached;
        }

        const next_tool_round = tool_rounds.* + 1;
        const loop_started_payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"source\":\"{s}\",\"providerRound\":{d},\"toolRound\":{d},\"toolId\":\"{s}\",\"input\":{s}}}",
            .{ roundSourceText(source), provider_round, next_tool_round, tool_id, tool_input_json },
        );
        defer self.allocator.free(loop_started_payload);
        _ = try self.stream_output.publishWithExecution(
            request.session_id,
            request.stream_execution_id,
            "tool.loop.requested",
            loop_started_payload,
        );

        const next_tool_result = try self.tool_orchestrator.invokeSingle(.{
            .session_id = request.session_id,
            .execution_id = request.stream_execution_id,
            .tool_id = tool_id,
            .input_json = tool_input_json,
            .authority = request.authority,
        });

        if (tool_id_owned.*) |owned_tool_id| self.allocator.free(owned_tool_id);
        tool_id_owned.* = try self.allocator.dupe(u8, tool_id);
        if (tool_result_json.*) |owned_tool_result| self.allocator.free(owned_tool_result);
        tool_result_json.* = next_tool_result;
        tool_rounds.* = next_tool_round;
        try self.memory_runtime.appendToolResult(request.session_id, tool_id, next_tool_result);

        const loop_completed_payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"source\":\"{s}\",\"providerRound\":{d},\"toolRound\":{d},\"toolId\":\"{s}\",\"result\":{s}}}",
            .{ roundSourceText(source), provider_round, next_tool_round, tool_id, next_tool_result },
        );
        defer self.allocator.free(loop_completed_payload);
        _ = try self.stream_output.publishWithExecution(
            request.session_id,
            request.stream_execution_id,
            "tool.loop.completed",
            loop_completed_payload,
        );
    }

    fn publishProviderTextDeltas(self: *Self, session_id: []const u8, execution_id: ?[]const u8, response_text: []const u8) anyerror!void {
        var parts = std.mem.splitScalar(u8, response_text, ' ');
        while (parts.next()) |part| {
            if (part.len == 0) continue;
            const payload = try std.fmt.allocPrint(self.allocator, "{{\"text\":\"{s}\"}}", .{part});
            defer self.allocator.free(payload);
            _ = try self.stream_output.publishWithExecution(session_id, execution_id, "text.delta", payload);
        }
    }

    fn publishRunFailure(self: *Self, session_id: []const u8, execution_id: ?[]const u8, run_err: anyerror) anyerror!void {
        const code = @errorName(run_err);
        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"stage\":\"agent_runtime\",\"errorCode\":\"{s}\",\"message\":\"{s}\"}}",
            .{ code, code },
        );
        defer self.allocator.free(payload);
        _ = self.stream_output.publishWithExecution(session_id, execution_id, "error", payload) catch {};
        _ = self.stream_output.publishWithExecution(session_id, execution_id, "session.turn.failed", payload) catch {};
    }

    fn roundSourceText(source: ToolRoundSource) []const u8 {
        return switch (source) {
            .request_seed => "request_seed",
            .provider_loop => "provider_loop",
        };
    }
};

test "agent runtime runs prompt through provider and optional tool" {
    var provider_registry = providers.ProviderRegistry.init(std.testing.allocator);
    defer provider_registry.deinit();
    var secrets = @import("../security/policy.zig").MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    provider_registry.setSecretStore(&secrets);
    try provider_registry.register(.{
        .id = "mock_openai",
        .label = "Mock OpenAI",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    var tool_registry = @import("../tools/root.zig").ToolRegistry.init(std.testing.allocator);
    defer tool_registry.deinit();
    try tool_registry.registerBuiltins();

    var memory = MemoryRuntime.init(std.testing.allocator);
    defer memory.deinit();
    var session_store = SessionStore.init(std.testing.allocator);
    defer session_store.deinit();
    var event_bus = framework.MemoryEventBus.init(std.testing.allocator);
    defer event_bus.deinit();
    var output = StreamOutput.init(std.testing.allocator, &session_store, null, event_bus.asEventBus());
    var orchestrator = ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var runtime = AgentRuntime.init(std.testing.allocator, &provider_registry, &memory, &session_store, &output, &orchestrator);

    var result = try runtime.run(.{
        .session_id = "sess_agent_01",
        .prompt = "hello",
        .provider_id = "mock_openai",
        .tool_id = "echo",
        .tool_input_json = "{\"message\":\"hi\"}",
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("final response after tool", result.response_text);
    try std.testing.expect(result.tool_result_json != null);
    try std.testing.expectEqual(@as(usize, 1), result.tool_rounds);
    try std.testing.expect(result.memory_entries_used >= 1);
    try std.testing.expect(result.session_event_count >= 3);
    try std.testing.expect(event_bus.count() >= 4);
}

test "agent runtime supports provider to tool to provider loop" {
    var provider_registry = providers.ProviderRegistry.init(std.testing.allocator);
    defer provider_registry.deinit();
    var secrets = @import("../security/policy.zig").MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    provider_registry.setSecretStore(&secrets);
    try provider_registry.register(.{
        .id = "mock_openai_loop",
        .label = "Mock OpenAI Loop",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    var tool_registry = @import("../tools/root.zig").ToolRegistry.init(std.testing.allocator);
    defer tool_registry.deinit();
    try tool_registry.registerBuiltins();

    var memory = MemoryRuntime.init(std.testing.allocator);
    defer memory.deinit();
    var session_store = SessionStore.init(std.testing.allocator);
    defer session_store.deinit();
    var output = StreamOutput.init(std.testing.allocator, &session_store, null, null);
    var orchestrator = ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var runtime = AgentRuntime.init(std.testing.allocator, &provider_registry, &memory, &session_store, &output, &orchestrator);

    var result = try runtime.run(.{
        .session_id = "sess_agent_loop",
        .prompt = "CALL_TOOL:echo",
        .provider_id = "mock_openai_loop",
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("final response after tool", result.response_text);
    try std.testing.expect(result.tool_id != null);
    try std.testing.expect(result.tool_rounds >= 1);

    const events = session_store.find("sess_agent_loop").?.events.items;
    try std.testing.expect(hasEventKind(events, "provider.tool.call"));
    try std.testing.expect(hasEventKind(events, "tool.loop.requested"));
    try std.testing.expect(hasEventKind(events, "tool.loop.completed"));
    try std.testing.expect(hasEventKind(events, "session.turn.completed"));

    var snapshot = try session_store.snapshotMeta(std.testing.allocator, "sess_agent_loop");
    defer snapshot.deinit(std.testing.allocator);
    try std.testing.expect(snapshot.latest_tool_id != null);
    try std.testing.expectEqualStrings("echo", snapshot.latest_tool_id.?);
    try std.testing.expect(snapshot.latest_tool_result_json != null);
    try std.testing.expect(snapshot.latest_model != null);
    try std.testing.expect(snapshot.latest_tool_rounds >= 1);
}

test "agent runtime writes failed turn when tool loop limit is hit" {
    var provider_registry = providers.ProviderRegistry.init(std.testing.allocator);
    defer provider_registry.deinit();

    var tool_registry = @import("../tools/root.zig").ToolRegistry.init(std.testing.allocator);
    defer tool_registry.deinit();
    try tool_registry.registerBuiltins();

    var memory = MemoryRuntime.init(std.testing.allocator);
    defer memory.deinit();
    var session_store = SessionStore.init(std.testing.allocator);
    defer session_store.deinit();
    var output = StreamOutput.init(std.testing.allocator, &session_store, null, null);
    var orchestrator = ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var runtime = AgentRuntime.init(std.testing.allocator, &provider_registry, &memory, &session_store, &output, &orchestrator);

    try std.testing.expectError(error.ToolLoopLimitReached, runtime.run(.{
        .session_id = "sess_agent_loop_limit",
        .prompt = "hello",
        .provider_id = "provider_unused",
        .tool_id = "echo",
        .tool_input_json = "{\"message\":\"hi\"}",
        .max_tool_rounds = 0,
    }));

    const events = session_store.find("sess_agent_loop_limit").?.events.items;
    try std.testing.expect(hasEventKind(events, "error"));
    try std.testing.expect(hasEventKind(events, "session.turn.failed"));

    var snapshot = try session_store.snapshotMeta(std.testing.allocator, "sess_agent_loop_limit");
    defer snapshot.deinit(std.testing.allocator);
    try std.testing.expect(snapshot.last_error_code != null);
    try std.testing.expectEqualStrings("ToolLoopLimitReached", snapshot.last_error_code.?);
}

test "agent runtime injects system and tools prompt into provider payload" {
    var provider_registry = providers.ProviderRegistry.init(std.testing.allocator);
    defer provider_registry.deinit();
    var secrets = @import("../security/policy.zig").MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    provider_registry.setSecretStore(&secrets);
    try provider_registry.register(.{
        .id = "mock_openai_prompt_assembly",
        .label = "Mock OpenAI Prompt Assembly",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    var tool_registry = @import("../tools/root.zig").ToolRegistry.init(std.testing.allocator);
    defer tool_registry.deinit();
    try tool_registry.registerBuiltins();

    var memory = MemoryRuntime.init(std.testing.allocator);
    defer memory.deinit();
    var session_store = SessionStore.init(std.testing.allocator);
    defer session_store.deinit();
    var output = StreamOutput.init(std.testing.allocator, &session_store, null, null);
    var orchestrator = ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var runtime = AgentRuntime.init(std.testing.allocator, &provider_registry, &memory, &session_store, &output, &orchestrator);

    var result = try runtime.run(.{
        .session_id = "sess_prompt_assembly",
        .prompt = "PROMPT_ASSEMBLY_PROBE",
        .provider_id = "mock_openai_prompt_assembly",
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("prompt assembly ok", result.response_text);
}

fn hasEventKind(events: []const session_state.SessionEvent, kind: []const u8) bool {
    for (events) |event| {
        if (std.mem.eql(u8, event.kind, kind)) return true;
    }
    return false;
}
