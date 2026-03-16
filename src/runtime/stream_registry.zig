const std = @import("std");
const framework = @import("framework");
const agent_runtime = @import("../domain/agent_runtime.zig");
const stream_output = @import("../domain/stream_output.zig");

pub const AgentRuntime = agent_runtime.AgentRuntime;
pub const StreamOutput = stream_output.StreamOutput;

pub const ExecutionRequest = struct {
    request_id: []const u8,
    session_id: []const u8,
    prompt: []const u8,
    provider_id: []const u8,
    tool_id: ?[]const u8 = null,
    tool_input_json: ?[]const u8 = null,
    authority: framework.Authority = .operator,
};

pub const ExecutionEvent = struct {
    seq: u64,
    kind: []u8,
    payload_json: []u8,

    pub fn clone(self: ExecutionEvent, allocator: std.mem.Allocator) anyerror!ExecutionEvent {
        return .{
            .seq = self.seq,
            .kind = try allocator.dupe(u8, self.kind),
            .payload_json = try allocator.dupe(u8, self.payload_json),
        };
    }

    pub fn deinit(self: *ExecutionEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.payload_json);
    }
};

pub const ExecutionTerminal = struct {
    completed: bool,
    close_code: u16,
    close_reason: ?[]const u8,
};

pub const StreamExecution = struct {
    allocator: std.mem.Allocator,
    registry: *StreamRegistry,
    id: []u8,
    request_id: []u8,
    session_id: []u8,
    prompt: []u8,
    provider_id: []u8,
    tool_id: ?[]u8 = null,
    tool_input_json: ?[]u8 = null,
    authority: framework.Authority,
    created_at_ms: i64,
    completed_at_ms: ?i64 = null,
    events: std.ArrayListUnmanaged(ExecutionEvent) = .empty,
    next_seq: u64 = 1,
    cancel_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    completed: bool = false,
    close_code: u16 = 1000,
    close_reason: ?[]u8 = null,
    worker: ?std.Thread = null,
    mutex: std.Thread.Mutex = .{},

    const Self = @This();

    fn init(allocator: std.mem.Allocator, registry: *StreamRegistry, id: []const u8, request: ExecutionRequest) anyerror!*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .registry = registry,
            .id = try allocator.dupe(u8, id),
            .request_id = try allocator.dupe(u8, request.request_id),
            .session_id = try allocator.dupe(u8, request.session_id),
            .prompt = try allocator.dupe(u8, request.prompt),
            .provider_id = try allocator.dupe(u8, request.provider_id),
            .tool_id = if (request.tool_id) |tool_id| try allocator.dupe(u8, tool_id) else null,
            .tool_input_json = if (request.tool_input_json) |tool_input_json| try allocator.dupe(u8, tool_input_json) else null,
            .authority = request.authority,
            .created_at_ms = std.time.milliTimestamp(),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.cancel_requested.store(true, .release);
        if (self.worker) |worker| worker.join();
        for (self.events.items) |*event| event.deinit(self.allocator);
        self.events.deinit(self.allocator);
        if (self.close_reason) |close_reason| self.allocator.free(close_reason);
        self.allocator.free(self.id);
        self.allocator.free(self.request_id);
        self.allocator.free(self.session_id);
        self.allocator.free(self.prompt);
        self.allocator.free(self.provider_id);
        if (self.tool_id) |tool_id| self.allocator.free(tool_id);
        if (self.tool_input_json) |tool_input_json| self.allocator.free(tool_input_json);
        self.allocator.destroy(self);
    }

    pub fn requestCancel(self: *Self) void {
        self.cancel_requested.store(true, .release);
    }

    pub fn latestSeq(self: *Self) u64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return if (self.events.items.len == 0) 0 else self.events.items[self.events.items.len - 1].seq;
    }

    pub fn terminalSnapshot(self: *Self) ExecutionTerminal {
        self.mutex.lock();
        defer self.mutex.unlock();
        return .{
            .completed = self.completed,
            .close_code = self.close_code,
            .close_reason = self.close_reason,
        };
    }

    pub fn snapshotAfter(self: *Self, allocator: std.mem.Allocator, after_seq: u64) anyerror![]ExecutionEvent {
        self.mutex.lock();
        defer self.mutex.unlock();

        var count: usize = 0;
        for (self.events.items) |event| {
            if (event.seq > after_seq) count += 1;
        }

        const cloned = try allocator.alloc(ExecutionEvent, count);
        errdefer allocator.free(cloned);

        var index: usize = 0;
        for (self.events.items) |event| {
            if (event.seq <= after_seq) continue;
            cloned[index] = try event.clone(allocator);
            index += 1;
        }
        return cloned;
    }

    fn projector(self: *Self) stream_output.Projector {
        return .{
            .ptr = @ptrCast(self),
            .on_event = onProjectedEvent,
        };
    }

    fn onProjectedEvent(
        ptr: *anyopaque,
        _: u64,
        execution_id: ?[]const u8,
        session_id: []const u8,
        kind: []const u8,
        payload_json: []const u8,
    ) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.cancel_requested.load(.acquire)) {
            return error.StreamCancelled;
        }
        const actual_execution_id = execution_id orelse return;
        if (!std.mem.eql(u8, actual_execution_id, self.id)) return;
        if (!std.mem.eql(u8, session_id, self.session_id)) return;
        try self.appendEvent(kind, payload_json);
    }

    fn appendEvent(self: *Self, kind: []const u8, payload_json: []const u8) anyerror!void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.events.append(self.allocator, .{
            .seq = self.next_seq,
            .kind = try self.allocator.dupe(u8, kind),
            .payload_json = try self.allocator.dupe(u8, payload_json),
        });
        self.next_seq += 1;
    }

    fn markCompleted(self: *Self, close_code: u16, close_reason: []const u8) anyerror!void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.completed = true;
        self.completed_at_ms = std.time.milliTimestamp();
        self.close_code = close_code;
        if (self.close_reason) |current| self.allocator.free(current);
        self.close_reason = try self.allocator.dupe(u8, close_reason);
    }

    fn appendResultAndDone(self: *Self, result: *const agent_runtime.AgentStreamResult) anyerror!void {
        const result_json = try buildResultJson(self.allocator, result);
        defer self.allocator.free(result_json);
        try self.appendEvent("result", result_json);

        const done_json = try buildDoneJson(self.allocator, true, null, "completed", self.latestSeq() + 1, estimateBytes(self));
        defer self.allocator.free(done_json);
        try self.appendEvent("done", done_json);
        try self.markCompleted(1000, "completed");
    }

    fn appendFailureAndDone(self: *Self, err: anyerror) anyerror!void {
        const code, const reason, const close_code, const close_reason = mapTerminalError(self, err);
        const error_json = try buildErrorJson(self.allocator, self.request_id, code);
        defer self.allocator.free(error_json);
        try self.appendEvent("error", error_json);

        const done_json = try buildDoneJson(self.allocator, false, code, reason, self.latestSeq() + 1, estimateBytes(self));
        defer self.allocator.free(done_json);
        try self.appendEvent("done", done_json);
        try self.markCompleted(close_code, close_reason);
    }

    fn estimateBytes(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        var total: usize = 0;
        for (self.events.items) |event| {
            total += event.kind.len + event.payload_json.len;
        }
        return total;
    }
};

pub const StreamRegistry = struct {
    allocator: std.mem.Allocator,
    agent_runtime: *AgentRuntime,
    stream_output: *StreamOutput,
    executions: std.ArrayListUnmanaged(*StreamExecution) = .empty,
    next_id: u64 = 1,
    mutex: std.Thread.Mutex = .{},

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, agent_runtime_ref: *AgentRuntime, stream_output_ref: *StreamOutput) Self {
        return .{
            .allocator = allocator,
            .agent_runtime = agent_runtime_ref,
            .stream_output = stream_output_ref,
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        var executions = self.executions;
        self.executions = .empty;
        self.mutex.unlock();

        for (executions.items) |execution| execution.deinit();
        executions.deinit(self.allocator);
    }

    pub fn startExecution(self: *Self, request: ExecutionRequest) anyerror!*StreamExecution {
        self.mutex.lock();
        defer self.mutex.unlock();

        const id = try std.fmt.allocPrint(self.allocator, "stream_exec_{d}", .{self.next_id});
        defer self.allocator.free(id);
        self.next_id += 1;

        const execution = try StreamExecution.init(self.allocator, self, id, request);
        errdefer execution.deinit();

        try self.executions.append(self.allocator, execution);
        execution.worker = try std.Thread.spawn(.{}, executionWorkerMain, .{execution});
        return execution;
    }

    pub fn findExecution(self: *Self, execution_id: []const u8) ?*StreamExecution {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.executions.items) |execution| {
            if (std.mem.eql(u8, execution.id, execution_id)) return execution;
        }
        return null;
    }

    /// 查找指定 session 的正在运行的执行（未 terminal）
    /// 用于 resume 恢复，避免重复执行
    pub fn findRunningBySession(self: *Self, session_id: []const u8) ?*StreamExecution {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.executions.items) |execution| {
            if (!execution.completed and std.mem.eql(u8, execution.session_id, session_id)) {
                return execution;
            }
        }
        return null;
    }
};

fn executionWorkerMain(execution: *StreamExecution) void {
    var guard = execution.registry.stream_output.beginProjection(execution.projector()) catch |err| {
        execution.appendFailureAndDone(err) catch {};
        return;
    };
    defer guard.deinit();

    var result = execution.registry.agent_runtime.runStream(.{
        .session_id = execution.session_id,
        .prompt = execution.prompt,
        .provider_id = execution.provider_id,
        .tool_id = execution.tool_id,
        .tool_input_json = execution.tool_input_json,
        .stream_execution_id = execution.id,
        .cancel_requested = &execution.cancel_requested,
        .authority = execution.authority,
    }) catch |err| {
        execution.appendFailureAndDone(err) catch {};
        return;
    };
    defer result.deinit(execution.allocator);

    execution.appendResultAndDone(&result) catch |err| {
        execution.appendFailureAndDone(err) catch {};
    };
}

fn mapTerminalError(execution: *StreamExecution, err: anyerror) struct { []const u8, []const u8, u16, []const u8 } {
    _ = execution;
    return switch (err) {
        error.StreamCancelled => .{ "StreamCancelled", "client_cancel", 1000, "client_cancel" },
        error.StreamBackpressureExceeded => .{ "StreamBackpressureExceeded", "backpressure", 1008, "backpressure" },
        error.StreamClientDisconnected => .{ "StreamClientDisconnected", "client_disconnect", 1001, "client_disconnect" },
        else => .{ @errorName(err), "error", 1011, @errorName(err) },
    };
}

fn buildResultJson(allocator: std.mem.Allocator, result: *const agent_runtime.AgentStreamResult) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);
    try writer.writeByte('{');
    try appendJsonStringField(writer, "sessionId", result.session_id, true);
    try appendJsonStringField(writer, "providerId", result.provider_id, false);
    try appendJsonStringField(writer, "model", result.model, false);
    try appendJsonUnsignedField(writer, "toolRounds", result.tool_rounds, false);
    try appendJsonUnsignedField(writer, "memoryEntriesUsed", result.memory_entries_used, false);
    try appendJsonUnsignedField(writer, "providerLatencyMs", result.provider_latency_ms, false);
    try appendJsonStringField(writer, "finalResponseText", result.final_response_text, false);
    try writer.writeByte('}');
    return allocator.dupe(u8, buf.items);
}

fn buildDoneJson(
    allocator: std.mem.Allocator,
    ok: bool,
    terminal_code: ?[]const u8,
    terminal_reason: ?[]const u8,
    emitted_events: u64,
    emitted_bytes: usize,
) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);
    try writer.writeByte('{');
    try appendJsonBoolField(writer, "ok", ok, true);
    try appendOptionalJsonStringField(writer, "terminalCode", terminal_code, false);
    try appendOptionalJsonStringField(writer, "terminalReason", terminal_reason, false);
    try appendJsonUnsignedField(writer, "emittedEvents", emitted_events, false);
    try appendJsonUnsignedField(writer, "emittedBytes", emitted_bytes, false);
    try writer.writeByte('}');
    return allocator.dupe(u8, buf.items);
}

fn buildErrorJson(allocator: std.mem.Allocator, request_id: []const u8, code: []const u8) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);
    try writer.writeByte('{');
    try appendJsonStringField(writer, "requestId", request_id, true);
    try appendJsonStringField(writer, "code", code, false);
    try writer.writeByte('}');
    return allocator.dupe(u8, buf.items);
}

fn appendJsonStringField(writer: anytype, key: []const u8, value: []const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writeJsonString(writer, value);
}

fn appendJsonUnsignedField(writer: anytype, key: []const u8, value: anytype, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.print("{d}", .{value});
}

fn appendJsonBoolField(writer: anytype, key: []const u8, value: bool, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.writeAll(if (value) "true" else "false");
}

fn appendOptionalJsonStringField(writer: anytype, key: []const u8, value: ?[]const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    if (value) |actual| {
        try writeJsonString(writer, actual);
        return;
    }
    try writer.writeAll("null");
}

fn writeJsonString(writer: anytype, value: []const u8) anyerror!void {
    try writer.writeByte('"');
    for (value) |ch| {
        switch (ch) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(ch),
        }
    }
    try writer.writeByte('"');
}

test "stream registry requestCancel propagates into provider execution" {
    var provider_registry = agent_runtime.ProviderRegistry.init(std.testing.allocator);
    defer provider_registry.deinit();
    var secrets = @import("../security/policy.zig").MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    provider_registry.setSecretStore(&secrets);
    try provider_registry.register(.{
        .id = "mock_openai_cancel_wait_registry",
        .label = "Mock OpenAI Cancel Wait",
        .endpoint = "mock://openai/chat_cancel_wait",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    });

    var tool_registry = @import("../tools/root.zig").ToolRegistry.init(std.testing.allocator);
    defer tool_registry.deinit();
    try tool_registry.registerBuiltins();

    var memory = agent_runtime.MemoryRuntime.init(std.testing.allocator);
    defer memory.deinit();
    var session_store = agent_runtime.SessionStore.init(std.testing.allocator);
    defer session_store.deinit();
    var output = StreamOutput.init(std.testing.allocator, &session_store, null, null);
    defer output.deinit();
    var orchestrator = @import("../domain/tool_orchestrator.zig").ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var runtime = AgentRuntime.init(std.testing.allocator, &provider_registry, &memory, &session_store, &output, &orchestrator);
    var registry = StreamRegistry.init(std.testing.allocator, &runtime, &output);
    defer registry.deinit();

    const execution = try registry.startExecution(.{
        .request_id = "req_stream_cancel_provider",
        .session_id = "sess_stream_cancel_provider",
        .prompt = "hello",
        .provider_id = "mock_openai_cancel_wait_registry",
        .authority = .admin,
    });

    std.Thread.sleep(20 * std.time.ns_per_ms);
    execution.requestCancel();
    execution.requestCancel();

    var attempts: usize = 0;
    while (attempts < 100 and !execution.terminalSnapshot().completed) : (attempts += 1) {
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }

    const terminal = execution.terminalSnapshot();
    try std.testing.expect(terminal.completed);
    try std.testing.expectEqual(@as(u16, 1000), terminal.close_code);
    try std.testing.expectEqualStrings("client_cancel", terminal.close_reason.?);

    const events = try execution.snapshotAfter(std.testing.allocator, 0);
    defer {
        for (events) |*event| event.deinit(std.testing.allocator);
        std.testing.allocator.free(events);
    }
    try std.testing.expect(events.len >= 2);
    try std.testing.expect(std.mem.indexOf(u8, events[events.len - 2].payload_json, "StreamCancelled") != null);
}

test "stream registry requestCancel propagates into tool execution" {
    var provider_registry = agent_runtime.ProviderRegistry.init(std.testing.allocator);
    defer provider_registry.deinit();

    var tool_registry = @import("../tools/root.zig").ToolRegistry.init(std.testing.allocator);
    defer tool_registry.deinit();
    try tool_registry.registerBuiltins();

    var memory = agent_runtime.MemoryRuntime.init(std.testing.allocator);
    defer memory.deinit();
    var session_store = agent_runtime.SessionStore.init(std.testing.allocator);
    defer session_store.deinit();
    var output = StreamOutput.init(std.testing.allocator, &session_store, null, null);
    defer output.deinit();
    var orchestrator = @import("../domain/tool_orchestrator.zig").ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var runtime = AgentRuntime.init(std.testing.allocator, &provider_registry, &memory, &session_store, &output, &orchestrator);
    var registry = StreamRegistry.init(std.testing.allocator, &runtime, &output);
    defer registry.deinit();

    const execution = try registry.startExecution(.{
        .request_id = "req_stream_cancel_tool",
        .session_id = "sess_stream_cancel_tool",
        .prompt = "hello",
        .provider_id = "provider_unused",
        .tool_id = "http_request",
        .tool_input_json = "{\"url\":\"mock://http/cancel_wait\"}",
        .authority = .operator,
    });

    std.Thread.sleep(20 * std.time.ns_per_ms);
    execution.requestCancel();
    execution.requestCancel();

    var attempts: usize = 0;
    while (attempts < 100 and !execution.terminalSnapshot().completed) : (attempts += 1) {
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }

    const terminal = execution.terminalSnapshot();
    try std.testing.expect(terminal.completed);
    try std.testing.expectEqualStrings("client_cancel", terminal.close_reason.?);
}
