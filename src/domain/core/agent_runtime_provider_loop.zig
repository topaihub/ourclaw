const std = @import("std");
const memory_runtime = @import("memory_runtime.zig");
const request_model = @import("agent_runtime_request.zig");
const stream_output = @import("stream_output.zig");
const tool_orchestrator = @import("tool_orchestrator.zig");

pub const MemoryRuntime = memory_runtime.MemoryRuntime;
pub const AgentRunRequest = request_model.AgentRunRequest;
pub const StreamOutput = stream_output.StreamOutput;
pub const ToolOrchestrator = tool_orchestrator.ToolOrchestrator;

pub const ToolRoundSource = enum {
    request_seed,
    provider_loop,
};

pub const ProviderLoopContext = struct {
    allocator: std.mem.Allocator,
    memory_runtime: *MemoryRuntime,
    stream_output: *StreamOutput,
    tool_orchestrator: *ToolOrchestrator,
};

pub fn roundSourceText(source: ToolRoundSource) []const u8 {
    return switch (source) {
        .request_seed => "request_seed",
        .provider_loop => "provider_loop",
    };
}

pub fn executeToolRound(
    ctx: ProviderLoopContext,
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
        ctx.allocator,
        "{{\"source\":\"{s}\",\"providerRound\":{d},\"toolRound\":{d},\"toolId\":\"{s}\",\"input\":{s}}}",
        .{ roundSourceText(source), provider_round, next_tool_round, tool_id, tool_input_json },
    );
    defer ctx.allocator.free(loop_started_payload);
    _ = try ctx.stream_output.publishWithExecution(
        request.session_id,
        request.stream_execution_id,
        "tool.loop.requested",
        loop_started_payload,
    );

    const next_tool_result = try ctx.tool_orchestrator.invokeSingle(.{
        .session_id = request.session_id,
        .execution_id = request.stream_execution_id,
        .tool_id = tool_id,
        .input_json = tool_input_json,
        .authority = request.authority,
        .confirm_risk = request.confirm_tool_risk,
        .remaining_budget = remaining_tool_budget,
        .cancel_requested = request.cancel_requested,
    });

    if (tool_id_owned.*) |owned_tool_id| ctx.allocator.free(owned_tool_id);
    tool_id_owned.* = try ctx.allocator.dupe(u8, tool_id);
    if (tool_result_json.*) |owned_tool_result| ctx.allocator.free(owned_tool_result);
    tool_result_json.* = next_tool_result;
    tool_rounds.* = next_tool_round;
    try ctx.memory_runtime.appendToolResult(request.session_id, tool_id, next_tool_result);

    const loop_completed_payload = try std.fmt.allocPrint(
        ctx.allocator,
        "{{\"source\":\"{s}\",\"providerRound\":{d},\"toolRound\":{d},\"toolId\":\"{s}\",\"result\":{s}}}",
        .{ roundSourceText(source), provider_round, next_tool_round, tool_id, next_tool_result },
    );
    defer ctx.allocator.free(loop_completed_payload);
    _ = try ctx.stream_output.publishWithExecution(
        request.session_id,
        request.stream_execution_id,
        "tool.loop.completed",
        loop_completed_payload,
    );
}
