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
    tool_call_budget: usize = 4,
    provider_round_budget: usize = 4,
    provider_attempt_budget: usize = 8,
    confirm_tool_risk: bool = false,
    provider_timeout_secs: u32 = 60,
    provider_retry_budget: u8 = 0,
    total_deadline_ms: u64 = 0,
    cancel_requested: ?*const std.atomic.Value(bool) = null,
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

        try ensureNotCancelled(request);

        if (!framework.Authority.allows(request.authority, .operator) and std.mem.eql(u8, request.provider_id, "openai")) {
            return error.ProviderPolicyDenied;
        }

        errdefer |run_err| {
            self.publishRunFailure(request.session_id, request.stream_execution_id, run_err) catch {};
        }

        const execution_budget_started_payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"phase\":\"execution.budget.started\",\"providerRoundBudget\":{d},\"toolCallBudget\":{d},\"providerRetryBudget\":{d},\"totalDeadlineMs\":{d}}}",
            .{ request.provider_round_budget, request.tool_call_budget, request.provider_retry_budget, request.total_deadline_ms },
        );
        defer self.allocator.free(execution_budget_started_payload);
        _ = try self.stream_output.publishWithExecution(
            request.session_id,
            request.stream_execution_id,
            "status.update",
            execution_budget_started_payload,
        );

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
        var remaining_tool_budget = request.tool_call_budget;
        var remaining_provider_attempt_budget = request.provider_attempt_budget;

        if (request.tool_id) |tool_id| {
            try ensureNotCancelled(request);
            try self.executeToolRound(
                request,
                tool_id,
                request.tool_input_json orelse "{}",
                .request_seed,
                provider_rounds,
                &tool_id_owned,
                &tool_result_json,
                &tool_rounds,
                &remaining_tool_budget,
            );
        }

        while (true) {
            try ensureExecutionBudget(request, started_at, provider_rounds, remaining_tool_budget);
            provider_rounds += 1;
            try ensureNotCancelled(request);
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

            const selected_model_slice = if (request.model) |model| model else (self.provider_registry.find(request.provider_id) orelse return error.ProviderNotFound).default_model;
            const provider_chunks = try self.provider_registry.chatStream(self.allocator, .{
                .provider_id = request.provider_id,
                .model = request.model,
                .messages = messages[0..],
                .enable_tools = provider_tools_enabled,
                .timeout_secs = request.provider_timeout_secs,
                .retry_budget = request.provider_retry_budget,
                .remaining_attempt_budget = &remaining_provider_attempt_budget,
                .cancel_requested = request.cancel_requested,
            });
            defer {
                for (provider_chunks) |*chunk| chunk.deinit(self.allocator);
                self.allocator.free(provider_chunks);
            }

            try ensureNotCancelled(request);
            try ensureExecutionBudget(request, started_at, provider_rounds, remaining_tool_budget);

            self.allocator.free(selected_model);
            selected_model = try self.allocator.dupe(u8, selected_model_slice);

            var streamed_text: std.ArrayListUnmanaged(u8) = .empty;
            defer streamed_text.deinit(self.allocator);
            var streamed_tool_name: ?[]u8 = null;
            defer if (streamed_tool_name) |value| self.allocator.free(value);
            var streamed_tool_input: ?[]u8 = null;
            defer if (streamed_tool_input) |value| self.allocator.free(value);
            var streamed_finish_reason: ?[]u8 = null;
            defer if (streamed_finish_reason) |value| self.allocator.free(value);

            for (provider_chunks) |chunk| {
                try ensureNotCancelled(request);
                switch (chunk.kind) {
                    .text_delta => {
                        const text = chunk.text orelse continue;
                        try streamed_text.appendSlice(self.allocator, text);
                        try self.publishProviderTextDelta(request.session_id, request.stream_execution_id, text, "provider_native");
                    },
                    .tool_call => {
                        if (streamed_tool_name == null and chunk.tool_name != null) {
                            streamed_tool_name = try self.allocator.dupe(u8, chunk.tool_name.?);
                        }
                        if (streamed_tool_input == null and chunk.tool_input_json != null) {
                            streamed_tool_input = try self.allocator.dupe(u8, chunk.tool_input_json.?);
                        }
                        const tool_payload = streamed_tool_input orelse chunk.tool_input_json orelse "{}";
                        const provider_tool_payload = try std.fmt.allocPrint(
                            self.allocator,
                            "{{\"round\":{d},\"toolId\":\"{s}\",\"toolInput\":{s},\"streamSource\":\"provider_native\"}}",
                            .{ provider_rounds, chunk.tool_name orelse streamed_tool_name.?, tool_payload },
                        );
                        defer self.allocator.free(provider_tool_payload);
                        _ = try self.stream_output.publishWithExecution(
                            request.session_id,
                            request.stream_execution_id,
                            "provider.tool.call",
                            provider_tool_payload,
                        );
                    },
                    .done => {
                        if (chunk.finish_reason) |finish_reason| {
                            streamed_finish_reason = try self.allocator.dupe(u8, finish_reason);
                        }
                    },
                }
            }

            const provider_round_completed_payload = try std.fmt.allocPrint(
                self.allocator,
                "{{\"round\":{d},\"providerId\":\"{s}\",\"model\":\"{s}\",\"toolRequested\":{s},\"finishReason\":\"{s}\",\"streamSource\":\"provider_native\"}}",
                .{ provider_rounds, request.provider_id, selected_model, if (streamed_tool_name != null) "true" else "false", streamed_finish_reason orelse "stop" },
            );
            defer self.allocator.free(provider_round_completed_payload);
            _ = try self.stream_output.publishWithExecution(
                request.session_id,
                request.stream_execution_id,
                "provider.round.completed",
                provider_round_completed_payload,
            );

            if (streamed_tool_name) |provider_tool_name| {
                const tool_payload = streamed_tool_input orelse "{}";

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
                    &remaining_tool_budget,
                );
                try ensureNotCancelled(request);
                continue;
            }

            self.allocator.free(final_text);
            final_text = try self.allocator.dupe(u8, streamed_text.items);

            const final_payload = try std.fmt.allocPrint(self.allocator, "{{\"text\":\"{s}\",\"streamSource\":\"runtime_synthesized\"}}", .{final_text});
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
                "{{\"providerId\":\"{s}\",\"model\":\"{s}\",\"providerRounds\":{d},\"providerRoundBudget\":{d},\"providerRoundsRemaining\":{d},\"providerAttemptBudget\":{d},\"providerAttemptsRemaining\":{d},\"toolId\":\"{s}\",\"toolRounds\":{d},\"toolCallBudget\":{d},\"toolCallsRemaining\":{d},\"providerRetryBudget\":{d},\"totalDeadlineMs\":{d},\"providerLatencyMs\":{d},\"memoryEntriesUsed\":{d}}}",
                .{ request.provider_id, selected_model, provider_rounds, request.provider_round_budget, remainingProviderRounds(request.provider_round_budget, provider_rounds), request.provider_attempt_budget, remaining_provider_attempt_budget, tool_id, tool_rounds, request.tool_call_budget, remaining_tool_budget, request.provider_retry_budget, request.total_deadline_ms, provider_latency_ms, recall.entry_count },
            )
        else
            try std.fmt.allocPrint(
                self.allocator,
                "{{\"providerId\":\"{s}\",\"model\":\"{s}\",\"providerRounds\":{d},\"providerRoundBudget\":{d},\"providerRoundsRemaining\":{d},\"providerAttemptBudget\":{d},\"providerAttemptsRemaining\":{d},\"toolId\":null,\"toolRounds\":{d},\"toolCallBudget\":{d},\"toolCallsRemaining\":{d},\"providerRetryBudget\":{d},\"totalDeadlineMs\":{d},\"providerLatencyMs\":{d},\"memoryEntriesUsed\":{d}}}",
                .{ request.provider_id, selected_model, provider_rounds, request.provider_round_budget, remainingProviderRounds(request.provider_round_budget, provider_rounds), request.provider_attempt_budget, remaining_provider_attempt_budget, tool_rounds, request.tool_call_budget, remaining_tool_budget, request.provider_retry_budget, request.total_deadline_ms, provider_latency_ms, recall.entry_count },
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
        remaining_tool_budget: *usize,
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
            .confirm_risk = request.confirm_tool_risk,
            .remaining_budget = remaining_tool_budget,
            .cancel_requested = request.cancel_requested,
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

    fn publishProviderTextDelta(self: *Self, session_id: []const u8, execution_id: ?[]const u8, text: []const u8, stream_source: []const u8) anyerror!void {
        const payload = try std.fmt.allocPrint(self.allocator, "{{\"text\":\"{s}\",\"streamSource\":\"{s}\"}}", .{ text, stream_source });
        defer self.allocator.free(payload);
        _ = try self.stream_output.publishWithExecution(session_id, execution_id, "text.delta", payload);
    }

    fn ensureNotCancelled(request: AgentRunRequest) anyerror!void {
        if (request.cancel_requested) |signal| {
            if (signal.load(.acquire)) return error.StreamCancelled;
        }
    }

    fn ensureExecutionBudget(request: AgentRunRequest, started_at: i64, provider_rounds_completed: usize, remaining_tool_budget: usize) anyerror!void {
        _ = remaining_tool_budget;
        if (provider_rounds_completed >= request.provider_round_budget) return error.ProviderRoundBudgetExceeded;
        if (request.total_deadline_ms > 0) {
            const elapsed_ms: u64 = @intCast(@max(std.time.milliTimestamp() - started_at, 0));
            if (elapsed_ms >= request.total_deadline_ms) return error.ExecutionDeadlineExceeded;
        }
    }

    fn remainingProviderRounds(provider_round_budget: usize, provider_rounds_used: usize) usize {
        return if (provider_rounds_used >= provider_round_budget) 0 else provider_round_budget - provider_rounds_used;
    }

    fn publishRunFailure(self: *Self, session_id: []const u8, execution_id: ?[]const u8, run_err: anyerror) anyerror!void {
        const provider_error = providers.ProviderRegistry.mapError(run_err);
        const tool_error = @import("../tools/root.zig").ToolRegistry.mapError(run_err);
        const provider_like = !std.mem.eql(u8, provider_error.code, "PROVIDER_EXECUTION_FAILED") or run_err == error.ProviderPolicyDenied;
        const code = if (run_err == error.ProviderPolicyDenied)
            "PROVIDER_POLICY_DENIED"
        else if (run_err == error.ProviderAttemptBudgetExceeded)
            "PROVIDER_ATTEMPT_BUDGET_EXCEEDED"
        else if (run_err == error.ExecutionDeadlineExceeded)
            "EXECUTION_DEADLINE_EXCEEDED"
        else if (run_err == error.ProviderRoundBudgetExceeded)
            "PROVIDER_ROUND_BUDGET_EXCEEDED"
        else if (provider_like)
            provider_error.code
        else if (!std.mem.eql(u8, tool_error.code, "TOOL_EXECUTION_FAILED"))
            tool_error.code
        else
            @errorName(run_err);
        const message = if (run_err == error.ProviderPolicyDenied)
            "provider use is denied by policy"
        else if (run_err == error.ProviderAttemptBudgetExceeded)
            "provider attempt budget has been exhausted"
        else if (run_err == error.ExecutionDeadlineExceeded)
            "execution deadline has been exceeded"
        else if (run_err == error.ProviderRoundBudgetExceeded)
            "provider round budget has been exhausted"
        else if (provider_like)
            provider_error.message
        else if (!std.mem.eql(u8, tool_error.code, "TOOL_EXECUTION_FAILED"))
            tool_error.message
        else
            @errorName(run_err);
        const stage = if (provider_like) "provider" else "agent_runtime";
        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"stage\":\"{s}\",\"errorCode\":\"{s}\",\"message\":\"{s}\"}}",
            .{ stage, code, message },
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

    const events = session_store.find("sess_agent_01").?.events.items;
    try std.testing.expect(std.mem.indexOf(u8, events[events.len - 2].payload_json, "runtime_synthesized") != null or hasEventPayload(events, "text.delta", "provider_native"));
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
    try std.testing.expect(hasEventPayload(events, "provider.tool.call", "provider_native"));

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

test "agent runtime writes provider timeout failure with mapped code" {
    var provider_registry = providers.ProviderRegistry.init(std.testing.allocator);
    defer provider_registry.deinit();
    var secrets = @import("../security/policy.zig").MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    provider_registry.setSecretStore(&secrets);
    try provider_registry.register(.{
        .id = "mock_openai_timeout",
        .label = "Mock OpenAI Timeout",
        .endpoint = "mock://openai/chat_timeout",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
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
    defer output.deinit();
    var orchestrator = ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var runtime = AgentRuntime.init(std.testing.allocator, &provider_registry, &memory, &session_store, &output, &orchestrator);

    try std.testing.expectError(error.ProviderTimeout, runtime.run(.{
        .session_id = "sess_provider_timeout",
        .prompt = "hello",
        .provider_id = "mock_openai_timeout",
    }));

    const events = session_store.find("sess_provider_timeout").?.events.items;
    try std.testing.expect(hasEventKind(events, "session.turn.failed"));
    try std.testing.expect(std.mem.indexOf(u8, events[events.len - 1].payload_json, "PROVIDER_TIMEOUT") != null);
}

test "agent runtime emits provider native stream deltas and finish reason" {
    var provider_registry = providers.ProviderRegistry.init(std.testing.allocator);
    defer provider_registry.deinit();
    var secrets = @import("../security/policy.zig").MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    provider_registry.setSecretStore(&secrets);
    try provider_registry.register(.{
        .id = "mock_openai_stream_native",
        .label = "Mock OpenAI Stream Native",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
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
    defer output.deinit();
    var orchestrator = ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var runtime = AgentRuntime.init(std.testing.allocator, &provider_registry, &memory, &session_store, &output, &orchestrator);

    var result = try runtime.run(.{
        .session_id = "sess_stream_native",
        .prompt = "hello",
        .provider_id = "mock_openai_stream_native",
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("mock openai response", result.response_text);
    const events = session_store.find("sess_stream_native").?.events.items;
    try std.testing.expect(hasEventPayload(events, "text.delta", "provider_native"));
    try std.testing.expect(hasEventPayload(events, "provider.round.completed", "\"finishReason\":\"stop\""));
    try std.testing.expect(hasEventPayload(events, "final.result", "runtime_synthesized"));
}

test "agent runtime writes malformed stream failure with mapped code" {
    var provider_registry = providers.ProviderRegistry.init(std.testing.allocator);
    defer provider_registry.deinit();
    var secrets = @import("../security/policy.zig").MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    provider_registry.setSecretStore(&secrets);
    try provider_registry.register(.{
        .id = "mock_openai_stream_malformed_runtime",
        .label = "Mock OpenAI Stream Malformed",
        .endpoint = "mock://openai/chat_stream_malformed",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
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
    defer output.deinit();
    var orchestrator = ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var runtime = AgentRuntime.init(std.testing.allocator, &provider_registry, &memory, &session_store, &output, &orchestrator);

    try std.testing.expectError(error.ProviderMalformedResponse, runtime.run(.{
        .session_id = "sess_stream_malformed",
        .prompt = "hello",
        .provider_id = "mock_openai_stream_malformed_runtime",
    }));

    const events = session_store.find("sess_stream_malformed").?.events.items;
    try std.testing.expect(std.mem.indexOf(u8, events[events.len - 1].payload_json, "PROVIDER_MALFORMED_RESPONSE") != null);
}

test "agent runtime writes upstream close stream failure with mapped code" {
    var provider_registry = providers.ProviderRegistry.init(std.testing.allocator);
    defer provider_registry.deinit();
    var secrets = @import("../security/policy.zig").MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    provider_registry.setSecretStore(&secrets);
    try provider_registry.register(.{
        .id = "mock_openai_stream_upstream_close_runtime",
        .label = "Mock OpenAI Stream Upstream Close",
        .endpoint = "mock://openai/chat_stream_upstream_close",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
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
    defer output.deinit();
    var orchestrator = ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var runtime = AgentRuntime.init(std.testing.allocator, &provider_registry, &memory, &session_store, &output, &orchestrator);

    try std.testing.expectError(error.ProviderHttpFailed, runtime.run(.{
        .session_id = "sess_stream_upstream_close",
        .prompt = "hello",
        .provider_id = "mock_openai_stream_upstream_close_runtime",
    }));

    const events = session_store.find("sess_stream_upstream_close").?.events.items;
    try std.testing.expect(std.mem.indexOf(u8, events[events.len - 1].payload_json, "PROVIDER_HTTP_FAILED") != null);
}

test "agent runtime writes retry exhausted stream failure with mapped code" {
    var provider_registry = providers.ProviderRegistry.init(std.testing.allocator);
    defer provider_registry.deinit();
    var secrets = @import("../security/policy.zig").MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    provider_registry.setSecretStore(&secrets);
    try provider_registry.register(.{
        .id = "mock_openai_stream_retry_exhausted_runtime",
        .label = "Mock OpenAI Stream Retry Exhausted",
        .endpoint = "mock://openai/chat_stream_retry_exhausted",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
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
    defer output.deinit();
    var orchestrator = ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var runtime = AgentRuntime.init(std.testing.allocator, &provider_registry, &memory, &session_store, &output, &orchestrator);

    try std.testing.expectError(error.ProviderRetryExhausted, runtime.run(.{
        .session_id = "sess_stream_retry_exhausted",
        .prompt = "hello",
        .provider_id = "mock_openai_stream_retry_exhausted_runtime",
        .provider_retry_budget = 1,
    }));

    const events = session_store.find("sess_stream_retry_exhausted").?.events.items;
    try std.testing.expect(std.mem.indexOf(u8, events[events.len - 1].payload_json, "PROVIDER_RETRY_EXHAUSTED") != null);
}

test "agent runtime writes provider round budget exhaustion with mapped code" {
    var provider_registry = providers.ProviderRegistry.init(std.testing.allocator);
    defer provider_registry.deinit();
    var secrets = @import("../security/policy.zig").MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    provider_registry.setSecretStore(&secrets);
    try provider_registry.register(.{
        .id = "mock_openai_round_budget",
        .label = "Mock OpenAI Round Budget",
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
    defer output.deinit();
    var orchestrator = ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var runtime = AgentRuntime.init(std.testing.allocator, &provider_registry, &memory, &session_store, &output, &orchestrator);

    try std.testing.expectError(error.ProviderRoundBudgetExceeded, runtime.run(.{
        .session_id = "sess_round_budget_exhausted",
        .prompt = "CALL_TOOL:echo",
        .provider_id = "mock_openai_round_budget",
        .provider_round_budget = 1,
    }));

    const events = session_store.find("sess_round_budget_exhausted").?.events.items;
    try std.testing.expect(std.mem.indexOf(u8, events[events.len - 1].payload_json, "PROVIDER_ROUND_BUDGET_EXCEEDED") != null);
}

test "agent runtime writes execution deadline exhaustion with mapped code" {
    var provider_registry = providers.ProviderRegistry.init(std.testing.allocator);
    defer provider_registry.deinit();
    var secrets = @import("../security/policy.zig").MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    provider_registry.setSecretStore(&secrets);
    try provider_registry.register(.{
        .id = "mock_openai_deadline",
        .label = "Mock OpenAI Deadline",
        .endpoint = "mock://openai/chat_cancel_wait",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
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
    defer output.deinit();
    var orchestrator = ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var runtime = AgentRuntime.init(std.testing.allocator, &provider_registry, &memory, &session_store, &output, &orchestrator);

    try std.testing.expectError(error.ExecutionDeadlineExceeded, runtime.run(.{
        .session_id = "sess_deadline_exhausted",
        .prompt = "hello",
        .provider_id = "mock_openai_deadline",
        .total_deadline_ms = 1,
    }));

    const events = session_store.find("sess_deadline_exhausted").?.events.items;
    try std.testing.expect(std.mem.indexOf(u8, events[events.len - 1].payload_json, "EXECUTION_DEADLINE_EXCEEDED") != null);
}

test "agent runtime writes provider attempt budget exhaustion with mapped code" {
    var provider_registry = providers.ProviderRegistry.init(std.testing.allocator);
    defer provider_registry.deinit();
    var secrets = @import("../security/policy.zig").MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    provider_registry.setSecretStore(&secrets);
    try provider_registry.register(.{
        .id = "mock_openai_attempt_budget_runtime",
        .label = "Mock OpenAI Attempt Budget",
        .endpoint = "mock://openai/chat_retry_once",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
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
    defer output.deinit();
    var orchestrator = ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var runtime = AgentRuntime.init(std.testing.allocator, &provider_registry, &memory, &session_store, &output, &orchestrator);

    try std.testing.expectError(error.ProviderAttemptBudgetExceeded, runtime.run(.{
        .session_id = "sess_attempt_budget_exhausted",
        .prompt = "hello",
        .provider_id = "mock_openai_attempt_budget_runtime",
        .provider_retry_budget = 1,
        .provider_attempt_budget = 0,
    }));

    const events = session_store.find("sess_attempt_budget_exhausted").?.events.items;
    try std.testing.expect(std.mem.indexOf(u8, events[events.len - 1].payload_json, "PROVIDER_ATTEMPT_BUDGET_EXCEEDED") != null);
}

test "agent runtime enforces tool budget and risk confirmation" {
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
    defer output.deinit();
    var orchestrator = ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var runtime = AgentRuntime.init(std.testing.allocator, &provider_registry, &memory, &session_store, &output, &orchestrator);

    try std.testing.expectError(error.ToolBudgetExceeded, runtime.run(.{
        .session_id = "sess_tool_budget",
        .prompt = "hello",
        .provider_id = "provider_unused",
        .tool_id = "echo",
        .tool_input_json = "{\"message\":\"hello\"}",
        .tool_call_budget = 0,
    }));

    try std.testing.expectError(error.ToolRiskConfirmationRequired, runtime.run(.{
        .session_id = "sess_tool_risk",
        .prompt = "hello",
        .provider_id = "provider_unused",
        .tool_id = "shell",
        .tool_input_json = "{\"command\":\"echo hello\"}",
        .authority = .admin,
    }));
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

fn hasEventPayload(events: []const session_state.SessionEvent, kind: []const u8, needle: []const u8) bool {
    for (events) |event| {
        if (!std.mem.eql(u8, event.kind, kind)) continue;
        if (std.mem.indexOf(u8, event.payload_json, needle) != null) return true;
    }
    return false;
}
