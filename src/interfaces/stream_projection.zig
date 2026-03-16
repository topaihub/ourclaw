const std = @import("std");
const framework = @import("framework");
const runtime = @import("../runtime/app_context.zig");
const stream_registry = @import("../runtime/stream_registry.zig");
const sink_model = @import("stream_sink.zig");
const stream_output = @import("../domain/stream_output.zig");
const stream_websocket = @import("stream_websocket.zig");

pub const ByteSink = sink_model.ByteSink;

pub const ProjectionPolicy = struct {
    max_event_bytes: usize = 64 * 1024,
    max_total_bytes: usize = 512 * 1024,
    cancel_after_events: usize = 0,
    text_delta_coalesce_event_limit: usize = 4,
    text_delta_coalesce_byte_limit: usize = 128,
    text_delta_throttle_window_ms: u64 = 120,
};

pub const StreamRequest = struct {
    request_id: []const u8,
    params: []const framework.ValidationField,
    authority: framework.Authority = .operator,
    policy: ProjectionPolicy = .{},
    cancel_requested: ?*const std.atomic.Value(bool) = null,
    client_closed: ?*const std.atomic.Value(bool) = null,
    websocket_acked_seq: ?*const std.atomic.Value(u64) = null,
    websocket_pause_requested: ?*std.atomic.Value(bool) = null,
    websocket_resume_requested: ?*std.atomic.Value(bool) = null,
    websocket_resume_from_seq: ?*const std.atomic.Value(u64) = null,
};

const TerminalReason = enum {
    none,
    cancel_after_events,
    client_cancel,
    max_event_bytes,
    max_total_bytes,
    client_disconnect,

    fn errorCode(self: TerminalReason) ?[]const u8 {
        return switch (self) {
            .none => null,
            .cancel_after_events => "StreamCancelled",
            .client_cancel => "StreamCancelled",
            .max_event_bytes, .max_total_bytes => "StreamBackpressureExceeded",
            .client_disconnect => "StreamClientDisconnected",
        };
    }

    fn label(self: TerminalReason) ?[]const u8 {
        return switch (self) {
            .none => null,
            .cancel_after_events => "cancel_after_events",
            .client_cancel => "client_cancel",
            .max_event_bytes => "max_event_bytes",
            .max_total_bytes => "max_total_bytes",
            .client_disconnect => "client_disconnect",
        };
    }
};

const ProjectionControl = struct {
    terminal_reason: TerminalReason = .none,

    fn note(self: *ProjectionControl, reason: TerminalReason) void {
        if (self.terminal_reason == .none) {
            self.terminal_reason = reason;
        }
    }

    fn errorCode(self: *const ProjectionControl) ?[]const u8 {
        return self.terminal_reason.errorCode();
    }

    fn reasonLabel(self: *const ProjectionControl) ?[]const u8 {
        return self.terminal_reason.label();
    }

    fn isClientDisconnect(self: *const ProjectionControl) bool {
        return self.terminal_reason == .client_disconnect;
    }
};

const ParsedRequest = struct {
    request_id: []u8,
    session_id: []u8,
    prompt: []u8,
    provider_id: []u8,
    tool_id: ?[]u8 = null,
    tool_input_json: ?[]u8 = null,
    resume_cursor: ?ResumeCursor = null,
    authority: framework.Authority,
    policy: ProjectionPolicy,
    cancel_requested: ?*const std.atomic.Value(bool),
    client_closed: ?*const std.atomic.Value(bool),

    fn deinit(self: *ParsedRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.request_id);
        allocator.free(self.session_id);
        allocator.free(self.prompt);
        allocator.free(self.provider_id);
        if (self.tool_id) |tool_id| allocator.free(tool_id);
        if (self.tool_input_json) |tool_input_json| allocator.free(tool_input_json);
        if (self.resume_cursor) |*cursor| cursor.deinit(allocator);
    }
};

const ProjectionState = struct {
    policy: ProjectionPolicy,
    control: *ProjectionControl,
    cancel_requested: ?*const std.atomic.Value(bool),
    client_closed: ?*const std.atomic.Value(bool),
    emitted_events: usize = 0,
    emitted_bytes: usize = 0,

    fn prepareWrite(self: *ProjectionState, byte_count: usize) anyerror!void {
        if (self.client_closed) |signal| {
            if (signal.load(.acquire)) {
                self.control.note(.client_disconnect);
                return error.StreamClientDisconnected;
            }
        }
        if (self.cancel_requested) |signal| {
            if (signal.load(.acquire)) {
                self.control.note(.client_cancel);
                return error.StreamCancelled;
            }
        }
        if (self.policy.cancel_after_events > 0 and self.emitted_events >= self.policy.cancel_after_events) {
            self.control.note(.cancel_after_events);
            return error.StreamCancelled;
        }
        if (self.policy.max_event_bytes > 0 and byte_count > self.policy.max_event_bytes) {
            self.control.note(.max_event_bytes);
            return error.StreamBackpressureExceeded;
        }
        if (self.policy.max_total_bytes > 0 and self.emitted_bytes + byte_count > self.policy.max_total_bytes) {
            self.control.note(.max_total_bytes);
            return error.StreamBackpressureExceeded;
        }
    }

    fn commitWrite(self: *ProjectionState, byte_count: usize) void {
        self.emitted_events += 1;
        self.emitted_bytes += byte_count;
    }

    fn mapSinkError(self: *ProjectionState, err: anyerror) anyerror {
        if (isDisconnectError(err)) {
            self.control.note(.client_disconnect);
            return error.StreamClientDisconnected;
        }
        return err;
    }
};

const EXECUTION_POLL_INTERVAL_MS: u64 = 20;

const ResumeCursor = union(enum) {
    legacy_seq: u64,
    execution: ExecutionResumeCursor,

    const ExecutionResumeCursor = struct {
        execution_id: []u8,
        after_seq: u64,
    };

    fn deinit(self: *ResumeCursor, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .legacy_seq => {},
            .execution => |cursor| allocator.free(cursor.execution_id),
        }
    }
};

const TextDeltaBatch = struct {
    allocator: std.mem.Allocator,
    coalesce_event_limit: usize,
    coalesce_byte_limit: usize,
    throttle_window_ms: u64,
    buffer: std.ArrayListUnmanaged(u8) = .empty,
    stream_source: ?[]u8 = null,
    latest_seq: u64 = 0,
    count: usize = 0,
    started_at_ms: ?i64 = null,

    fn init(allocator: std.mem.Allocator, policy: ProjectionPolicy) TextDeltaBatch {
        return .{
            .allocator = allocator,
            .coalesce_event_limit = policy.text_delta_coalesce_event_limit,
            .coalesce_byte_limit = policy.text_delta_coalesce_byte_limit,
            .throttle_window_ms = policy.text_delta_throttle_window_ms,
        };
    }

    fn deinit(self: *TextDeltaBatch) void {
        self.buffer.deinit(self.allocator);
        if (self.stream_source) |value| self.allocator.free(value);
    }

    fn hasPending(self: *const TextDeltaBatch) bool {
        return self.count > 0;
    }

    fn shouldFlushBeforeAppend(self: *const TextDeltaBatch, append_len: usize, stream_source: ?[]const u8) bool {
        if (!self.hasPending()) return false;
        if (!sameOptionalString(self.stream_source, stream_source)) return true;
        if (self.coalesce_event_limit > 0 and self.count >= self.coalesce_event_limit) return true;
        if (self.coalesce_byte_limit > 0 and self.buffer.items.len + append_len > self.coalesce_byte_limit) return true;
        return false;
    }

    fn append(self: *TextDeltaBatch, seq: u64, text: []const u8, stream_source: ?[]const u8) anyerror!void {
        if (self.count == 0) {
            self.started_at_ms = std.time.milliTimestamp();
            if (stream_source) |value| {
                self.stream_source = try self.allocator.dupe(u8, value);
            }
        }
        try self.buffer.appendSlice(self.allocator, text);
        self.latest_seq = seq;
        self.count += 1;
    }

    fn shouldFlushByWindow(self: *const TextDeltaBatch, now_ms: i64) bool {
        if (!self.hasPending()) return false;
        if (self.throttle_window_ms == 0) return true;
        const started_at_ms = self.started_at_ms orelse return false;
        if (now_ms <= started_at_ms) return false;
        const elapsed_ms: u64 = @intCast(now_ms - started_at_ms);
        return elapsed_ms >= self.throttle_window_ms;
    }

    fn reset(self: *TextDeltaBatch) void {
        self.buffer.clearRetainingCapacity();
        if (self.stream_source) |value| self.allocator.free(value);
        self.stream_source = null;
        self.latest_seq = 0;
        self.count = 0;
        self.started_at_ms = null;
    }
};

const SseProjector = struct {
    allocator: std.mem.Allocator,
    sink: ByteSink,
    state: *ProjectionState,
    pending_text: TextDeltaBatch,

    fn init(allocator: std.mem.Allocator, sink: ByteSink, state: *ProjectionState) SseProjector {
        return .{
            .allocator = allocator,
            .sink = sink,
            .state = state,
            .pending_text = TextDeltaBatch.init(allocator, state.policy),
        };
    }

    fn deinit(self: *SseProjector) void {
        self.pending_text.deinit();
    }

    fn asProjector(self: *SseProjector) stream_output.Projector {
        return .{
            .ptr = @ptrCast(self),
            .on_event = onEvent,
        };
    }

    fn onEvent(ptr: *anyopaque, seq: u64, _: ?[]const u8, _: []const u8, kind: []const u8, payload_json: []const u8) anyerror!void {
        const self: *SseProjector = @ptrCast(@alignCast(ptr));
        if (try self.tryCoalesceTextDelta(seq, kind, payload_json)) return;
        try self.flushPendingText();
        try writeControlledSseEvent(self.allocator, self.sink, self.state, null, kind, seq, payload_json);
    }

    fn tryCoalesceTextDelta(self: *SseProjector, seq: u64, kind: []const u8, payload_json: []const u8) anyerror!bool {
        if (!std.mem.eql(u8, kind, "text.delta")) return false;
        const text = extractTextDelta(payload_json) orelse return false;
        const stream_source = extractTextDeltaStreamSource(payload_json);
        if (self.pending_text.shouldFlushBeforeAppend(text.len, stream_source)) {
            try self.flushPendingText();
        }
        try self.pending_text.append(seq, text, stream_source);
        return true;
    }

    fn flushPendingText(self: *SseProjector) anyerror!void {
        if (!self.pending_text.hasPending()) return;
        const payload = try buildTextDeltaJson(self.allocator, self.pending_text.buffer.items, self.pending_text.stream_source);
        defer self.allocator.free(payload);
        try writeControlledSseEvent(self.allocator, self.sink, self.state, null, "text.delta", self.pending_text.latest_seq, payload);
        self.pending_text.reset();
    }
};

const BridgeProjector = struct {
    allocator: std.mem.Allocator,
    sink: ByteSink,
    state: *ProjectionState,
    pending_text: TextDeltaBatch,

    fn init(allocator: std.mem.Allocator, sink: ByteSink, state: *ProjectionState) BridgeProjector {
        return .{
            .allocator = allocator,
            .sink = sink,
            .state = state,
            .pending_text = TextDeltaBatch.init(allocator, state.policy),
        };
    }

    fn deinit(self: *BridgeProjector) void {
        self.pending_text.deinit();
    }

    fn asProjector(self: *BridgeProjector) stream_output.Projector {
        return .{
            .ptr = @ptrCast(self),
            .on_event = onEvent,
        };
    }

    fn onEvent(ptr: *anyopaque, seq: u64, _: ?[]const u8, _: []const u8, kind: []const u8, payload_json: []const u8) anyerror!void {
        const self: *BridgeProjector = @ptrCast(@alignCast(ptr));
        if (try self.tryCoalesceTextDelta(seq, kind, payload_json)) return;
        try self.flushPendingText();
        try writeControlledJsonLineEvent(self.allocator, self.sink, self.state, kind, seq, payload_json);
    }

    fn tryCoalesceTextDelta(self: *BridgeProjector, seq: u64, kind: []const u8, payload_json: []const u8) anyerror!bool {
        if (!std.mem.eql(u8, kind, "text.delta")) return false;
        const text = extractTextDelta(payload_json) orelse return false;
        const stream_source = extractTextDeltaStreamSource(payload_json);
        if (self.pending_text.shouldFlushBeforeAppend(text.len, stream_source)) {
            try self.flushPendingText();
        }
        try self.pending_text.append(seq, text, stream_source);
        return true;
    }

    fn flushPendingText(self: *BridgeProjector) anyerror!void {
        if (!self.pending_text.hasPending()) return;
        const payload = try buildTextDeltaJson(self.allocator, self.pending_text.buffer.items, self.pending_text.stream_source);
        defer self.allocator.free(payload);
        try writeControlledJsonLineEvent(self.allocator, self.sink, self.state, "text.delta", self.pending_text.latest_seq, payload);
        self.pending_text.reset();
    }
};

const WebSocketProjector = struct {
    allocator: std.mem.Allocator,
    sink: ByteSink,
    state: *ProjectionState,
    pending_text: TextDeltaBatch,

    fn init(allocator: std.mem.Allocator, sink: ByteSink, state: *ProjectionState) WebSocketProjector {
        return .{
            .allocator = allocator,
            .sink = sink,
            .state = state,
            .pending_text = TextDeltaBatch.init(allocator, state.policy),
        };
    }

    fn deinit(self: *WebSocketProjector) void {
        self.pending_text.deinit();
    }

    fn asProjector(self: *WebSocketProjector) stream_output.Projector {
        return .{
            .ptr = @ptrCast(self),
            .on_event = onEvent,
        };
    }

    fn onEvent(ptr: *anyopaque, seq: u64, _: ?[]const u8, _: []const u8, kind: []const u8, payload_json: []const u8) anyerror!void {
        const self: *WebSocketProjector = @ptrCast(@alignCast(ptr));
        if (try self.tryCoalesceTextDelta(seq, kind, payload_json)) return;
        try self.flushPendingText();
        try writeControlledWebSocketEvent(self.allocator, self.sink, self.state, kind, seq, payload_json);
    }

    fn tryCoalesceTextDelta(self: *WebSocketProjector, seq: u64, kind: []const u8, payload_json: []const u8) anyerror!bool {
        if (!std.mem.eql(u8, kind, "text.delta")) return false;
        const text = extractTextDelta(payload_json) orelse return false;
        const stream_source = extractTextDeltaStreamSource(payload_json);
        if (self.pending_text.shouldFlushBeforeAppend(text.len, stream_source)) {
            try self.flushPendingText();
        }
        try self.pending_text.append(seq, text, stream_source);
        return true;
    }

    fn flushPendingText(self: *WebSocketProjector) anyerror!void {
        if (!self.pending_text.hasPending()) return;
        const payload = try buildTextDeltaJson(self.allocator, self.pending_text.buffer.items, self.pending_text.stream_source);
        defer self.allocator.free(payload);
        try writeControlledWebSocketEvent(self.allocator, self.sink, self.state, "text.delta", self.pending_text.latest_seq, payload);
        self.pending_text.reset();
    }
};

/// 查找指定 session 的正在运行的执行，用于 resume 恢复
/// 返回 null 表示没有正在运行的执行（可能已 terminal 或不存在）
fn findRunningExecutionForSession(app: *runtime.AppContext, session_id: []const u8) ?*stream_registry.StreamExecution {
    return app.stream_registry.findRunningBySession(session_id);
}

pub fn writeSseAgentStream(allocator: std.mem.Allocator, app: *runtime.AppContext, request: StreamRequest, sink: ByteSink) anyerror!void {
    try sink.writeAll(": ourclaw agent.stream sse\n");
    try sink.writeAll("retry: 1000\n\n");

    var parsed = parseRequest(allocator, request) catch |err| {
        try writeSseProjectionFailure(allocator, sink, request.request_id, err);
        return;
    };
    defer parsed.deinit(allocator);

    var control = ProjectionControl{};
    var state = ProjectionState{
        .policy = parsed.policy,
        .control = &control,
        .cancel_requested = parsed.cancel_requested,
        .client_closed = parsed.client_closed,
    };

    switch (parsed.resume_cursor orelse ResumeCursor{ .legacy_seq = 0 }) {
        .legacy_seq => |last_event_id| {
            const use_legacy_replay = parsed.resume_cursor != null and last_event_id > 0;

            // 尝试查找同一 session 的 running 执行，避免重复执行
            const existing_execution = if (use_legacy_replay)
                findRunningExecutionForSession(app, parsed.session_id)
            else
                null;

            if (existing_execution) |execution| {
                // 找到正在运行的执行，resume 它
                const meta_json = try buildMetaJson(
                    allocator,
                    parsed.request_id,
                    execution.id,
                    parsed.session_id,
                    parsed.provider_id,
                    last_event_id,
                    "resume",
                );
                defer allocator.free(meta_json);
                writeControlledSseEvent(allocator, sink, &state, null, "meta", 0, meta_json) catch |err| {
                    try finishSseTerminalState(allocator, sink, parsed.request_id, &state, err);
                    return;
                };
                drainExecutionAsSse(allocator, sink, &state, execution, last_event_id) catch |err| {
                    try finishSseTerminalState(allocator, sink, parsed.request_id, &state, err);
                };
                return;
            }

            // 没有正在运行的执行，回放历史事件
            if (use_legacy_replay) {
                const meta_json = try buildMetaJson(
                    allocator,
                    parsed.request_id,
                    null,
                    parsed.session_id,
                    parsed.provider_id,
                    last_event_id,
                    "replay_only",
                );
                defer allocator.free(meta_json);
                writeControlledSseEvent(allocator, sink, &state, null, "meta", 0, meta_json) catch |err| {
                    try finishSseTerminalState(allocator, sink, parsed.request_id, &state, err);
                    return;
                };

                const replay = try replaySseSessionEventsAfterSeq(allocator, app, parsed.session_id, last_event_id, sink, &state);
                const done_json = try buildDoneJson(
                    allocator,
                    true,
                    null,
                    if (replay.reached_terminal_event) "reconnect_replay_completed" else "reconnect_replay_only",
                    state.emitted_events,
                    state.emitted_bytes,
                );
                defer allocator.free(done_json);
                try writeRawSseEvent(allocator, sink, "done", 0, done_json);
                return;
            }

            // 没有 last_event_id，启动新执行
            const resolved = try startLiveExecution(app, &parsed);
            defer releaseExecutionIfNeeded(resolved);

            const live_meta_json = try buildMetaJson(
                allocator,
                parsed.request_id,
                resolved.execution.id,
                parsed.session_id,
                parsed.provider_id,
                null,
                "continue",
            );
            defer allocator.free(live_meta_json);
            try writeControlledSseEvent(allocator, sink, &state, null, "meta", 0, live_meta_json);
            drainExecutionAsSse(allocator, sink, &state, resolved.execution, 0) catch |err| {
                try finishSseTerminalState(allocator, sink, parsed.request_id, &state, err);
            };
            return;
        },
        .execution => |cursor| {
            const execution = app.stream_registry.findExecution(cursor.execution_id) orelse {
                try writeSseProjectionFailure(allocator, sink, parsed.request_id, error.StreamExecutionNotFound);
                return;
            };
            if (!std.mem.eql(u8, execution.session_id, parsed.session_id)) {
                try writeSseProjectionFailure(allocator, sink, parsed.request_id, error.StreamExecutionMismatch);
                return;
            }

            const meta_json = try buildMetaJson(
                allocator,
                parsed.request_id,
                execution.id,
                parsed.session_id,
                parsed.provider_id,
                cursor.after_seq,
                "resume",
            );
            defer allocator.free(meta_json);
            writeControlledSseEvent(allocator, sink, &state, null, "meta", 0, meta_json) catch |err| {
                try finishSseTerminalState(allocator, sink, parsed.request_id, &state, err);
                return;
            };
            drainExecutionAsSse(allocator, sink, &state, execution, cursor.after_seq) catch |err| {
                try finishSseTerminalState(allocator, sink, parsed.request_id, &state, err);
            };
            return;
        },
    }
}

pub fn writeBridgeAgentStream(allocator: std.mem.Allocator, app: *runtime.AppContext, request: StreamRequest, sink: ByteSink) anyerror!void {
    var parsed = parseRequest(allocator, request) catch |err| {
        try writeBridgeProjectionFailure(allocator, sink, request.request_id, err);
        return;
    };
    defer parsed.deinit(allocator);

    var control = ProjectionControl{};
    var state = ProjectionState{
        .policy = parsed.policy,
        .control = &control,
        .cancel_requested = parsed.cancel_requested,
        .client_closed = parsed.client_closed,
    };
    const has_resume_cursor = parsed.resume_cursor != null;

    switch (parsed.resume_cursor orelse ResumeCursor{ .legacy_seq = 0 }) {
        .legacy_seq => |last_event_id| {
            const use_legacy_replay = has_resume_cursor and last_event_id > 0;
            const existing_execution = findRunningExecutionForSession(app, parsed.session_id);

            if (existing_execution) |execution| {
                const meta_json = try buildMetaJson(
                    allocator,
                    parsed.request_id,
                    execution.id,
                    parsed.session_id,
                    parsed.provider_id,
                    if (use_legacy_replay) last_event_id else null,
                    if (use_legacy_replay) "resume" else "already_running_resume",
                );
                defer allocator.free(meta_json);
                writeControlledJsonLineEvent(allocator, sink, &state, "meta", 0, meta_json) catch |err| {
                    try finishBridgeTerminalState(allocator, sink, parsed.request_id, &state, err);
                    return;
                };
                drainExecutionAsBridge(allocator, sink, &state, execution, if (use_legacy_replay) last_event_id else 0) catch |err| {
                    try finishBridgeTerminalState(allocator, sink, parsed.request_id, &state, err);
                };
                return;
            }

            if (use_legacy_replay) {
                const meta_json = try buildMetaJson(
                    allocator,
                    parsed.request_id,
                    null,
                    parsed.session_id,
                    parsed.provider_id,
                    last_event_id,
                    "replay_only",
                );
                defer allocator.free(meta_json);
                writeControlledJsonLineEvent(allocator, sink, &state, "meta", 0, meta_json) catch |err| {
                    try finishBridgeTerminalState(allocator, sink, parsed.request_id, &state, err);
                    return;
                };

                const replay = try replayBridgeSessionEventsAfterSeq(allocator, app, parsed.session_id, last_event_id, sink, &state);
                const done_json = try buildDoneJson(
                    allocator,
                    true,
                    null,
                    if (replay.reached_terminal_event) "reconnect_replay_completed" else "reconnect_replay_only",
                    state.emitted_events,
                    state.emitted_bytes,
                );
                defer allocator.free(done_json);
                try writeRawJsonLineEvent(allocator, sink, "done", 0, done_json);
                return;
            }

            const resolved = try startLiveExecution(app, &parsed);
            defer releaseExecutionIfNeeded(resolved);

            const meta_json = try buildMetaJson(
                allocator,
                parsed.request_id,
                resolved.execution.id,
                parsed.session_id,
                parsed.provider_id,
                null,
                "continue",
            );
            defer allocator.free(meta_json);
            writeControlledJsonLineEvent(allocator, sink, &state, "meta", 0, meta_json) catch |err| {
                try finishBridgeTerminalState(allocator, sink, parsed.request_id, &state, err);
                return;
            };

            drainExecutionAsBridge(allocator, sink, &state, resolved.execution, 0) catch |err| {
                try finishBridgeTerminalState(allocator, sink, parsed.request_id, &state, err);
            };
            return;
        },
        .execution => |cursor| {
            const execution = app.stream_registry.findExecution(cursor.execution_id) orelse {
                try writeBridgeProjectionFailure(allocator, sink, parsed.request_id, error.StreamExecutionNotFound);
                return;
            };
            if (!std.mem.eql(u8, execution.session_id, parsed.session_id)) {
                try writeBridgeProjectionFailure(allocator, sink, parsed.request_id, error.StreamExecutionMismatch);
                return;
            }

            const meta_json = try buildMetaJson(
                allocator,
                parsed.request_id,
                execution.id,
                parsed.session_id,
                parsed.provider_id,
                cursor.after_seq,
                "resume",
            );
            defer allocator.free(meta_json);
            writeControlledJsonLineEvent(allocator, sink, &state, "meta", 0, meta_json) catch |err| {
                try finishBridgeTerminalState(allocator, sink, parsed.request_id, &state, err);
                return;
            };
            drainExecutionAsBridge(allocator, sink, &state, execution, cursor.after_seq) catch |err| {
                try finishBridgeTerminalState(allocator, sink, parsed.request_id, &state, err);
            };
            return;
        },
    }
}

pub fn writeWebSocketAgentStream(allocator: std.mem.Allocator, app: *runtime.AppContext, request: StreamRequest, sink: ByteSink) anyerror!void {
    var parsed = parseRequest(allocator, request) catch |err| {
        try writeWebSocketProjectionFailure(allocator, sink, request.request_id, err);
        try stream_websocket.writeCloseFrame(sink);
        return;
    };
    defer parsed.deinit(allocator);

    var control = ProjectionControl{};
    var state = ProjectionState{
        .policy = parsed.policy,
        .control = &control,
        .cancel_requested = parsed.cancel_requested,
        .client_closed = parsed.client_closed,
    };
    const has_resume_cursor = parsed.resume_cursor != null;

    switch (parsed.resume_cursor orelse ResumeCursor{ .legacy_seq = 0 }) {
        .legacy_seq => |last_event_id| {
            const use_legacy_replay = has_resume_cursor and last_event_id > 0;
            const existing_execution = findRunningExecutionForSession(app, parsed.session_id);

            if (existing_execution) |execution| {
                const meta_json = try buildMetaJson(
                    allocator,
                    parsed.request_id,
                    execution.id,
                    parsed.session_id,
                    parsed.provider_id,
                    if (use_legacy_replay) last_event_id else null,
                    "resume",
                );
                defer allocator.free(meta_json);
                writeControlledWebSocketEvent(allocator, sink, &state, "meta", 0, meta_json) catch |err| {
                    try finishWebSocketTerminalState(allocator, sink, parsed.request_id, &state, err);
                    try stream_websocket.writeCloseFrame(sink);
                    return;
                };
                drainExecutionAsWebSocket(allocator, sink, &state, execution, if (use_legacy_replay) last_event_id else 0, .{
                    .acked_seq = request.websocket_acked_seq,
                    .pause_requested = request.websocket_pause_requested,
                    .resume_requested = request.websocket_resume_requested,
                    .resume_from_seq = request.websocket_resume_from_seq,
                }) catch |err| {
                    try finishWebSocketTerminalState(allocator, sink, parsed.request_id, &state, err);
                };
                return;
            }

            if (use_legacy_replay) {
                const meta_json = try buildMetaJson(
                    allocator,
                    parsed.request_id,
                    null,
                    parsed.session_id,
                    parsed.provider_id,
                    last_event_id,
                    "replay_only",
                );
                defer allocator.free(meta_json);
                writeControlledWebSocketEvent(allocator, sink, &state, "meta", 0, meta_json) catch |err| {
                    try finishWebSocketTerminalState(allocator, sink, parsed.request_id, &state, err);
                    try stream_websocket.writeCloseFrame(sink);
                    return;
                };

                const replay = try replayWebSocketSessionEventsAfterSeq(allocator, app, parsed.session_id, last_event_id, sink, &state);
                const done_json = try buildDoneJson(
                    allocator,
                    true,
                    null,
                    if (replay.reached_terminal_event) "reconnect_replay_completed" else "reconnect_replay_only",
                    state.emitted_events,
                    state.emitted_bytes,
                );
                defer allocator.free(done_json);
                try writeRawWebSocketEvent(allocator, sink, "done", 0, done_json);
                try stream_websocket.writeCloseFrame(sink);
                return;
            }

            const resolved = try startLiveExecution(app, &parsed);
            defer releaseExecutionIfNeeded(resolved);

            const meta_json = try buildMetaJson(
                allocator,
                parsed.request_id,
                resolved.execution.id,
                parsed.session_id,
                parsed.provider_id,
                null,
                "continue",
            );
            defer allocator.free(meta_json);
            writeControlledWebSocketEvent(allocator, sink, &state, "meta", 0, meta_json) catch |err| {
                try finishWebSocketTerminalState(allocator, sink, parsed.request_id, &state, err);
                try stream_websocket.writeCloseFrame(sink);
                return;
            };
            drainExecutionAsWebSocket(allocator, sink, &state, resolved.execution, 0, .{
                .acked_seq = request.websocket_acked_seq,
                .pause_requested = request.websocket_pause_requested,
                .resume_requested = request.websocket_resume_requested,
                .resume_from_seq = request.websocket_resume_from_seq,
            }) catch |err| {
                try finishWebSocketTerminalState(allocator, sink, parsed.request_id, &state, err);
            };
            return;
        },
        .execution => |cursor| {
            const execution = app.stream_registry.findExecution(cursor.execution_id) orelse {
                try writeWebSocketProjectionFailure(allocator, sink, parsed.request_id, error.StreamExecutionNotFound);
                try stream_websocket.writeCloseFrame(sink);
                return;
            };
            if (!std.mem.eql(u8, execution.session_id, parsed.session_id)) {
                try writeWebSocketProjectionFailure(allocator, sink, parsed.request_id, error.StreamExecutionMismatch);
                try stream_websocket.writeCloseFrame(sink);
                return;
            }

            const meta_json = try buildMetaJson(
                allocator,
                parsed.request_id,
                execution.id,
                parsed.session_id,
                parsed.provider_id,
                cursor.after_seq,
                "resume",
            );
            defer allocator.free(meta_json);
            writeControlledWebSocketEvent(allocator, sink, &state, "meta", 0, meta_json) catch |err| {
                try finishWebSocketTerminalState(allocator, sink, parsed.request_id, &state, err);
                try stream_websocket.writeCloseFrame(sink);
                return;
            };
            drainExecutionAsWebSocket(allocator, sink, &state, execution, cursor.after_seq, .{
                .acked_seq = request.websocket_acked_seq,
                .pause_requested = request.websocket_pause_requested,
                .resume_requested = request.websocket_resume_requested,
                .resume_from_seq = request.websocket_resume_from_seq,
            }) catch |err| {
                try finishWebSocketTerminalState(allocator, sink, parsed.request_id, &state, err);
            };
            return;
        },
    }
}

const LiveExecutionHandle = struct {
    execution: *stream_registry.StreamExecution,
};

const WebSocketControlSignals = struct {
    acked_seq: ?*const std.atomic.Value(u64) = null,
    pause_requested: ?*std.atomic.Value(bool) = null,
    resume_requested: ?*std.atomic.Value(bool) = null,
    resume_from_seq: ?*const std.atomic.Value(u64) = null,
};

fn startLiveExecution(app: *runtime.AppContext, parsed: *const ParsedRequest) anyerror!LiveExecutionHandle {
    const execution = try app.stream_registry.startExecution(.{
        .request_id = parsed.request_id,
        .session_id = parsed.session_id,
        .prompt = parsed.prompt,
        .provider_id = parsed.provider_id,
        .tool_id = parsed.tool_id,
        .tool_input_json = parsed.tool_input_json,
        .authority = parsed.authority,
    });
    return .{ .execution = execution };
}

fn releaseExecutionIfNeeded(_: LiveExecutionHandle) void {}

fn drainExecutionAsSse(
    allocator: std.mem.Allocator,
    sink: ByteSink,
    state: *ProjectionState,
    execution: *stream_registry.StreamExecution,
    after_seq: u64,
) anyerror!void {
    var cursor = after_seq;
    var pending_text = TextDeltaBatch.init(allocator, state.policy);
    defer pending_text.deinit();

    while (true) {
        if (state.cancel_requested) |signal| {
            if (signal.load(.acquire)) {
                execution.requestCancel();
            }
        }
        if (state.client_closed) |signal| {
            if (signal.load(.acquire)) {
                execution.requestCancel();
            }
        }

        const events = try execution.snapshotAfter(allocator, cursor);
        defer {
            for (events) |*event| event.deinit(allocator);
            allocator.free(events);
        }

        if (events.len > 0) {
            for (events) |event| {
                const now_ms = std.time.milliTimestamp();
                if (std.mem.eql(u8, event.kind, "text.delta")) {
                    const text = extractTextDelta(event.payload_json) orelse {
                        try flushPendingSseText(allocator, sink, state, execution.id, &pending_text);
                        try writeControlledSseEvent(allocator, sink, state, execution.id, event.kind, event.seq, event.payload_json);
                        cursor = event.seq;
                        continue;
                    };
                    const stream_source = extractTextDeltaStreamSource(event.payload_json);
                    if (pending_text.shouldFlushBeforeAppend(text.len, stream_source)) {
                        try flushPendingSseText(allocator, sink, state, execution.id, &pending_text);
                    }
                    try pending_text.append(event.seq, text, stream_source);
                    cursor = event.seq;
                    if (pending_text.shouldFlushByWindow(now_ms)) {
                        try flushPendingSseText(allocator, sink, state, execution.id, &pending_text);
                    }
                    continue;
                }

                try flushPendingSseText(allocator, sink, state, execution.id, &pending_text);
                try writeControlledSseEvent(allocator, sink, state, execution.id, event.kind, event.seq, event.payload_json);
                cursor = event.seq;
                if (std.mem.eql(u8, event.kind, "done")) {
                    return;
                }
            }
            continue;
        }

        const terminal = execution.terminalSnapshot();
        if (terminal.completed) {
            try flushPendingSseText(allocator, sink, state, execution.id, &pending_text);
            if (cursor >= execution.latestSeq()) {
                return;
            }
        } else if (pending_text.shouldFlushByWindow(std.time.milliTimestamp())) {
            try flushPendingSseText(allocator, sink, state, execution.id, &pending_text);
        }

        std.Thread.sleep(EXECUTION_POLL_INTERVAL_MS * std.time.ns_per_ms);
    }
}

fn drainExecutionAsBridge(
    allocator: std.mem.Allocator,
    sink: ByteSink,
    state: *ProjectionState,
    execution: *stream_registry.StreamExecution,
    after_seq: u64,
) anyerror!void {
    var cursor = after_seq;
    var pending_text = TextDeltaBatch.init(allocator, state.policy);
    defer pending_text.deinit();

    while (true) {
        if (state.cancel_requested) |signal| {
            if (signal.load(.acquire)) {
                execution.requestCancel();
            }
        }
        if (state.client_closed) |signal| {
            if (signal.load(.acquire)) {
                execution.requestCancel();
            }
        }

        const events = try execution.snapshotAfter(allocator, cursor);
        defer {
            for (events) |*event| event.deinit(allocator);
            allocator.free(events);
        }

        if (events.len > 0) {
            for (events) |event| {
                const now_ms = std.time.milliTimestamp();
                if (std.mem.eql(u8, event.kind, "text.delta")) {
                    const text = extractTextDelta(event.payload_json) orelse {
                        try flushPendingBridgeText(allocator, sink, state, &pending_text);
                        try writeControlledJsonLineEvent(allocator, sink, state, event.kind, event.seq, event.payload_json);
                        cursor = event.seq;
                        continue;
                    };
                    const stream_source = extractTextDeltaStreamSource(event.payload_json);
                    if (pending_text.shouldFlushBeforeAppend(text.len, stream_source)) {
                        try flushPendingBridgeText(allocator, sink, state, &pending_text);
                    }
                    try pending_text.append(event.seq, text, stream_source);
                    cursor = event.seq;
                    if (pending_text.shouldFlushByWindow(now_ms)) {
                        try flushPendingBridgeText(allocator, sink, state, &pending_text);
                    }
                    continue;
                }

                if (std.mem.eql(u8, event.kind, "result")) {
                    try flushPendingBridgeText(allocator, sink, state, &pending_text);
                    try writeControlledJsonLineEvent(allocator, sink, state, event.kind, 0, event.payload_json);
                    cursor = event.seq;
                    continue;
                }

                if (std.mem.eql(u8, event.kind, "error")) {
                    try flushPendingBridgeText(allocator, sink, state, &pending_text);
                    try writeControlledJsonLineEvent(allocator, sink, state, event.kind, 0, event.payload_json);
                    cursor = event.seq;
                    continue;
                }

                if (std.mem.eql(u8, event.kind, "done")) {
                    try flushPendingBridgeText(allocator, sink, state, &pending_text);
                    const terminal_code = extractJsonStringField(event.payload_json, "terminalCode");
                    const terminal_reason = extractJsonStringField(event.payload_json, "terminalReason");
                    const done_ok = std.mem.indexOf(u8, event.payload_json, "\"ok\":true") != null;
                    const done_json = try buildDoneJson(
                        allocator,
                        done_ok,
                        terminal_code,
                        terminal_reason,
                        state.emitted_events,
                        state.emitted_bytes,
                    );
                    defer allocator.free(done_json);
                    try writeControlledJsonLineEvent(allocator, sink, state, event.kind, 0, done_json);
                    return;
                }

                try flushPendingBridgeText(allocator, sink, state, &pending_text);
                try writeControlledJsonLineEvent(allocator, sink, state, event.kind, event.seq, event.payload_json);
                cursor = event.seq;
            }
            continue;
        }

        const terminal = execution.terminalSnapshot();
        if (terminal.completed) {
            try flushPendingBridgeText(allocator, sink, state, &pending_text);
            if (cursor >= execution.latestSeq()) {
                return;
            }
        } else if (pending_text.shouldFlushByWindow(std.time.milliTimestamp())) {
            try flushPendingBridgeText(allocator, sink, state, &pending_text);
        }

        std.Thread.sleep(EXECUTION_POLL_INTERVAL_MS * std.time.ns_per_ms);
    }
}

fn drainExecutionAsWebSocket(
    allocator: std.mem.Allocator,
    sink: ByteSink,
    state: *ProjectionState,
    execution: *stream_registry.StreamExecution,
    after_seq: u64,
    signals: WebSocketControlSignals,
) anyerror!void {
    var cursor = after_seq;
    var pending_text = TextDeltaBatch.init(allocator, state.policy);
    defer pending_text.deinit();
    var paused = false;

    while (true) {
        if (state.cancel_requested) |signal| {
            if (signal.load(.acquire)) execution.requestCancel();
        }
        if (state.client_closed) |signal| {
            if (signal.load(.acquire)) execution.requestCancel();
        }

        if (signals.pause_requested) |pause_requested| {
            if (pause_requested.swap(false, .acq_rel)) {
                paused = true;
                const acked_seq = currentAckedSeq(signals, cursor);
                const pause_json = try buildControlJson(
                    allocator,
                    acked_seq,
                    acked_seq,
                    "client_pause",
                    1000,
                );
                defer allocator.free(pause_json);
                try writeRawWebSocketEvent(allocator, sink, "control.pause", 0, pause_json);
            }
        }

        if (signals.resume_requested) |resume_requested| {
            if (resume_requested.swap(false, .acq_rel)) {
                const acked_seq = currentAckedSeq(signals, cursor);
                const resume_from_seq = if (signals.resume_from_seq) |resume_from| resume_from.load(.acquire) else acked_seq;
                paused = false;
                cursor = @min(cursor, @min(acked_seq, resume_from_seq));
                const resume_json = try buildControlJson(allocator, acked_seq, resume_from_seq, "client_resume", 1000);
                defer allocator.free(resume_json);
                try writeRawWebSocketEvent(allocator, sink, "control.resume", 0, resume_json);
            }
        }

        if (paused) {
            if (execution.terminalSnapshot().completed and state.client_closed != null and state.client_closed.?.load(.acquire)) {
                return;
            }
            std.Thread.sleep(EXECUTION_POLL_INTERVAL_MS * std.time.ns_per_ms);
            continue;
        }

        const events = try execution.snapshotAfter(allocator, cursor);
        defer {
            for (events) |*event| event.deinit(allocator);
            allocator.free(events);
        }

        if (events.len > 0) {
            for (events) |event| {
                const now_ms = std.time.milliTimestamp();
                if (std.mem.eql(u8, event.kind, "text.delta")) {
                    const text = extractTextDelta(event.payload_json) orelse {
                        try flushPendingWebSocketText(allocator, sink, state, &pending_text);
                        try writeControlledWebSocketEvent(allocator, sink, state, event.kind, event.seq, event.payload_json);
                        cursor = event.seq;
                        continue;
                    };
                    const stream_source = extractTextDeltaStreamSource(event.payload_json);
                    if (pending_text.shouldFlushBeforeAppend(text.len, stream_source)) {
                        try flushPendingWebSocketText(allocator, sink, state, &pending_text);
                    }
                    try pending_text.append(event.seq, text, stream_source);
                    cursor = event.seq;
                    if (pending_text.shouldFlushByWindow(now_ms)) {
                        try flushPendingWebSocketText(allocator, sink, state, &pending_text);
                    }
                    continue;
                }

                try flushPendingWebSocketText(allocator, sink, state, &pending_text);
                try writeControlledWebSocketEvent(allocator, sink, state, event.kind, event.seq, event.payload_json);
                cursor = event.seq;
                if (std.mem.eql(u8, event.kind, "done")) {
                    const terminal = execution.terminalSnapshot();
                    try sendWebSocketCloseControl(allocator, sink, terminal.close_code, terminal.close_reason orelse "completed", currentAckedSeq(signals, cursor));
                    try stream_websocket.writeCloseFrameWithReason(sink, terminal.close_code, terminal.close_reason orelse "completed");
                    return;
                }
            }
            continue;
        }

        const terminal = execution.terminalSnapshot();
        if (terminal.completed) {
            try flushPendingWebSocketText(allocator, sink, state, &pending_text);
            if (cursor >= execution.latestSeq()) {
                try sendWebSocketCloseControl(allocator, sink, terminal.close_code, terminal.close_reason orelse "completed", cursor);
                try stream_websocket.writeCloseFrameWithReason(sink, terminal.close_code, terminal.close_reason orelse "completed");
                return;
            }
        } else if (pending_text.shouldFlushByWindow(std.time.milliTimestamp())) {
            try flushPendingWebSocketText(allocator, sink, state, &pending_text);
        }

        std.Thread.sleep(EXECUTION_POLL_INTERVAL_MS * std.time.ns_per_ms);
    }
}

fn currentAckedSeq(signals: WebSocketControlSignals, cursor: u64) u64 {
    if (signals.acked_seq) |acked| {
        const value = acked.load(.acquire);
        if (value > 0) return value;
    }
    return cursor;
}

fn flushPendingSseText(
    allocator: std.mem.Allocator,
    sink: ByteSink,
    state: *ProjectionState,
    execution_id: []const u8,
    pending_text: *TextDeltaBatch,
) anyerror!void {
    if (!pending_text.hasPending()) return;
    const payload = try buildTextDeltaJson(allocator, pending_text.buffer.items, pending_text.stream_source);
    defer allocator.free(payload);
    try writeControlledSseEvent(allocator, sink, state, execution_id, "text.delta", pending_text.latest_seq, payload);
    pending_text.reset();
}

fn flushPendingBridgeText(
    allocator: std.mem.Allocator,
    sink: ByteSink,
    state: *ProjectionState,
    pending_text: *TextDeltaBatch,
) anyerror!void {
    if (!pending_text.hasPending()) return;
    const payload = try buildTextDeltaJson(allocator, pending_text.buffer.items, pending_text.stream_source);
    defer allocator.free(payload);
    try writeControlledJsonLineEvent(allocator, sink, state, "text.delta", pending_text.latest_seq, payload);
    pending_text.reset();
}

fn flushPendingWebSocketText(
    allocator: std.mem.Allocator,
    sink: ByteSink,
    state: *ProjectionState,
    pending_text: *TextDeltaBatch,
) anyerror!void {
    if (!pending_text.hasPending()) return;
    const payload = try buildTextDeltaJson(allocator, pending_text.buffer.items, pending_text.stream_source);
    defer allocator.free(payload);
    try writeControlledWebSocketEvent(allocator, sink, state, "text.delta", pending_text.latest_seq, payload);
    pending_text.reset();
}

fn buildControlJson(
    allocator: std.mem.Allocator,
    acked_seq: u64,
    replay_from_seq: u64,
    reason: []const u8,
    close_code: u16,
) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);
    try writer.writeByte('{');
    try appendJsonUnsignedField(writer, "ackedSeq", acked_seq, true);
    try appendJsonUnsignedField(writer, "replayFromSeq", replay_from_seq, false);
    try appendJsonStringField(writer, "reason", reason, false);
    try appendJsonUnsignedField(writer, "code", close_code, false);
    try writer.writeByte('}');
    return allocator.dupe(u8, buf.items);
}

fn sendWebSocketCloseControl(
    allocator: std.mem.Allocator,
    sink: ByteSink,
    close_code: u16,
    close_reason: []const u8,
    acked_seq: u64,
) anyerror!void {
    const payload = try buildControlJson(allocator, acked_seq, acked_seq, close_reason, close_code);
    defer allocator.free(payload);
    try writeRawWebSocketEvent(allocator, sink, "control.close", 0, payload);
}

fn parseRequest(allocator: std.mem.Allocator, request: StreamRequest) anyerror!ParsedRequest {
    const session_id = requiredStringParam(request.params, "session_id") orelse return error.InvalidAgentStreamRequest;
    const prompt = requiredStringParam(request.params, "prompt") orelse return error.InvalidAgentStreamRequest;
    const provider_id = optionalStringParam(request.params, "provider_id") orelse "openai";
    const tool_id = optionalStringParam(request.params, "tool_id");
    const tool_input_json = optionalStringParam(request.params, "tool_input_json");
    const resume_cursor = try parseResumeCursor(allocator, request.params);
    const policy = try resolvePolicy(request.params, request.policy);

    return .{
        .request_id = try allocator.dupe(u8, request.request_id),
        .session_id = try allocator.dupe(u8, session_id),
        .prompt = try allocator.dupe(u8, prompt),
        .provider_id = try allocator.dupe(u8, provider_id),
        .tool_id = if (tool_id) |value| try allocator.dupe(u8, value) else null,
        .tool_input_json = if (tool_input_json) |value| try allocator.dupe(u8, value) else null,
        .resume_cursor = resume_cursor,
        .authority = request.authority,
        .policy = policy,
        .cancel_requested = request.cancel_requested,
        .client_closed = request.client_closed,
    };
}

fn resolvePolicy(params: []const framework.ValidationField, base: ProjectionPolicy) anyerror!ProjectionPolicy {
    var policy = base;
    if (try optionalUsizeParam(params, "cancel_after_events")) |value| {
        policy.cancel_after_events = value;
    }
    if (try optionalUsizeParam(params, "max_total_bytes")) |value| {
        policy.max_total_bytes = value;
    }
    if (try optionalUsizeParam(params, "max_event_bytes")) |value| {
        policy.max_event_bytes = value;
    }
    if (try optionalUsizeParam(params, "text_delta_coalesce_event_limit")) |value| {
        policy.text_delta_coalesce_event_limit = value;
    }
    if (try optionalUsizeParam(params, "text_delta_coalesce_byte_limit")) |value| {
        policy.text_delta_coalesce_byte_limit = value;
    }
    if (try optionalU64Param(params, "text_delta_throttle_window_ms")) |value| {
        policy.text_delta_throttle_window_ms = value;
    }
    return policy;
}

fn requiredStringParam(params: []const framework.ValidationField, key: []const u8) ?[]const u8 {
    for (params) |field| {
        if (!std.mem.eql(u8, field.key, key)) continue;
        return switch (field.value) {
            .string => |value| if (value.len > 0) value else null,
            else => null,
        };
    }
    return null;
}

fn optionalStringParam(params: []const framework.ValidationField, key: []const u8) ?[]const u8 {
    for (params) |field| {
        if (!std.mem.eql(u8, field.key, key)) continue;
        return switch (field.value) {
            .string => |value| value,
            else => null,
        };
    }
    return null;
}

fn optionalUsizeParam(params: []const framework.ValidationField, key: []const u8) anyerror!?usize {
    for (params) |field| {
        if (!std.mem.eql(u8, field.key, key)) continue;
        return switch (field.value) {
            .integer => |value| blk: {
                if (value < 0) return error.InvalidAgentStreamRequest;
                break :blk @intCast(value);
            },
            .string => |value| if (value.len == 0)
                null
            else
                std.fmt.parseInt(usize, value, 10) catch error.InvalidAgentStreamRequest,
            else => error.InvalidAgentStreamRequest,
        };
    }
    return null;
}

fn optionalU64Param(params: []const framework.ValidationField, key: []const u8) anyerror!?u64 {
    for (params) |field| {
        if (!std.mem.eql(u8, field.key, key)) continue;
        return switch (field.value) {
            .integer => |value| blk: {
                if (value < 0) return error.InvalidAgentStreamRequest;
                break :blk @intCast(value);
            },
            .string => |value| if (value.len == 0)
                null
            else
                std.fmt.parseInt(u64, value, 10) catch error.InvalidAgentStreamRequest,
            else => error.InvalidAgentStreamRequest,
        };
    }
    return null;
}

fn parseResumeCursor(allocator: std.mem.Allocator, params: []const framework.ValidationField) anyerror!?ResumeCursor {
    for (params) |field| {
        if (!std.mem.eql(u8, field.key, "last_event_id")) continue;
        return switch (field.value) {
            .integer => |value| blk: {
                if (value < 0) return error.InvalidAgentStreamRequest;
                break :blk ResumeCursor{ .legacy_seq = @intCast(value) };
            },
            .string => |value| blk: {
                if (value.len == 0) break :blk null;
                if (std.mem.lastIndexOfScalar(u8, value, ':')) |pivot| {
                    if (pivot == 0 or pivot + 1 >= value.len) return error.InvalidAgentStreamRequest;
                    const execution_id = try allocator.dupe(u8, value[0..pivot]);
                    errdefer allocator.free(execution_id);
                    const after_seq = std.fmt.parseInt(u64, value[pivot + 1 ..], 10) catch return error.InvalidAgentStreamRequest;
                    break :blk ResumeCursor{ .execution = .{ .execution_id = execution_id, .after_seq = after_seq } };
                }
                break :blk ResumeCursor{ .legacy_seq = std.fmt.parseInt(u64, value, 10) catch return error.InvalidAgentStreamRequest };
            },
            else => error.InvalidAgentStreamRequest,
        };
    }
    return null;
}

fn writeControlledSseEvent(
    allocator: std.mem.Allocator,
    sink: ByteSink,
    state: *ProjectionState,
    execution_id: ?[]const u8,
    event_name: []const u8,
    seq: u64,
    data_json: []const u8,
) anyerror!void {
    const rendered = try renderSseEvent(allocator, execution_id, event_name, seq, data_json);
    defer allocator.free(rendered);
    try state.prepareWrite(rendered.len);
    sink.writeAll(rendered) catch |err| return state.mapSinkError(err);
    sink.flush() catch |err| return state.mapSinkError(err);
    state.commitWrite(rendered.len);
}

fn writeControlledJsonLineEvent(allocator: std.mem.Allocator, sink: ByteSink, state: *ProjectionState, event_name: []const u8, seq: u64, data_json: []const u8) anyerror!void {
    const rendered = try framework.renderJsonEvent(allocator, event_name, seq, data_json);
    defer allocator.free(rendered);
    try state.prepareWrite(rendered.len + 1);
    sink.writeAll(rendered) catch |err| return state.mapSinkError(err);
    sink.writeAll("\n") catch |err| return state.mapSinkError(err);
    sink.flush() catch |err| return state.mapSinkError(err);
    state.commitWrite(rendered.len + 1);
}

fn writeControlledWebSocketEvent(allocator: std.mem.Allocator, sink: ByteSink, state: *ProjectionState, event_name: []const u8, seq: u64, data_json: []const u8) anyerror!void {
    const rendered = try framework.renderJsonEvent(allocator, event_name, seq, data_json);
    defer allocator.free(rendered);
    const byte_count = webSocketFrameByteCount(rendered.len);
    try state.prepareWrite(byte_count);
    stream_websocket.writeTextFrame(sink, rendered) catch |err| return state.mapSinkError(err);
    state.commitWrite(byte_count);
}

fn writeRawSseEvent(allocator: std.mem.Allocator, sink: ByteSink, event_name: []const u8, seq: u64, data_json: []const u8) anyerror!void {
    const rendered = try renderSseEvent(allocator, null, event_name, seq, data_json);
    defer allocator.free(rendered);
    try sink.writeAll(rendered);
    try sink.flush();
}

fn writeRawJsonLineEvent(allocator: std.mem.Allocator, sink: ByteSink, event_name: []const u8, seq: u64, data_json: []const u8) anyerror!void {
    const rendered = try framework.renderJsonEvent(allocator, event_name, seq, data_json);
    defer allocator.free(rendered);
    try sink.writeAll(rendered);
    try sink.writeAll("\n");
    try sink.flush();
}

fn writeRawWebSocketEvent(allocator: std.mem.Allocator, sink: ByteSink, event_name: []const u8, seq: u64, data_json: []const u8) anyerror!void {
    const rendered = try framework.renderJsonEvent(allocator, event_name, seq, data_json);
    defer allocator.free(rendered);
    try stream_websocket.writeTextFrame(sink, rendered);
}

const ReplayOutcome = struct {
    replayed_events: usize = 0,
    reached_terminal_event: bool = false,
};

const ParsedStreamOutputEnvelope = struct {
    session_id: []const u8,
    kind: []const u8,
    payload_json: []const u8,
};

fn replaySseSessionEventsAfterSeq(
    allocator: std.mem.Allocator,
    app: *runtime.AppContext,
    session_id: []const u8,
    after_seq: u64,
    sink: ByteSink,
    state: *ProjectionState,
) anyerror!ReplayOutcome {
    const events = try app.framework_context.event_bus.pollAfter(allocator, after_seq);
    defer {
        for (events) |*event| event.deinit(allocator);
        allocator.free(events);
    }

    var outcome = ReplayOutcome{};
    for (events) |event| {
        if (!std.mem.eql(u8, event.topic, "stream.output")) continue;
        const parsed = parseStreamOutputEnvelope(event.payload_json) catch continue;
        if (!std.mem.eql(u8, parsed.session_id, session_id)) continue;
        try writeControlledSseEvent(allocator, sink, state, null, parsed.kind, event.seq, parsed.payload_json);
        outcome.replayed_events += 1;
        if (std.mem.eql(u8, parsed.kind, "final.result")) {
            outcome.reached_terminal_event = true;
        }
    }
    return outcome;
}

fn replayBridgeSessionEventsAfterSeq(
    allocator: std.mem.Allocator,
    app: *runtime.AppContext,
    session_id: []const u8,
    after_seq: u64,
    sink: ByteSink,
    state: *ProjectionState,
) anyerror!ReplayOutcome {
    const events = try app.framework_context.event_bus.pollAfter(allocator, after_seq);
    defer {
        for (events) |*event| event.deinit(allocator);
        allocator.free(events);
    }

    var outcome = ReplayOutcome{};
    for (events) |event| {
        if (!std.mem.eql(u8, event.topic, "stream.output")) continue;
        const parsed = parseStreamOutputEnvelope(event.payload_json) catch continue;
        if (!std.mem.eql(u8, parsed.session_id, session_id)) continue;
        try writeControlledJsonLineEvent(allocator, sink, state, parsed.kind, event.seq, parsed.payload_json);
        outcome.replayed_events += 1;
        if (std.mem.eql(u8, parsed.kind, "final.result")) {
            outcome.reached_terminal_event = true;
        }
    }
    return outcome;
}

fn replayWebSocketSessionEventsAfterSeq(
    allocator: std.mem.Allocator,
    app: *runtime.AppContext,
    session_id: []const u8,
    after_seq: u64,
    sink: ByteSink,
    state: *ProjectionState,
) anyerror!ReplayOutcome {
    const events = try app.framework_context.event_bus.pollAfter(allocator, after_seq);
    defer {
        for (events) |*event| event.deinit(allocator);
        allocator.free(events);
    }

    var outcome = ReplayOutcome{};
    for (events) |event| {
        if (!std.mem.eql(u8, event.topic, "stream.output")) continue;
        const parsed = parseStreamOutputEnvelope(event.payload_json) catch continue;
        if (!std.mem.eql(u8, parsed.session_id, session_id)) continue;
        try writeControlledWebSocketEvent(allocator, sink, state, parsed.kind, event.seq, parsed.payload_json);
        outcome.replayed_events += 1;
        if (std.mem.eql(u8, parsed.kind, "final.result")) {
            outcome.reached_terminal_event = true;
        }
    }
    return outcome;
}

fn parseStreamOutputEnvelope(envelope_json: []const u8) anyerror!ParsedStreamOutputEnvelope {
    const session_id = extractJsonStringField(envelope_json, "sessionId") orelse return error.InvalidStreamOutputEnvelope;
    const kind = extractJsonStringField(envelope_json, "kind") orelse return error.InvalidStreamOutputEnvelope;
    const payload_marker = "\"payload\":";
    const payload_start = std.mem.indexOf(u8, envelope_json, payload_marker) orelse return error.InvalidStreamOutputEnvelope;
    if (envelope_json.len < payload_start + payload_marker.len + 1) return error.InvalidStreamOutputEnvelope;
    if (envelope_json[envelope_json.len - 1] != '}') return error.InvalidStreamOutputEnvelope;
    return .{
        .session_id = session_id,
        .kind = kind,
        .payload_json = envelope_json[payload_start + payload_marker.len .. envelope_json.len - 1],
    };
}

fn extractTextDelta(payload_json: []const u8) ?[]const u8 {
    return extractJsonStringField(payload_json, "text");
}

fn buildTextDeltaJson(allocator: std.mem.Allocator, text: []const u8, stream_source: ?[]const u8) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);
    try writer.writeByte('{');
    try appendJsonStringField(writer, "text", text, true);
    if (stream_source) |value| {
        try appendJsonStringField(writer, "streamSource", value, false);
    }
    try writer.writeByte('}');
    return allocator.dupe(u8, buf.items);
}

fn extractTextDeltaStreamSource(payload_json: []const u8) ?[]const u8 {
    return extractJsonStringField(payload_json, "streamSource");
}

fn sameOptionalString(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null and right == null) return true;
    if (left == null or right == null) return false;
    return std.mem.eql(u8, left.?, right.?);
}

fn extractJsonStringField(body: []const u8, key: []const u8) ?[]const u8 {
    var marker_buf: [128]u8 = undefined;
    const marker = std.fmt.bufPrint(&marker_buf, "\"{s}\":\"", .{key}) catch return null;
    const start = std.mem.indexOf(u8, body, marker) orelse return null;
    const value_start = start + marker.len;
    var value_end = value_start;
    var escaped = false;
    while (value_end < body.len) : (value_end += 1) {
        const ch = body[value_end];
        if (escaped) {
            escaped = false;
            continue;
        }
        if (ch == '\\') {
            escaped = true;
            continue;
        }
        if (ch == '"') break;
    }
    if (value_end >= body.len) return null;
    return body[value_start..value_end];
}

fn finishSseTerminalState(allocator: std.mem.Allocator, sink: ByteSink, request_id: []const u8, state: *const ProjectionState, err: anyerror) anyerror!void {
    if (try writeControlledSseTermination(allocator, sink, request_id, state, err)) {
        return;
    }
    try writeSseProjectionFailure(allocator, sink, request_id, err);
}

fn finishBridgeTerminalState(allocator: std.mem.Allocator, sink: ByteSink, request_id: []const u8, state: *const ProjectionState, err: anyerror) anyerror!void {
    if (try writeControlledBridgeTermination(allocator, sink, request_id, state, err)) {
        return;
    }
    try writeBridgeProjectionFailure(allocator, sink, request_id, err);
}

fn finishWebSocketTerminalState(allocator: std.mem.Allocator, sink: ByteSink, request_id: []const u8, state: *const ProjectionState, err: anyerror) anyerror!void {
    if (try writeControlledWebSocketTermination(allocator, sink, request_id, state, err)) {
        return;
    }
    try writeWebSocketProjectionFailure(allocator, sink, request_id, err);
    try stream_websocket.writeCloseFrame(sink);
}

fn writeControlledSseTermination(allocator: std.mem.Allocator, sink: ByteSink, request_id: []const u8, state: *const ProjectionState, err: anyerror) anyerror!bool {
    if (!isControlledTerminalError(err)) return false;
    if (state.control.isClientDisconnect()) return true;

    const error_json = try buildErrorJson(allocator, request_id, state.control.errorCode().?);
    defer allocator.free(error_json);
    try writeRawSseEvent(allocator, sink, "error", 0, error_json);

    const done_json = try buildDoneJson(
        allocator,
        false,
        state.control.errorCode(),
        state.control.reasonLabel(),
        state.emitted_events,
        state.emitted_bytes,
    );
    defer allocator.free(done_json);
    try writeRawSseEvent(allocator, sink, "done", 0, done_json);
    return true;
}

fn writeControlledBridgeTermination(allocator: std.mem.Allocator, sink: ByteSink, request_id: []const u8, state: *const ProjectionState, err: anyerror) anyerror!bool {
    if (!isControlledTerminalError(err)) return false;
    if (state.control.isClientDisconnect()) return true;

    const error_json = try buildErrorJson(allocator, request_id, state.control.errorCode().?);
    defer allocator.free(error_json);
    try writeRawJsonLineEvent(allocator, sink, "error", 0, error_json);

    const done_json = try buildDoneJson(
        allocator,
        false,
        state.control.errorCode(),
        state.control.reasonLabel(),
        state.emitted_events,
        state.emitted_bytes,
    );
    defer allocator.free(done_json);
    try writeRawJsonLineEvent(allocator, sink, "done", 0, done_json);
    return true;
}

fn writeControlledWebSocketTermination(allocator: std.mem.Allocator, sink: ByteSink, request_id: []const u8, state: *const ProjectionState, err: anyerror) anyerror!bool {
    if (!isControlledTerminalError(err)) return false;
    if (state.control.isClientDisconnect()) return true;

    const error_json = try buildErrorJson(allocator, request_id, state.control.errorCode().?);
    defer allocator.free(error_json);
    try writeRawWebSocketEvent(allocator, sink, "error", 0, error_json);

    const done_json = try buildDoneJson(
        allocator,
        false,
        state.control.errorCode(),
        state.control.reasonLabel(),
        state.emitted_events,
        state.emitted_bytes,
    );
    defer allocator.free(done_json);
    try writeRawWebSocketEvent(allocator, sink, "done", 0, done_json);
    const close_code, const close_reason = controlledTerminalClose(err);
    try stream_websocket.writeCloseFrameWithReason(sink, close_code, close_reason);
    return true;
}

fn controlledTerminalClose(err: anyerror) struct { u16, []const u8 } {
    return switch (err) {
        error.StreamCancelled => .{ 1000, "client_cancel" },
        error.StreamBackpressureExceeded => .{ 1008, "backpressure" },
        error.StreamClientDisconnected => .{ 1001, "client_disconnect" },
        else => .{ 1011, "error" },
    };
}

fn isControlledTerminalError(err: anyerror) bool {
    return switch (err) {
        error.StreamCancelled,
        error.StreamBackpressureExceeded,
        error.StreamClientDisconnected,
        => true,
        else => false,
    };
}

fn isDisconnectError(err: anyerror) bool {
    return switch (err) {
        error.BrokenPipe,
        error.ConnectionAborted,
        error.ConnectionResetByPeer,
        error.ConnectionTimedOut,
        error.EndOfStream,
        error.NotOpenForWriting,
        error.OperationAborted,
        => true,
        else => false,
    };
}

fn renderSseEvent(
    allocator: std.mem.Allocator,
    execution_id: ?[]const u8,
    event_name: []const u8,
    seq: u64,
    data_json: []const u8,
) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);
    if (seq > 0) {
        if (execution_id) |actual_execution_id| {
            try writer.print("id: {s}:{d}\n", .{ actual_execution_id, seq });
        } else {
            try writer.print("id: {d}\n", .{seq});
        }
    }
    try writer.writeAll("event: ");
    try writer.writeAll(event_name);
    try writer.writeAll("\n");
    try writer.writeAll("data: ");
    try writer.writeAll(data_json);
    try writer.writeAll("\n\n");
    return allocator.dupe(u8, buf.items);
}

fn webSocketFrameByteCount(payload_len: usize) usize {
    if (payload_len <= 125) return payload_len + 2;
    if (payload_len <= 65535) return payload_len + 4;
    return payload_len + 10;
}

fn writeSseProjectionFailure(allocator: std.mem.Allocator, sink: ByteSink, request_id: []const u8, err: anyerror) anyerror!void {
    const error_json = try buildErrorJson(allocator, request_id, @errorName(err));
    defer allocator.free(error_json);
    try writeRawSseEvent(allocator, sink, "error", 0, error_json);

    const done_json = try buildDoneJson(allocator, false, @errorName(err), "error", 0, 0);
    defer allocator.free(done_json);
    try writeRawSseEvent(allocator, sink, "done", 0, done_json);
}

fn writeBridgeProjectionFailure(allocator: std.mem.Allocator, sink: ByteSink, request_id: []const u8, err: anyerror) anyerror!void {
    const error_json = try buildErrorJson(allocator, request_id, @errorName(err));
    defer allocator.free(error_json);
    try writeRawJsonLineEvent(allocator, sink, "error", 0, error_json);

    const done_json = try buildDoneJson(allocator, false, @errorName(err), "error", 0, 0);
    defer allocator.free(done_json);
    try writeRawJsonLineEvent(allocator, sink, "done", 0, done_json);
}

fn writeWebSocketProjectionFailure(allocator: std.mem.Allocator, sink: ByteSink, request_id: []const u8, err: anyerror) anyerror!void {
    const error_json = try buildErrorJson(allocator, request_id, @errorName(err));
    defer allocator.free(error_json);
    try writeRawWebSocketEvent(allocator, sink, "error", 0, error_json);

    const done_json = try buildDoneJson(allocator, false, @errorName(err), "error", 0, 0);
    defer allocator.free(done_json);
    try writeRawWebSocketEvent(allocator, sink, "done", 0, done_json);
}

fn buildMetaJson(
    allocator: std.mem.Allocator,
    request_id: []const u8,
    execution_id: ?[]const u8,
    session_id: []const u8,
    provider_id: []const u8,
    last_event_id: ?u64,
    resume_mode: []const u8,
) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);
    try writer.writeByte('{');
    try appendJsonStringField(writer, "requestId", request_id, true);
    try appendOptionalJsonStringField(writer, "executionId", execution_id, false);
    try appendJsonStringField(writer, "sessionId", session_id, false);
    try appendJsonStringField(writer, "providerId", provider_id, false);
    try appendOptionalJsonUnsignedField(writer, "lastEventId", last_event_id, false);
    try appendJsonStringField(writer, "resumeMode", resume_mode, false);
    try writer.writeByte('}');
    return allocator.dupe(u8, buf.items);
}

fn buildResultJson(allocator: std.mem.Allocator, result: anytype) anyerror![]u8 {
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
    emitted_events: usize,
    emitted_bytes: usize,
) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);
    try writer.writeByte('{');
    try appendJsonBoolField(writer, "ok", ok, true);
    try appendOptionalJsonStringField(writer, "terminalCode", terminal_code, false);
    try appendOptionalJsonStringField(writer, "terminalReason", terminal_reason, false);
    try appendJsonUnsignedField(writer, "emittedEvents", @intCast(emitted_events), false);
    try appendJsonUnsignedField(writer, "emittedBytes", @intCast(emitted_bytes), false);
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

fn appendJsonUnsignedField(writer: anytype, key: []const u8, value: u64, first: bool) anyerror!void {
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

fn appendOptionalJsonUnsignedField(writer: anytype, key: []const u8, value: ?u64, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    if (value) |actual| {
        try writer.print("{d}", .{actual});
        return;
    }
    try writer.writeAll("null");
}

fn appendRawJsonField(writer: anytype, key: []const u8, value_json: []const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.writeAll(value_json);
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

const DisconnectingSink = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8) = .empty,
    max_writes: usize,
    write_count: usize = 0,

    fn init(allocator: std.mem.Allocator, max_writes: usize) DisconnectingSink {
        return .{ .allocator = allocator, .max_writes = max_writes };
    }

    fn deinit(self: *DisconnectingSink) void {
        self.buffer.deinit(self.allocator);
    }

    fn asByteSink(self: *DisconnectingSink) ByteSink {
        return .{
            .ptr = @ptrCast(self),
            .write_all = writeAllErased,
            .flush_fn = flushErased,
        };
    }

    fn toOwnedSlice(self: *DisconnectingSink) anyerror![]u8 {
        return self.allocator.dupe(u8, self.buffer.items);
    }

    fn writeAllErased(ptr: *anyopaque, bytes: []const u8) anyerror!void {
        const self: *DisconnectingSink = @ptrCast(@alignCast(ptr));
        if (self.write_count >= self.max_writes) return error.BrokenPipe;
        self.write_count += 1;
        try self.buffer.appendSlice(self.allocator, bytes);
    }

    fn flushErased(_: *anyopaque) anyerror!void {}
};

fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
    if (needle.len == 0) return 0;
    var count: usize = 0;
    var offset: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, offset, needle)) |index| {
        count += 1;
        offset = index + needle.len;
    }
    return count;
}

test "stream projection resolves text delta policy overrides from params" {
    const params = [_]framework.ValidationField{
        .{ .key = "text_delta_coalesce_event_limit", .value = .{ .integer = 9 } },
        .{ .key = "text_delta_coalesce_byte_limit", .value = .{ .integer = 2048 } },
        .{ .key = "text_delta_throttle_window_ms", .value = .{ .string = "0" } },
    };

    const resolved = try resolvePolicy(params[0..], .{});
    try std.testing.expectEqual(@as(usize, 9), resolved.text_delta_coalesce_event_limit);
    try std.testing.expectEqual(@as(usize, 2048), resolved.text_delta_coalesce_byte_limit);
    try std.testing.expectEqual(@as(u64, 0), resolved.text_delta_throttle_window_ms);
}

test "stream projection resolves policy overrides from params" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_stream_policy",
        .label = "Mock OpenAI Stream Policy",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_stream_policy" } },
        .{ .key = "prompt", .value = .{ .string = "CALL_TOOL:echo" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_stream_policy" } },
        .{ .key = "cancel_after_events", .value = .{ .integer = 1 } },
    };

    var sink = sink_model.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();
    try writeBridgeAgentStream(std.testing.allocator, app, .{
        .request_id = "stream_req_policy_01",
        .params = params[0..],
        .authority = .admin,
    }, sink.asByteSink());

    const output = try sink.toOwnedSlice();
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"event\":\"meta\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "StreamCancelled") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"terminalReason\":\"cancel_after_events\"") != null);
}

test "stream projection bridge drains text delta by throttle window policy" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_stream_bridge_throttle",
        .label = "Mock OpenAI Stream Bridge Throttle",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    const base_params = [_]framework.ValidationField{
        .{ .key = "prompt", .value = .{ .string = "CALL_TOOL:echo" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_stream_bridge_throttle" } },
        .{ .key = "text_delta_coalesce_event_limit", .value = .{ .integer = 64 } },
        .{ .key = "text_delta_coalesce_byte_limit", .value = .{ .integer = 4096 } },
    };

    const default_params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_bridge_throttle_default" } },
        base_params[0],
        base_params[1],
        base_params[2],
        base_params[3],
        .{ .key = "text_delta_throttle_window_ms", .value = .{ .integer = 60000 } },
    };

    var default_sink = sink_model.ArrayListSink.init(std.testing.allocator);
    defer default_sink.deinit();
    try writeBridgeAgentStream(std.testing.allocator, app, .{
        .request_id = "stream_req_bridge_throttle_default_01",
        .params = default_params[0..],
        .authority = .admin,
    }, default_sink.asByteSink());

    const default_output = try default_sink.toOwnedSlice();
    defer std.testing.allocator.free(default_output);
    const default_delta_count = countOccurrences(default_output, "\"event\":\"text.delta\"");
    try std.testing.expectEqual(@as(usize, 2), default_delta_count);
    try std.testing.expect(std.mem.indexOf(u8, default_output, "\"streamSource\":\"provider_native\"") != null);

    const window_params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_bridge_throttle_window" } },
        base_params[0],
        base_params[1],
        base_params[2],
        base_params[3],
        .{ .key = "text_delta_throttle_window_ms", .value = .{ .integer = 0 } },
    };

    var window_sink = sink_model.ArrayListSink.init(std.testing.allocator);
    defer window_sink.deinit();
    try writeBridgeAgentStream(std.testing.allocator, app, .{
        .request_id = "stream_req_bridge_throttle_window_01",
        .params = window_params[0..],
        .authority = .admin,
    }, window_sink.asByteSink());

    const window_output = try window_sink.toOwnedSlice();
    defer std.testing.allocator.free(window_output);
    const window_delta_count = countOccurrences(window_output, "\"event\":\"text.delta\"");
    try std.testing.expect(window_delta_count > default_delta_count);
    try std.testing.expect(window_delta_count >= 5);
    try std.testing.expect(std.mem.indexOf(u8, window_output, "\"streamSource\":\"provider_native\"") != null);
}

test "stream projection returns replay only sse stream for last event id" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_stream_replay",
        .label = "Mock OpenAI Stream Replay",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    var seeded = try app.agent_runtime.runStream(.{
        .session_id = "sess_stream_replay",
        .prompt = "CALL_TOOL:echo",
        .provider_id = "mock_openai_stream_replay",
        .authority = .admin,
    });
    defer seeded.deinit(std.testing.allocator);

    const latest_before = app.framework_context.event_bus.latestSeq();
    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_stream_replay" } },
        .{ .key = "prompt", .value = .{ .string = "ignored on replay" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_stream_replay" } },
        .{ .key = "last_event_id", .value = .{ .integer = 1 } },
    };

    var sink = sink_model.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();
    try writeSseAgentStream(std.testing.allocator, app, .{
        .request_id = "stream_req_replay_01",
        .params = params[0..],
        .authority = .admin,
    }, sink.asByteSink());

    const output = try sink.toOwnedSlice();
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"resumeMode\":\"replay_only\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "id: 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "event: final.result") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"terminalReason\":\"reconnect_replay_completed\"") != null);
    try std.testing.expectEqual(latest_before, app.framework_context.event_bus.latestSeq());
}

test "stream projection returns replay only bridge stream for last event id" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_stream_bridge_replay",
        .label = "Mock OpenAI Stream Bridge Replay",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    var seeded = try app.agent_runtime.runStream(.{
        .session_id = "sess_stream_bridge_replay",
        .prompt = "CALL_TOOL:echo",
        .provider_id = "mock_openai_stream_bridge_replay",
        .authority = .admin,
    });
    defer seeded.deinit(std.testing.allocator);

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_stream_bridge_replay" } },
        .{ .key = "prompt", .value = .{ .string = "ignored on replay" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_stream_bridge_replay" } },
        .{ .key = "last_event_id", .value = .{ .integer = 1 } },
    };

    var sink = sink_model.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();
    const parsed_bridge_replay = try parseResumeCursor(std.testing.allocator, params[0..]);
    try std.testing.expect(parsed_bridge_replay != null);
    switch (parsed_bridge_replay.?) {
        .legacy_seq => |value| try std.testing.expectEqual(@as(u64, 1), value),
        .execution => return error.TestUnexpectedResult,
    }
    try writeBridgeAgentStream(std.testing.allocator, app, .{
        .request_id = "stream_req_bridge_replay_01",
        .params = params[0..],
        .authority = .admin,
    }, sink.asByteSink());

    const output = try sink.toOwnedSlice();
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"resumeMode\":\"replay_only\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"event\":\"final.result\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"terminalReason\":\"reconnect_replay_completed\"") != null);
}

test "stream projection bridge resumes by execution cursor" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_stream_bridge_resume",
        .label = "Mock OpenAI Stream Bridge Resume",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    const execution = try app.stream_registry.startExecution(.{
        .request_id = "stream_req_bridge_resume_seed",
        .session_id = "sess_stream_bridge_resume",
        .prompt = "CALL_TOOL:echo",
        .provider_id = "mock_openai_stream_bridge_resume",
        .authority = .admin,
    });

    while (!execution.terminalSnapshot().completed) {
        std.Thread.sleep(2 * std.time.ns_per_ms);
    }

    const resume_value = try std.fmt.allocPrint(std.testing.allocator, "{s}:{d}", .{ execution.id, 1 });
    defer std.testing.allocator.free(resume_value);

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_stream_bridge_resume" } },
        .{ .key = "prompt", .value = .{ .string = "ignored on resume" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_stream_bridge_resume" } },
        .{ .key = "last_event_id", .value = .{ .string = resume_value } },
    };

    var sink = sink_model.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();
    const parsed_bridge_resume = try parseResumeCursor(std.testing.allocator, params[0..]);
    try std.testing.expect(parsed_bridge_resume != null);
    switch (parsed_bridge_resume.?) {
        .legacy_seq => return error.TestUnexpectedResult,
        .execution => |cursor| {
            defer std.testing.allocator.free(cursor.execution_id);
            try std.testing.expectEqualStrings(execution.id, cursor.execution_id);
            try std.testing.expectEqual(@as(u64, 1), cursor.after_seq);
        },
    }
    try writeBridgeAgentStream(std.testing.allocator, app, .{
        .request_id = "stream_req_bridge_resume_01",
        .params = params[0..],
        .authority = .admin,
    }, sink.asByteSink());

    const output = try sink.toOwnedSlice();
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"resumeMode\":\"resume\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, execution.id) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"event\":\"done\"") != null);
}

test "stream projection websocket returns replay only stream for last event id" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_stream_ws_replay",
        .label = "Mock OpenAI Stream WS Replay",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    var seeded = try app.agent_runtime.runStream(.{
        .session_id = "sess_stream_ws_replay",
        .prompt = "CALL_TOOL:echo",
        .provider_id = "mock_openai_stream_ws_replay",
        .authority = .admin,
    });
    defer seeded.deinit(std.testing.allocator);

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_stream_ws_replay" } },
        .{ .key = "prompt", .value = .{ .string = "ignored on replay" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_stream_ws_replay" } },
        .{ .key = "last_event_id", .value = .{ .integer = 1 } },
    };

    var sink = sink_model.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();
    const parsed_ws_replay = try parseResumeCursor(std.testing.allocator, params[0..]);
    try std.testing.expect(parsed_ws_replay != null);
    switch (parsed_ws_replay.?) {
        .legacy_seq => |value| try std.testing.expectEqual(@as(u64, 1), value),
        .execution => return error.TestUnexpectedResult,
    }
    try writeWebSocketAgentStream(std.testing.allocator, app, .{
        .request_id = "stream_req_ws_replay_01",
        .params = params[0..],
        .authority = .admin,
    }, sink.asByteSink());

    const bytes = try sink.toOwnedSlice();
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"resumeMode\":\"replay_only\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"event\":\"done\"") != null);
}

test "stream projection honours external cancel signal" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_stream_cancel_signal",
        .label = "Mock OpenAI Stream Cancel Signal",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_stream_cancel_signal" } },
        .{ .key = "prompt", .value = .{ .string = "CALL_TOOL:echo" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_stream_cancel_signal" } },
    };

    var cancel_requested = std.atomic.Value(bool).init(true);
    var sink = sink_model.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();
    try writeBridgeAgentStream(std.testing.allocator, app, .{
        .request_id = "stream_req_cancel_signal_01",
        .params = params[0..],
        .authority = .admin,
        .cancel_requested = &cancel_requested,
    }, sink.asByteSink());

    const output = try sink.toOwnedSlice();
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "StreamCancelled") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"terminalReason\":\"client_cancel\"") != null);
}

test "stream projection SSE honours external cancel signal" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_stream_sse_cancel_signal",
        .label = "Mock OpenAI Stream SSE Cancel Signal",
        .endpoint = "mock://openai/chat_cancel_wait",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = false,
        .health_json = "{}",
    });

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_stream_sse_cancel_signal" } },
        .{ .key = "prompt", .value = .{ .string = "hello cancel" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_stream_sse_cancel_signal" } },
    };

    var cancel_requested = std.atomic.Value(bool).init(false);
    const worker = try std.Thread.spawn(.{}, triggerProjectionCancelLater, .{&cancel_requested});
    defer worker.join();
    var sink = sink_model.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();
    try writeSseAgentStream(std.testing.allocator, app, .{
        .request_id = "stream_req_sse_cancel_signal_01",
        .params = params[0..],
        .authority = .admin,
        .cancel_requested = &cancel_requested,
    }, sink.asByteSink());

    const output = try sink.toOwnedSlice();
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "event: error") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "StreamCancelled") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"terminalReason\":\"client_cancel\"") != null);
}

test "stream projection treats broken pipe as client disconnect" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_stream_disconnect",
        .label = "Mock OpenAI Stream Disconnect",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_stream_disconnect" } },
        .{ .key = "prompt", .value = .{ .string = "CALL_TOOL:echo" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_stream_disconnect" } },
    };

    var sink = DisconnectingSink.init(std.testing.allocator, 2);
    defer sink.deinit();
    try writeBridgeAgentStream(std.testing.allocator, app, .{
        .request_id = "stream_req_disconnect_01",
        .params = params[0..],
        .authority = .admin,
    }, sink.asByteSink());

    const output = try sink.toOwnedSlice();
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"event\":\"meta\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "StreamClientDisconnected") == null);
}

test "stream projection websocket emits pause resume and close controls" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_stream_ws_control",
        .label = "Mock OpenAI Stream WS Control",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_stream_ws_control" } },
        .{ .key = "prompt", .value = .{ .string = "CALL_TOOL:echo" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_stream_ws_control" } },
    };

    var websocket_acked_seq = std.atomic.Value(u64).init(7);
    var websocket_pause_requested = std.atomic.Value(bool).init(true);
    var websocket_resume_requested = std.atomic.Value(bool).init(true);
    var websocket_resume_from_seq = std.atomic.Value(u64).init(5);

    var sink = sink_model.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();
    try writeWebSocketAgentStream(std.testing.allocator, app, .{
        .request_id = "stream_req_ws_control_01",
        .params = params[0..],
        .authority = .admin,
        .websocket_acked_seq = &websocket_acked_seq,
        .websocket_pause_requested = &websocket_pause_requested,
        .websocket_resume_requested = &websocket_resume_requested,
        .websocket_resume_from_seq = &websocket_resume_from_seq,
    }, sink.asByteSink());

    const bytes = try sink.toOwnedSlice();
    defer std.testing.allocator.free(bytes);

    var offset: usize = 0;
    var saw_pause = false;
    var saw_resume = false;
    var saw_close = false;
    while (offset < bytes.len) {
        const frame = try stream_websocket.parseServerFrame(bytes[offset..]);
        const payload_start = offset + frame.header_len;
        const payload_end = payload_start + frame.payload_len;
        const payload = bytes[payload_start..payload_end];

        if (frame.opcode == 0x8) {
            break;
        }

        if (std.mem.indexOf(u8, payload, "\"event\":\"control.pause\"") != null) {
            saw_pause = true;
        }
        if (std.mem.indexOf(u8, payload, "\"event\":\"control.resume\"") != null) {
            saw_resume = true;
            try std.testing.expect(std.mem.indexOf(u8, payload, "\"ackedSeq\":7") != null);
            try std.testing.expect(std.mem.indexOf(u8, payload, "\"replayFromSeq\":5") != null);
        }
        if (std.mem.indexOf(u8, payload, "\"event\":\"control.close\"") != null) {
            saw_close = true;
            try std.testing.expect(std.mem.indexOf(u8, payload, "\"ackedSeq\":7") != null);
            try std.testing.expect(std.mem.indexOf(u8, payload, "\"replayFromSeq\":7") != null);
            try std.testing.expect(std.mem.indexOf(u8, payload, "\"code\":1000") != null);
            try std.testing.expect(std.mem.indexOf(u8, payload, "\"reason\":\"completed\"") != null);
        }

        offset = payload_end;
    }

    try std.testing.expect(saw_pause);
    try std.testing.expect(saw_resume);
    try std.testing.expect(saw_close);
}

test "stream projection websocket controlled terminal writes close reason" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_stream_ws_controlled_close",
        .label = "Mock OpenAI Stream WS Controlled Close",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_stream_ws_controlled_close" } },
        .{ .key = "prompt", .value = .{ .string = "CALL_TOOL:echo" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_stream_ws_controlled_close" } },
        .{ .key = "cancel_after_events", .value = .{ .integer = 1 } },
    };

    var sink = sink_model.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();
    try writeWebSocketAgentStream(std.testing.allocator, app, .{
        .request_id = "stream_req_ws_controlled_close_01",
        .params = params[0..],
        .authority = .admin,
    }, sink.asByteSink());

    const bytes = try sink.toOwnedSlice();
    defer std.testing.allocator.free(bytes);

    var offset: usize = 0;
    var saw_done = false;
    var close_frame_found = false;
    while (offset < bytes.len) {
        const frame = try stream_websocket.parseServerFrame(bytes[offset..]);
        const payload_start = offset + frame.header_len;
        const payload_end = payload_start + frame.payload_len;
        const payload = bytes[payload_start..payload_end];

        if (frame.opcode == 0x8) {
            close_frame_found = true;
            const parsed_close = try stream_websocket.parseClosePayload(payload);
            try std.testing.expectEqual(@as(?u16, 1000), parsed_close.close_code);
            try std.testing.expect(parsed_close.close_reason != null);
            try std.testing.expectEqualStrings("client_cancel", parsed_close.close_reason.?);
            break;
        }

        if (std.mem.indexOf(u8, payload, "\"event\":\"done\"") != null) {
            saw_done = true;
            try std.testing.expect(std.mem.indexOf(u8, payload, "\"terminalReason\":\"cancel_after_events\"") != null);
        }

        offset = payload_end;
    }

    try std.testing.expect(saw_done);
    try std.testing.expect(close_frame_found);
}

test "stream projection websocket honours external cancel signal" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_stream_ws_cancel_signal",
        .label = "Mock OpenAI Stream WS Cancel Signal",
        .endpoint = "mock://openai/chat_cancel_wait",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = false,
        .health_json = "{}",
    });

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_stream_ws_cancel_signal" } },
        .{ .key = "prompt", .value = .{ .string = "hello cancel" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_stream_ws_cancel_signal" } },
    };

    var cancel_requested = std.atomic.Value(bool).init(false);
    const worker = try std.Thread.spawn(.{}, triggerProjectionCancelLater, .{&cancel_requested});
    defer worker.join();
    var sink = sink_model.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();
    try writeWebSocketAgentStream(std.testing.allocator, app, .{
        .request_id = "stream_req_ws_cancel_signal_01",
        .params = params[0..],
        .authority = .admin,
        .cancel_requested = &cancel_requested,
    }, sink.asByteSink());

    const bytes = try sink.toOwnedSlice();
    defer std.testing.allocator.free(bytes);

    var offset: usize = 0;
    var saw_done = false;
    var saw_close = false;
    while (offset < bytes.len) {
        const frame = try stream_websocket.parseServerFrame(bytes[offset..]);
        const payload_start = offset + frame.header_len;
        const payload_end = payload_start + frame.payload_len;
        const payload = bytes[payload_start..payload_end];

        if (frame.opcode == 0x8) {
            saw_close = true;
            const parsed_close = try stream_websocket.parseClosePayload(payload);
            try std.testing.expectEqual(@as(?u16, 1000), parsed_close.close_code);
            try std.testing.expect(parsed_close.close_reason != null);
            try std.testing.expectEqualStrings("client_cancel", parsed_close.close_reason.?);
            break;
        }

        if (std.mem.indexOf(u8, payload, "\"event\":\"done\"") != null) {
            saw_done = true;
            try std.testing.expect(std.mem.indexOf(u8, payload, "\"terminalReason\":\"client_cancel\"") != null);
        }

        offset = payload_end;
    }

    try std.testing.expect(saw_done);
    try std.testing.expect(saw_close);
}

fn triggerProjectionCancelLater(cancel_requested: *std.atomic.Value(bool)) void {
    std.Thread.sleep(30 * std.time.ns_per_ms);
    cancel_requested.store(true, .release);
}
