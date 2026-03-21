const std = @import("std");
const framework = @import("framework");
const prompt_assembly = @import("prompt_assembly.zig");

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

test "agent runtime request defaults stay stable" {
    const request: AgentRunRequest = .{ .session_id = "sess", .prompt = "hello" };
    try std.testing.expectEqualStrings("openai", request.provider_id);
    try std.testing.expectEqual(@as(usize, 4), request.max_tool_rounds);
    try std.testing.expectEqual(@as(usize, 4), request.provider_round_budget);
    try std.testing.expectEqual(@as(usize, 8), request.provider_attempt_budget);
}
