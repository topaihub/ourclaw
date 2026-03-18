const std = @import("std");
const framework = @import("framework");
const tools = @import("../tools/root.zig");
const security = @import("../security/policy.zig");
const stream_output = @import("stream_output.zig");

pub const Authority = framework.Authority;
pub const ToolRegistry = tools.ToolRegistry;
pub const SecurityPolicy = security.SecurityPolicy;
pub const StreamOutput = stream_output.StreamOutput;

pub const ToolOrchestrator = struct {
    allocator: std.mem.Allocator,
    tool_registry: *ToolRegistry,
    stream_output: *StreamOutput,
    logger: ?*framework.Logger = null,

    const Self = @This();

    /// ToolOrchestrator 只负责一次工具调用，不负责 provider ↔ tool 多轮编排。
    /// 多轮 loop 必须由 agent_runtime 显式驱动。
    pub const SingleInvokeRequest = struct {
        session_id: []const u8,
        execution_id: ?[]const u8 = null,
        tool_id: []const u8,
        input_json: []const u8,
        authority: Authority,
        confirm_risk: bool = false,
        remaining_budget: ?*usize = null,
        cancel_requested: ?*const std.atomic.Value(bool) = null,
    };

    pub fn init(allocator: std.mem.Allocator, tool_registry: *ToolRegistry, output: *StreamOutput) Self {
        return .{
            .allocator = allocator,
            .tool_registry = tool_registry,
            .stream_output = output,
        };
    }

    pub fn setLogger(self: *Self, logger: *framework.Logger) void {
        self.logger = logger;
    }

    pub fn invoke(self: *Self, session_id: []const u8, tool_id: []const u8, input_json: []const u8, authority: Authority) anyerror![]u8 {
        return self.invokeSingle(.{
            .session_id = session_id,
            .tool_id = tool_id,
            .input_json = input_json,
            .authority = authority,
        });
    }

    pub fn invokeWithExecution(
        self: *Self,
        session_id: []const u8,
        execution_id: ?[]const u8,
        tool_id: []const u8,
        input_json: []const u8,
        authority: Authority,
    ) anyerror![]u8 {
        return self.invokeSingle(.{
            .session_id = session_id,
            .execution_id = execution_id,
            .tool_id = tool_id,
            .input_json = input_json,
            .authority = authority,
        });
    }

    pub fn invokeSingle(self: *Self, request: SingleInvokeRequest) anyerror![]u8 {
        // 初始化方法追踪和摘要追踪
        const method_name = try std.fmt.allocPrint(self.allocator, "Tool.{s}", .{request.tool_id});
        defer self.allocator.free(method_name);

        var method_trace: ?framework.observability.MethodTrace = null;
        var summary_trace: ?framework.observability.SummaryTrace = null;
        if (self.logger) |logger| {
            method_trace = try framework.observability.MethodTrace.begin(
                self.allocator,
                logger,
                method_name,
                request.input_json,
                1000, // 工具调用通常较快，设置 1 秒阈值
            );
            summary_trace = try framework.observability.SummaryTrace.begin(
                self.allocator,
                logger,
                method_name,
                1000,
            );
        }
        defer {
            if (method_trace) |*trace| trace.deinit();
            if (summary_trace) |*trace| trace.deinit();
        }

        const definition = self.tool_registry.find(request.tool_id) orelse {
            if (method_trace) |*trace| trace.finishError("ToolNotFound", "TOOL_NOT_FOUND", false);
            if (summary_trace) |*trace| trace.finishError(.business);
            const payload = try std.fmt.allocPrint(
                self.allocator,
                "{{\"contract\":\"single_invocation\",\"toolId\":\"{s}\",\"errorCode\":\"TOOL_NOT_FOUND\"}}",
                .{request.tool_id},
            );
            defer self.allocator.free(payload);
            _ = try self.stream_output.publishWithExecution(request.session_id, request.execution_id, "tool.call.failed", payload);
            return error.ToolNotFound;
        };

        if (!SecurityPolicy.canInvokeTool(request.authority, request.tool_id)) {
            if (method_trace) |*trace| trace.finishError("PolicyDenied", "TOOL_POLICY_DENIED", false);
            if (summary_trace) |*trace| trace.finishError(.auth);
            const denied_payload = try std.fmt.allocPrint(
                self.allocator,
                "{{\"contract\":\"single_invocation\",\"toolId\":\"{s}\",\"requiredAuthority\":\"{s}\",\"riskLevel\":\"{s}\",\"errorCode\":\"TOOL_POLICY_DENIED\"}}",
                .{ request.tool_id, @tagName(definition.required_authority), definition.risk_level.asText() },
            );
            defer self.allocator.free(denied_payload);
            _ = try self.stream_output.publishWithExecution(
                request.session_id,
                request.execution_id,
                "tool.call.denied",
                denied_payload,
            );
            try self.publishAudit(request, definition, "denied_authority");
            return error.PolicyDenied;
        }

        if (definition.risk_level == .high and !request.confirm_risk) {
            if (method_trace) |*trace| trace.finishError("ToolRiskConfirmationRequired", "TOOL_RISK_CONFIRMATION_REQUIRED", false);
            if (summary_trace) |*trace| trace.finishError(.validation);
            const denied_payload = try std.fmt.allocPrint(
                self.allocator,
                "{{\"contract\":\"single_invocation\",\"toolId\":\"{s}\",\"requiredAuthority\":\"{s}\",\"riskLevel\":\"{s}\",\"errorCode\":\"TOOL_RISK_CONFIRMATION_REQUIRED\"}}",
                .{ request.tool_id, @tagName(definition.required_authority), definition.risk_level.asText() },
            );
            defer self.allocator.free(denied_payload);
            _ = try self.stream_output.publishWithExecution(request.session_id, request.execution_id, "tool.call.denied", denied_payload);
            try self.publishAudit(request, definition, "denied_risk_confirmation");
            return error.ToolRiskConfirmationRequired;
        }

        if (request.remaining_budget) |budget| {
            if (budget.* == 0) {
                if (method_trace) |*trace| trace.finishError("ToolBudgetExceeded", "TOOL_BUDGET_EXCEEDED", false);
                if (summary_trace) |*trace| trace.finishError(.business);
                const denied_payload = try std.fmt.allocPrint(
                    self.allocator,
                    "{{\"contract\":\"single_invocation\",\"toolId\":\"{s}\",\"requiredAuthority\":\"{s}\",\"riskLevel\":\"{s}\",\"errorCode\":\"TOOL_BUDGET_EXCEEDED\"}}",
                    .{ request.tool_id, @tagName(definition.required_authority), definition.risk_level.asText() },
                );
                defer self.allocator.free(denied_payload);
                _ = try self.stream_output.publishWithExecution(request.session_id, request.execution_id, "tool.call.denied", denied_payload);
                try self.publishAudit(request, definition, "denied_budget");
                return error.ToolBudgetExceeded;
            }
            budget.* -= 1;
        }

        const started_payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"contract\":\"single_invocation\",\"toolId\":\"{s}\",\"requiredAuthority\":\"{s}\",\"riskLevel\":\"{s}\",\"input\":{s}}}",
            .{ request.tool_id, @tagName(definition.required_authority), definition.risk_level.asText(), request.input_json },
        );
        defer self.allocator.free(started_payload);
        _ = try self.stream_output.publishWithExecution(
            request.session_id,
            request.execution_id,
            "tool.call.started",
            started_payload,
        );
        try self.publishAudit(request, definition, "started");

        const result = self.tool_registry.invokeWithPolicy(self.allocator, request.tool_id, request.input_json, .{ .confirm_risk = request.confirm_risk, .cancel_requested = request.cancel_requested }) catch |err| {
            if (method_trace) |*trace| trace.finishError(@errorName(err), null, false);
            if (summary_trace) |*trace| trace.finishError(.system);
            const mapped = tools.ToolRegistry.mapError(err);
            const payload = try std.fmt.allocPrint(
                self.allocator,
                "{{\"contract\":\"single_invocation\",\"toolId\":\"{s}\",\"requiredAuthority\":\"{s}\",\"riskLevel\":\"{s}\",\"errorCode\":\"{s}\",\"message\":\"{s}\"}}",
                .{ request.tool_id, @tagName(definition.required_authority), definition.risk_level.asText(), mapped.code, mapped.message },
            );
            defer self.allocator.free(payload);
            _ = try self.stream_output.publishWithExecution(request.session_id, request.execution_id, "tool.call.failed", payload);
            try self.publishAudit(request, definition, mapped.code);
            return err;
        };
        errdefer self.allocator.free(result);

        // 截取结果摘要（最多 96 字符）
        const result_summary = if (result.len <= 96) result else result[0..96];
        if (method_trace) |*trace| trace.finishSuccess(result_summary, false);
        if (summary_trace) |*trace| trace.finishSuccess();

        const finished_payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"contract\":\"single_invocation\",\"toolId\":\"{s}\",\"requiredAuthority\":\"{s}\",\"riskLevel\":\"{s}\",\"result\":{s}}}",
            .{ request.tool_id, @tagName(definition.required_authority), definition.risk_level.asText(), result },
        );
        defer self.allocator.free(finished_payload);
        _ = try self.stream_output.publishWithExecution(request.session_id, request.execution_id, "tool.call.finished", finished_payload);
        _ = try self.stream_output.publishWithExecution(request.session_id, request.execution_id, "tool.result", result);
        try self.publishAudit(request, definition, "finished");
        return result;
    }

    fn publishAudit(self: *Self, request: SingleInvokeRequest, definition: tools.ToolDefinition, outcome: []const u8) anyerror!void {
        const remaining_budget = if (request.remaining_budget) |budget| budget.* else 0;
        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"contract\":\"single_invocation\",\"toolId\":\"{s}\",\"outcome\":\"{s}\",\"requiredAuthority\":\"{s}\",\"riskLevel\":\"{s}\",\"confirmRisk\":{s},\"remainingBudget\":{d}}}",
            .{ request.tool_id, outcome, @tagName(definition.required_authority), definition.risk_level.asText(), if (request.confirm_risk) "true" else "false", remaining_budget },
        );
        defer self.allocator.free(payload);
        _ = try self.stream_output.publishWithExecution(request.session_id, request.execution_id, "tool.call.audit", payload);
    }
};

test "tool orchestrator invokes tool and emits stream output" {
    var registry = tools.ToolRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerBuiltins();

    var session_store = @import("session_state.zig").SessionStore.init(std.testing.allocator);
    defer session_store.deinit();
    var output = StreamOutput.init(std.testing.allocator, &session_store, null, null);
    defer output.deinit();
    var orchestrator = ToolOrchestrator.init(std.testing.allocator, &registry, &output);

    const result = try orchestrator.invoke("sess_01", "echo", "{\"message\":\"hello\"}", .public);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"tool\":\"echo\"") != null);
    try std.testing.expectEqual(@as(usize, 5), session_store.find("sess_01").?.events.items.len);
    try std.testing.expect(std.mem.indexOf(u8, session_store.find("sess_01").?.events.items[0].payload_json, "\"toolId\":\"echo\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, session_store.find("sess_01").?.events.items[0].payload_json, "\"contract\":\"single_invocation\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, session_store.find("sess_01").?.events.items[1].payload_json, "\"outcome\":\"started\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, session_store.find("sess_01").?.events.items[2].payload_json, "\"result\":") != null);
}

test "tool orchestrator denies high-risk tool without confirmation and budget" {
    var registry = tools.ToolRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerBuiltins();

    var session_store = @import("session_state.zig").SessionStore.init(std.testing.allocator);
    defer session_store.deinit();
    var output = StreamOutput.init(std.testing.allocator, &session_store, null, null);
    defer output.deinit();
    var orchestrator = ToolOrchestrator.init(std.testing.allocator, &registry, &output);

    var empty_budget: usize = 0;
    try std.testing.expectError(error.ToolBudgetExceeded, orchestrator.invokeSingle(.{
        .session_id = "sess_budget_denied",
        .tool_id = "echo",
        .input_json = "{}",
        .authority = .public,
        .remaining_budget = &empty_budget,
    }));

    try std.testing.expectError(error.ToolRiskConfirmationRequired, orchestrator.invokeSingle(.{
        .session_id = "sess_risk_denied",
        .tool_id = "shell",
        .input_json = "{\"command\":\"echo hello\"}",
        .authority = .admin,
    }));

    const risk_events = session_store.find("sess_risk_denied").?.events.items;
    try std.testing.expect(std.mem.indexOf(u8, risk_events[0].payload_json, "TOOL_RISK_CONFIRMATION_REQUIRED") != null or std.mem.indexOf(u8, risk_events[1].payload_json, "TOOL_RISK_CONFIRMATION_REQUIRED") != null);
}
