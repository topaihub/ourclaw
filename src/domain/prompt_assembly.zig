const std = @import("std");
const framework = @import("framework");
const providers = @import("../providers/root.zig");
const tools = @import("../tools/root.zig");

pub const Authority = framework.Authority;
pub const ProviderMessage = providers.ProviderMessage;
pub const ProviderRole = providers.ProviderRole;
pub const ToolRegistry = tools.ToolRegistry;

pub const OwnedProviderMessage = struct {
    role: ProviderRole,
    content: []u8,

    pub fn deinit(self: *OwnedProviderMessage, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
    }

    pub fn asProviderMessage(self: *const OwnedProviderMessage) ProviderMessage {
        return .{ .role = self.role, .content = self.content };
    }
};

pub const PromptAssemblyInput = struct {
    session_id: []const u8,
    user_prompt: []const u8,
    authority: Authority,
    recall_summary: ?[]const u8 = null,
    tool_result_json: ?[]const u8 = null,
    allow_provider_tools: bool = true,
    tool_registry: ?*const ToolRegistry = null,
};

pub const PromptAssemblyResult = struct {
    messages: []OwnedProviderMessage,

    pub fn deinit(self: *PromptAssemblyResult, allocator: std.mem.Allocator) void {
        for (self.messages) |*message| message.deinit(allocator);
        allocator.free(self.messages);
    }

    pub fn asProviderMessages(self: *const PromptAssemblyResult, allocator: std.mem.Allocator) anyerror![]ProviderMessage {
        const messages = try allocator.alloc(ProviderMessage, self.messages.len);
        for (self.messages, 0..) |message, index| {
            messages[index] = message.asProviderMessage();
        }
        return messages;
    }
};

pub fn build(allocator: std.mem.Allocator, input: PromptAssemblyInput) anyerror!PromptAssemblyResult {
    var messages: std.ArrayListUnmanaged(OwnedProviderMessage) = .empty;
    errdefer {
        for (messages.items) |*message| message.deinit(allocator);
        messages.deinit(allocator);
    }

    try messages.append(allocator, .{
        .role = .system,
        .content = try buildSystemPrompt(allocator, input),
    });

    if (input.allow_provider_tools and input.tool_registry != null and input.tool_registry.?.definitions.items.len > 0) {
        try messages.append(allocator, .{
            .role = .system,
            .content = try buildToolsPrompt(allocator, input.tool_registry.?),
        });
    }

    if (input.recall_summary) |recall_summary| {
        if (std.mem.trim(u8, recall_summary, " \r\n\t").len > 0) {
            try messages.append(allocator, .{
                .role = .system,
                .content = try std.fmt.allocPrint(allocator, "Memory Recall:\n{s}", .{recall_summary}),
            });
        }
    }

    try messages.append(allocator, .{
        .role = .user,
        .content = try allocator.dupe(u8, input.user_prompt),
    });

    if (input.tool_result_json) |tool_result_json| {
        try messages.append(allocator, .{
            .role = .tool,
            .content = try std.fmt.allocPrint(allocator, "Tool Result:\n{s}", .{tool_result_json}),
        });
    }

    return .{ .messages = try messages.toOwnedSlice(allocator) };
}

fn buildSystemPrompt(allocator: std.mem.Allocator, input: PromptAssemblyInput) anyerror![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "System Prompt:\nYou are the OurClaw runtime assistant. Keep responses concise, respect authority level `{s}`, and stay within the active session `{s}`.",
        .{ @tagName(input.authority), input.session_id },
    );
}

fn buildToolsPrompt(allocator: std.mem.Allocator, tool_registry: *const ToolRegistry) anyerror![]u8 {
    const tools_json = try tool_registry.toolsPromptJson(allocator);
    defer allocator.free(tools_json);
    return std.fmt.allocPrint(allocator, "Available Tools JSON:\n{s}", .{tools_json});
}

test "prompt assembly builds system tools recall and user messages" {
    var tool_registry = tools.ToolRegistry.init(std.testing.allocator);
    defer tool_registry.deinit();
    try tool_registry.registerBuiltins();

    var result = try build(std.testing.allocator, .{
        .session_id = "sess_prompt_01",
        .user_prompt = "PROMPT_ASSEMBLY_PROBE",
        .authority = .operator,
        .recall_summary = "remember previous answer",
        .tool_result_json = "{\"tool\":\"echo\"}",
        .tool_registry = &tool_registry,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), result.messages.len);
    try std.testing.expectEqual(ProviderRole.system, result.messages[0].role);
    try std.testing.expect(std.mem.indexOf(u8, result.messages[0].content, "System Prompt:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.messages[1].content, "Available Tools JSON:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.messages[1].content, "\"riskLevel\":\"high\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.messages[3].content, "PROMPT_ASSEMBLY_PROBE") != null);
    try std.testing.expectEqual(ProviderRole.tool, result.messages[4].role);
}
