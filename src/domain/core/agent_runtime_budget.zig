const std = @import("std");
const request_model = @import("agent_runtime_request.zig");

pub const AgentRunRequest = request_model.AgentRunRequest;

pub fn ensureNotCancelled(request: AgentRunRequest) anyerror!void {
    if (request.cancel_requested) |signal| {
        if (signal.load(.acquire)) return error.StreamCancelled;
    }
}

pub fn ensureExecutionBudget(request: AgentRunRequest, started_at: i64, provider_rounds_completed: usize, remaining_tool_budget: usize) anyerror!void {
    _ = remaining_tool_budget;
    if (provider_rounds_completed >= request.provider_round_budget) return error.ProviderRoundBudgetExceeded;
    if (request.total_deadline_ms > 0) {
        const elapsed_ms: u64 = @intCast(@max(std.time.milliTimestamp() - started_at, 0));
        if (elapsed_ms >= request.total_deadline_ms) return error.ExecutionDeadlineExceeded;
    }
}

pub fn remainingProviderRounds(provider_round_budget: usize, provider_rounds_used: usize) usize {
    return if (provider_rounds_used >= provider_round_budget) 0 else provider_round_budget - provider_rounds_used;
}

test "remaining provider rounds saturates at zero" {
    try std.testing.expectEqual(@as(usize, 2), remainingProviderRounds(4, 2));
    try std.testing.expectEqual(@as(usize, 0), remainingProviderRounds(4, 4));
    try std.testing.expectEqual(@as(usize, 0), remainingProviderRounds(4, 9));
}
