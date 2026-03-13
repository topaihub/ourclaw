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

        if (request.tool_id) |tool_id| {
            const initial_tool_payload = request.tool_input_json orelse "{}";
            const initial_tool_result = try self.tool_orchestrator.invokeWithExecution(
                request.session_id,
                request.stream_execution_id,
                tool_id,
                initial_tool_payload,
                request.authority,
            );
            tool_result_json = initial_tool_result;
            tool_id_owned = try self.allocator.dupe(u8, tool_id);
            tool_rounds = 1;
            try self.memory_runtime.appendToolResult(request.session_id, tool_id, initial_tool_result);
        }

        var round: usize = 0;
        while (true) : (round += 1) {
            const provider_supports_tools = self.provider_registry.supportsTools(request.provider_id) catch false;
            var assembled = try prompt_assembly.build(self.allocator, .{
                .session_id = request.session_id,
                .user_prompt = request.prompt,
                .authority = request.authority,
                .recall_summary = if (recall.entry_count > 0) recall.summary_text else null,
                .tool_result_json = tool_result_json,
                .allow_provider_tools = request.allow_provider_tools and provider_supports_tools,
                .tool_registry = self.tool_orchestrator.tool_registry,
            });
            defer assembled.deinit(self.allocator);
            const messages = try assembled.asProviderMessages(self.allocator);
            defer self.allocator.free(messages);

            var provider_response = try self.provider_registry.chatOnce(self.allocator, .{
                .provider_id = request.provider_id,
                .model = request.model,
                .messages = messages[0..],
                .enable_tools = request.allow_provider_tools and provider_supports_tools,
            });
            defer provider_response.deinit(self.allocator);

            self.allocator.free(selected_model);
            selected_model = try self.allocator.dupe(u8, provider_response.model);

            const stream_chunks = try self.provider_registry.chatStream(self.allocator, .{
                .provider_id = request.provider_id,
                .model = request.model,
                .messages = messages[0..],
                .enable_tools = request.allow_provider_tools and provider_supports_tools,
            });
            defer {
                for (stream_chunks) |*chunk| chunk.deinit(self.allocator);
                self.allocator.free(stream_chunks);
            }

            var text_buf: std.ArrayListUnmanaged(u8) = .empty;
            defer text_buf.deinit(self.allocator);
            for (stream_chunks) |chunk| {
                switch (chunk.kind) {
                    .text_delta => if (chunk.text) |text| {
                        if (text_buf.items.len > 0) {
                            try text_buf.append(self.allocator, ' ');
                        }
                        try text_buf.appendSlice(self.allocator, text);
                        const payload = try std.fmt.allocPrint(self.allocator, "{{\"text\":\"{s}\"}}", .{text});
                        defer self.allocator.free(payload);
                        _ = try self.stream_output.publishWithExecution(
                            request.session_id,
                            request.stream_execution_id,
                            "text.delta",
                            payload,
                        );
                    },
                    .tool_call => if (chunk.tool_name) |tool_name| {
                        try self.session_store.appendEvent(request.session_id, "provider.tool_call", tool_name);
                    },
                    .done => {},
                }
            }

            if (provider_response.tool_name) |provider_tool_name| {
                if (round >= request.max_tool_rounds) return error.ToolLoopLimitReached;
                if (tool_id_owned) |owned_tool_id| self.allocator.free(owned_tool_id);
                tool_id_owned = try self.allocator.dupe(u8, provider_tool_name);
                if (tool_result_json) |owned_tool_result| self.allocator.free(owned_tool_result);
                const tool_payload = provider_response.tool_input_json orelse "{}";
                const next_tool_result = try self.tool_orchestrator.invokeWithExecution(
                    request.session_id,
                    request.stream_execution_id,
                    provider_tool_name,
                    tool_payload,
                    request.authority,
                );
                tool_result_json = next_tool_result;
                tool_rounds += 1;
                try self.memory_runtime.appendToolResult(request.session_id, provider_tool_name, next_tool_result);
                continue;
            }

            self.allocator.free(final_text);
            final_text = if (text_buf.items.len > 0)
                try self.allocator.dupe(u8, text_buf.items)
            else
                try self.allocator.dupe(u8, provider_response.text);

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

        const events = try self.session_store.snapshotSince(self.allocator, request.session_id, event_start_index);
        return .{
            .session_id = try self.allocator.dupe(u8, request.session_id),
            .provider_id = try self.allocator.dupe(u8, request.provider_id),
            .model = try self.allocator.dupe(u8, selected_model),
            .final_response_text = try self.allocator.dupe(u8, final_text),
            .tool_id = if (tool_id_owned) |tool_id| tool_id else null,
            .tool_result_json = tool_result_json,
            .tool_rounds = tool_rounds,
            .provider_latency_ms = @intCast(@max(std.time.milliTimestamp() - started_at, 0)),
            .memory_entries_used = recall.entry_count,
            .events = events,
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
