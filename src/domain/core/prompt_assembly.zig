const std = @import("std");
const framework = @import("framework");
const providers = @import("../../providers/root.zig");
const tools = @import("../../tools/root.zig");

pub const Authority = framework.Authority;
pub const ProviderMessage = providers.ProviderMessage;
pub const ProviderRole = providers.ProviderRole;
pub const ToolRegistry = tools.ToolRegistry;

pub const PromptProfile = enum {
    default,
    concise_operator,
    support_triage,
};

pub const ResponseMode = enum {
    standard,
    terse,
    diagnostic,
};

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
    profile: PromptProfile = .default,
    channel_id: []const u8 = "runtime",
    identity_label: ?[]const u8 = null,
    response_mode: ResponseMode = .standard,
    session_event_count: usize = 0,
    tool_trace_count: usize = 0,
    max_tool_rounds: usize = 4,
    tool_call_budget: usize = 4,
    provider_round_budget: usize = 4,
    provider_attempt_budget: usize = 8,
    provider_retry_budget: u8 = 0,
    total_deadline_ms: u64 = 0,
    compacted_summary: ?[]const u8 = null,
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

    try messages.append(allocator, .{
        .role = .system,
        .content = try buildExecutionStrategyPrompt(allocator, input),
    });

    if (input.compacted_summary) |compacted_summary| {
        if (std.mem.trim(u8, compacted_summary, " \r\n\t").len > 0) {
            try messages.append(allocator, .{
                .role = .system,
                .content = try std.fmt.allocPrint(allocator, "Compacted Session Summary:\n{s}", .{compacted_summary}),
            });
        }
    }

    if (input.recall_summary) |recall_summary| {
        if (std.mem.trim(u8, recall_summary, " \r\n\t").len > 0) {
            try messages.append(allocator, .{
                .role = .system,
                .content = try std.fmt.allocPrint(allocator, "Recent Memory Recall:\n{s}", .{recall_summary}),
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
    const identity = input.identity_label orelse "anonymous";
    return std.fmt.allocPrint(
        allocator,
        "System Prompt:\nYou are the OurClaw runtime assistant. Profile=`{s}`. ResponseMode=`{s}`. Channel=`{s}`. Identity=`{s}`. Respect authority level `{s}`, stay within the active session `{s}`, and account for sessionEventCount={d}, toolTraceCount={d}.",
        .{ @tagName(input.profile), @tagName(input.response_mode), input.channel_id, identity, @tagName(input.authority), input.session_id, input.session_event_count, input.tool_trace_count },
    );
}

fn buildToolsPrompt(allocator: std.mem.Allocator, tool_registry: *const ToolRegistry) anyerror![]u8 {
    const tools_json = try tool_registry.toolsPromptJson(allocator);
    defer allocator.free(tools_json);
    return std.fmt.allocPrint(allocator, "Available Tools JSON:\n{s}", .{tools_json});
}

fn buildExecutionStrategyPrompt(allocator: std.mem.Allocator, input: PromptAssemblyInput) anyerror![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "Execution Strategy JSON:\n{{\"profile\":\"{s}\",\"responseMode\":\"{s}\",\"providerToolsEnabled\":{s},\"maxToolRounds\":{d},\"toolCallBudget\":{d},\"providerRoundBudget\":{d},\"providerAttemptBudget\":{d},\"providerRetryBudget\":{d},\"totalDeadlineMs\":{d}}}",
        .{
            @tagName(input.profile),
            @tagName(input.response_mode),
            if (input.allow_provider_tools) "true" else "false",
            input.max_tool_rounds,
            input.tool_call_budget,
            input.provider_round_budget,
            input.provider_attempt_budget,
            input.provider_retry_budget,
            input.total_deadline_ms,
        },
    );
}

test "prompt assembly builds system tools recall and user messages" {
    var tool_registry = tools.ToolRegistry.init(std.testing.allocator);
    defer tool_registry.deinit();
    try tool_registry.registerBuiltins();

    var result = try build(std.testing.allocator, .{
        .session_id = "sess_prompt_01",
        .user_prompt = "PROMPT_ASSEMBLY_PROBE",
        .authority = .operator,
        .profile = .concise_operator,
        .channel_id = "cli",
        .identity_label = "operator:alice",
        .response_mode = .terse,
        .session_event_count = 4,
        .tool_trace_count = 1,
        .max_tool_rounds = 1,
        .tool_call_budget = 2,
        .provider_round_budget = 3,
        .provider_attempt_budget = 5,
        .provider_retry_budget = 1,
        .total_deadline_ms = 250,
        .compacted_summary = "condensed session state",
        .recall_summary = "remember previous answer",
        .tool_result_json = "{\"tool\":\"echo\"}",
        .tool_registry = &tool_registry,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 7), result.messages.len);
    try std.testing.expectEqual(ProviderRole.system, result.messages[0].role);
    try std.testing.expect(std.mem.indexOf(u8, result.messages[0].content, "System Prompt:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.messages[0].content, "Profile=`concise_operator`") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.messages[0].content, "Identity=`operator:alice`") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.messages[1].content, "Available Tools JSON:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.messages[1].content, "\"riskLevel\":\"high\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.messages[2].content, "Execution Strategy JSON:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.messages[2].content, "\"maxToolRounds\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.messages[2].content, "\"providerToolsEnabled\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.messages[3].content, "Compacted Session Summary:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.messages[4].content, "Recent Memory Recall:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.messages[5].content, "PROMPT_ASSEMBLY_PROBE") != null);
    try std.testing.expectEqual(ProviderRole.tool, result.messages[6].role);
}
