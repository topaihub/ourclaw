const std = @import("std");

pub const MODULE_NAME = "domain";

pub const memory_runtime = @import("core/memory_runtime.zig");
pub const services = @import("core/services.zig");
pub const agent_runtime = @import("core/agent_runtime.zig");
pub const skills = @import("extensions/skills.zig");
pub const skillforge = @import("extensions/skillforge.zig");
pub const tunnel_runtime = @import("extensions/tunnel_runtime.zig");
pub const mcp_runtime = @import("extensions/mcp_runtime.zig");
pub const peripherals = @import("extensions/peripherals.zig");
pub const hardware = @import("extensions/hardware.zig");
pub const voice_runtime = @import("extensions/voice_runtime.zig");
pub const session_state = @import("core/session_state.zig");
pub const stream_output = @import("core/stream_output.zig");
pub const tool_orchestrator = @import("core/tool_orchestrator.zig");
pub const prompt_assembly = @import("core/prompt_assembly.zig");

test "domain exports are stable" {
    try std.testing.expectEqualStrings("domain", MODULE_NAME);
    _ = session_state.SessionStore;
    _ = agent_runtime.AgentRuntime;
    _ = memory_runtime.MemoryRuntime;
    _ = skills.SkillRegistry;
}
