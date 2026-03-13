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

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, tool_registry: *ToolRegistry, output: *StreamOutput) Self {
        return .{
            .allocator = allocator,
            .tool_registry = tool_registry,
            .stream_output = output,
        };
    }

    pub fn invoke(self: *Self, session_id: []const u8, tool_id: []const u8, input_json: []const u8, authority: Authority) anyerror![]u8 {
        return self.invokeWithExecution(session_id, null, tool_id, input_json, authority);
    }

    pub fn invokeWithExecution(
        self: *Self,
        session_id: []const u8,
        execution_id: ?[]const u8,
        tool_id: []const u8,
        input_json: []const u8,
        authority: Authority,
    ) anyerror![]u8 {
        const definition = self.tool_registry.find(tool_id) orelse {
            const payload = try std.fmt.allocPrint(self.allocator, "{{\"toolId\":\"{s}\",\"errorCode\":\"TOOL_NOT_FOUND\"}}", .{tool_id});
            defer self.allocator.free(payload);
            _ = try self.stream_output.publishWithExecution(session_id, execution_id, "tool.call.failed", payload);
            return error.ToolNotFound;
        };

        if (!SecurityPolicy.canInvokeTool(authority, tool_id)) {
            const denied_payload = try std.fmt.allocPrint(
                self.allocator,
                "{{\"toolId\":\"{s}\",\"requiredAuthority\":\"{s}\",\"riskLevel\":\"{s}\",\"errorCode\":\"TOOL_POLICY_DENIED\"}}",
                .{ tool_id, @tagName(definition.required_authority), definition.risk_level.asText() },
            );
            defer self.allocator.free(denied_payload);
            _ = try self.stream_output.publishWithExecution(
                session_id,
                execution_id,
                "tool.call.denied",
                denied_payload,
            );
            return error.PolicyDenied;
        }

        const started_payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"toolId\":\"{s}\",\"requiredAuthority\":\"{s}\",\"riskLevel\":\"{s}\",\"input\":{s}}}",
            .{ tool_id, @tagName(definition.required_authority), definition.risk_level.asText(), input_json },
        );
        defer self.allocator.free(started_payload);
        _ = try self.stream_output.publishWithExecution(
            session_id,
            execution_id,
            "tool.call.started",
            started_payload,
        );

        const result = self.tool_registry.invoke(self.allocator, tool_id, input_json) catch |err| {
            const mapped = tools.ToolRegistry.mapError(err);
            const payload = try std.fmt.allocPrint(
                self.allocator,
                "{{\"toolId\":\"{s}\",\"requiredAuthority\":\"{s}\",\"riskLevel\":\"{s}\",\"errorCode\":\"{s}\",\"message\":\"{s}\"}}",
                .{ tool_id, @tagName(definition.required_authority), definition.risk_level.asText(), mapped.code, mapped.message },
            );
            defer self.allocator.free(payload);
            _ = try self.stream_output.publishWithExecution(session_id, execution_id, "tool.call.failed", payload);
            return err;
        };
        errdefer self.allocator.free(result);

        _ = try self.stream_output.publishWithExecution(session_id, execution_id, "tool.call.finished", result);
        _ = try self.stream_output.publishWithExecution(session_id, execution_id, "tool.result", result);
        return result;
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
    try std.testing.expectEqual(@as(usize, 3), session_store.find("sess_01").?.events.items.len);
    try std.testing.expect(std.mem.indexOf(u8, session_store.find("sess_01").?.events.items[0].payload_json, "\"toolId\":\"echo\"") != null);
}
