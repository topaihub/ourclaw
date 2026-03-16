const std = @import("std");

pub const MODULE_NAME = "domain";

pub const memory_runtime = @import("memory_runtime.zig");
pub const services = @import("services.zig");
pub const agent_runtime = @import("agent_runtime.zig");
pub const skills = @import("skills.zig");
pub const skillforge = @import("skillforge.zig");
pub const tunnel_runtime = @import("tunnel_runtime.zig");
pub const mcp_runtime = @import("mcp_runtime.zig");
pub const peripherals = @import("peripherals.zig");
pub const hardware = @import("hardware.zig");
pub const voice_runtime = @import("voice_runtime.zig");
pub const session_state = @import("session_state.zig");
pub const stream_output = @import("stream_output.zig");
pub const tool_orchestrator = @import("tool_orchestrator.zig");
pub const prompt_assembly = @import("prompt_assembly.zig");

test "domain exports are stable" {
    try std.testing.expectEqualStrings("domain", MODULE_NAME);
    _ = session_state.SessionStore;
    _ = agent_runtime.AgentRuntime;
    _ = memory_runtime.MemoryRuntime;
    _ = skills.SkillRegistry;
}
