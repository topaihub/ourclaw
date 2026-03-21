const std = @import("std");
const contracts = @import("contracts.zig");
const file_read = @import("file_read.zig");
const shell = @import("shell.zig");
const http_request = @import("http_request.zig");

pub const ToolExecutionContext = contracts.ToolExecutionContext;
pub const ToolDefinition = contracts.ToolDefinition;
pub const ToolErrorInfo = contracts.ToolErrorInfo;
pub const ToolInvokePolicy = contracts.ToolInvokePolicy;

pub const ToolRegistry = struct {
    allocator: std.mem.Allocator,
    definitions: std.ArrayListUnmanaged(ToolDefinition) = .empty,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        self.definitions.deinit(self.allocator);
    }

    pub fn register(self: *Self, definition: ToolDefinition) anyerror!void {
        if (self.find(definition.id) != null) return error.DuplicateTool;
        try self.definitions.append(self.allocator, definition);
    }

    pub fn registerBuiltins(self: *Self) anyerror!void {
        try self.register(.{ .id = "echo", .description = "Return input JSON", .parameters_json = "{\"type\":\"object\"}", .handler = echoTool });
        try self.register(.{ .id = "clock", .description = "Return current timestamp", .parameters_json = "{\"type\":\"object\"}", .handler = clockTool });
        try self.register(.{ .id = "file_read", .description = "Read a local file", .required_authority = .operator, .risk_level = .medium, .parameters_json = "{\"type\":\"object\",\"required\":[\"path\"]}", .required_fields = &.{"path"}, .handler = file_read.execute });
        try self.register(.{ .id = "shell", .description = "Execute a shell command", .required_authority = .admin, .risk_level = .high, .parameters_json = "{\"type\":\"object\",\"required\":[\"command\"]}", .required_fields = &.{"command"}, .handler = shell.execute });
        try self.register(.{ .id = "http_request", .description = "Perform an HTTP request", .required_authority = .operator, .risk_level = .medium, .parameters_json = "{\"type\":\"object\",\"required\":[\"url\"]}", .required_fields = &.{"url"}, .handler = http_request.execute });
    }

    pub fn find(self: *const Self, id: []const u8) ?ToolDefinition {
        for (self.definitions.items) |definition| {
            if (std.mem.eql(u8, definition.id, id)) return definition;
        }
        return null;
    }

    pub fn count(self: *const Self) usize {
        return self.definitions.items.len;
    }

    pub fn invoke(self: *const Self, allocator: std.mem.Allocator, id: []const u8, input_json: []const u8) anyerror![]u8 {
        return self.invokeWithPolicy(allocator, id, input_json, .{});
    }

    pub fn invokeWithPolicy(self: *const Self, allocator: std.mem.Allocator, id: []const u8, input_json: []const u8, policy: ToolInvokePolicy) anyerror![]u8 {
        const definition = self.find(id) orelse return error.ToolNotFound;
        if (definition.risk_level == .high and !policy.confirm_risk) return error.ToolRiskConfirmationRequired;
        if (policy.cancel_requested) |signal| {
            if (signal.load(.acquire)) return error.StreamCancelled;
        }
        try validateInput(definition, input_json);
        return definition.handler(.{ .cancel_requested = policy.cancel_requested }, allocator, input_json);
    }

    pub fn schemaJson(self: *const Self, allocator: std.mem.Allocator, id: []const u8) anyerror![]u8 {
        const definition = self.find(id) orelse return error.ToolNotFound;
        return allocator.dupe(u8, definition.parameters_json);
    }

    pub fn toolsPromptJson(self: *const Self, allocator: std.mem.Allocator) anyerror![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(allocator);
        const writer = buf.writer(allocator);
        try writer.writeByte('[');
        for (self.definitions.items, 0..) |definition, index| {
            if (index > 0) try writer.writeByte(',');
            try writer.print(
                "{{\"id\":\"{s}\",\"description\":\"{s}\",\"requiredAuthority\":\"{s}\",\"riskLevel\":\"{s}\",\"parameters\":{s}}}",
                .{ definition.id, definition.description, @tagName(definition.required_authority), definition.risk_level.asText(), definition.parameters_json },
            );
        }
        try writer.writeByte(']');
        return allocator.dupe(u8, buf.items);
    }

    pub fn mapError(err: anyerror) ToolErrorInfo {
        return switch (err) {
            error.ToolNotFound => .{ .code = "TOOL_NOT_FOUND", .message = "tool is not registered" },
            error.ToolBudgetExceeded => .{ .code = "TOOL_BUDGET_EXCEEDED", .message = "tool call budget has been exhausted" },
            error.ToolRiskConfirmationRequired => .{ .code = "TOOL_RISK_CONFIRMATION_REQUIRED", .message = "high-risk tool invocation requires explicit confirmation" },
            error.StreamCancelled => .{ .code = "TOOL_CANCELLED", .message = "tool execution was cancelled" },
            error.ToolValidationFailed => .{ .code = "TOOL_VALIDATION_FAILED", .message = "tool input does not match schema" },
            error.MissingPath, error.MissingCommand, error.MissingUrl => .{ .code = "TOOL_VALIDATION_FAILED", .message = "tool input is missing required fields" },
            error.PathTraversalNotAllowed, error.InvalidUrlScheme => .{ .code = "TOOL_POLICY_DENIED", .message = "tool input violates security policy" },
            else => .{ .code = "TOOL_EXECUTION_FAILED", .message = "tool execution failed" },
        };
    }
};

fn validateInput(definition: ToolDefinition, input_json: []const u8) anyerror!void {
    for (definition.required_fields) |field| {
        if (!hasJsonStringField(input_json, field)) {
            return error.ToolValidationFailed;
        }
    }
}

fn hasJsonStringField(input_json: []const u8, key: []const u8) bool {
    var buf: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&buf, "\"{s}\":", .{key}) catch return false;
    return std.mem.indexOf(u8, input_json, needle) != null;
}

fn echoTool(_: ToolExecutionContext, allocator: std.mem.Allocator, input_json: []const u8) anyerror![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"tool\":\"echo\",\"input\":{s}}}", .{input_json});
}

fn clockTool(_: ToolExecutionContext, allocator: std.mem.Allocator, _: []const u8) anyerror![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"tool\":\"clock\",\"tsUnixMs\":{d}}}", .{std.time.milliTimestamp()});
}

test "tool registry registers and invokes builtins" {
    var registry = ToolRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerBuiltins();
    const result = try registry.invoke(std.testing.allocator, "echo", "{\"message\":\"hello\"}");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 5), registry.count());
    try std.testing.expect(std.mem.indexOf(u8, result, "\"tool\":\"echo\"") != null);
}

test "tool registry exposes schema and maps validation errors" {
    var registry = ToolRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerBuiltins();

    const schema = try registry.schemaJson(std.testing.allocator, "shell");
    defer std.testing.allocator.free(schema);
    try std.testing.expect(std.mem.indexOf(u8, schema, "command") != null);

    try std.testing.expectError(error.ToolValidationFailed, registry.invoke(std.testing.allocator, "http_request", "{}"));
    const mapped = ToolRegistry.mapError(error.ToolValidationFailed);
    try std.testing.expectEqualStrings("TOOL_VALIDATION_FAILED", mapped.code);

    const tools_prompt = try registry.toolsPromptJson(std.testing.allocator);
    defer std.testing.allocator.free(tools_prompt);
    try std.testing.expect(std.mem.indexOf(u8, tools_prompt, "\"id\":\"shell\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, tools_prompt, "\"riskLevel\":\"high\"") != null);
}

test "tool registry requires confirmation for high-risk tools" {
    var registry = ToolRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerBuiltins();

    try std.testing.expectError(error.ToolRiskConfirmationRequired, registry.invoke(std.testing.allocator, "shell", "{\"command\":\"echo hello\"}"));

    const result = try registry.invokeWithPolicy(std.testing.allocator, "shell", "{\"command\":\"echo hello\"}", .{ .confirm_risk = true });
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"tool\":\"shell\"") != null);
}

test "tool registry propagates cancel signal into tool execution" {
    var registry = ToolRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerBuiltins();

    var cancelled = std.atomic.Value(bool).init(true);
    try std.testing.expectError(error.StreamCancelled, registry.invokeWithPolicy(std.testing.allocator, "http_request", "{\"url\":\"mock://http/ok\"}", .{ .cancel_requested = &cancelled }));
}
