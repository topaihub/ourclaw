const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const memory_runtime = domain.memory_runtime;
const agent_runtime = domain.agent_runtime;
const skills = domain.skills;
const skillforge = domain.skillforge;
const tunnel_runtime = domain.tunnel_runtime;
const mcp_runtime = domain.mcp_runtime;
const peripherals = domain.peripherals;
const hardware = domain.hardware;
const voice_runtime = domain.voice_runtime;
const session_state = domain.session_state;
const stream_output = domain.stream_output;
const tool_orchestrator = domain.tool_orchestrator;
const providers = @import("../../providers/root.zig");
const tools = @import("../../tools/root.zig");
const pairing_registry = @import("../pairing_registry.zig");
const channel_ingress = @import("../channel_ingress.zig");
const stream_registry = @import("../stream_registry.zig");

pub fn initSessionStore(allocator: std.mem.Allocator) anyerror!*session_state.SessionStore {
    const session_store = try allocator.create(session_state.SessionStore);
    session_store.* = session_state.SessionStore.init(allocator);
    return session_store;
}

pub fn initSkillRegistry(allocator: std.mem.Allocator) anyerror!*skills.SkillRegistry {
    const skill_registry = try allocator.create(skills.SkillRegistry);
    skill_registry.* = skills.SkillRegistry.init(allocator);
    return skill_registry;
}

pub fn initSkillforge(allocator: std.mem.Allocator, skill_registry: *skills.SkillRegistry) anyerror!*skillforge.SkillForge {
    const skillforge_ref = try allocator.create(skillforge.SkillForge);
    skillforge_ref.* = skillforge.SkillForge.init(skill_registry);
    try skillforge_ref.installBuiltin("doctor");
    return skillforge_ref;
}

pub fn initTunnelRuntime(allocator: std.mem.Allocator) anyerror!*tunnel_runtime.TunnelRuntime {
    const runtime_ref = try allocator.create(tunnel_runtime.TunnelRuntime);
    runtime_ref.* = tunnel_runtime.TunnelRuntime.init(allocator);
    return runtime_ref;
}

pub fn initMcpRuntime(allocator: std.mem.Allocator) anyerror!*mcp_runtime.McpRuntime {
    const runtime_ref = try allocator.create(mcp_runtime.McpRuntime);
    runtime_ref.* = mcp_runtime.McpRuntime.init(allocator);
    try runtime_ref.register("local", "stdio", null);
    return runtime_ref;
}

pub fn initPeripheralRegistry(allocator: std.mem.Allocator) anyerror!*peripherals.PeripheralRegistry {
    const registry = try allocator.create(peripherals.PeripheralRegistry);
    registry.* = peripherals.PeripheralRegistry.init(allocator);
    try registry.register("camera", "video");
    return registry;
}

pub fn initHardwareRegistry(allocator: std.mem.Allocator) anyerror!*hardware.HardwareRegistry {
    const registry = try allocator.create(hardware.HardwareRegistry);
    registry.* = hardware.HardwareRegistry.init(allocator);
    try registry.register("gpu0", "Primary GPU");
    return registry;
}

pub fn initVoiceRuntime(allocator: std.mem.Allocator) anyerror!*voice_runtime.VoiceRuntime {
    const runtime_ref = try allocator.create(voice_runtime.VoiceRuntime);
    runtime_ref.* = voice_runtime.VoiceRuntime.init(allocator);
    return runtime_ref;
}

pub fn initPairingRegistry(allocator: std.mem.Allocator) anyerror!*pairing_registry.PairingRegistry {
    const registry = try allocator.create(pairing_registry.PairingRegistry);
    registry.* = pairing_registry.PairingRegistry.init(allocator);
    return registry;
}

pub fn initChannelIngress(allocator: std.mem.Allocator) anyerror!*channel_ingress.ChannelIngressRuntime {
    const runtime_ref = try allocator.create(channel_ingress.ChannelIngressRuntime);
    runtime_ref.* = channel_ingress.ChannelIngressRuntime.init(allocator);
    return runtime_ref;
}

pub fn initMemoryRuntime(allocator: std.mem.Allocator, provider_registry: *providers.ProviderRegistry) anyerror!*memory_runtime.MemoryRuntime {
    const runtime_ref = try allocator.create(memory_runtime.MemoryRuntime);
    runtime_ref.* = memory_runtime.MemoryRuntime.init(allocator);
    runtime_ref.bindProviderRegistry(provider_registry);
    return runtime_ref;
}

pub fn initStreamOutput(
    allocator: std.mem.Allocator,
    session_store: *session_state.SessionStore,
    observer: framework.Observer,
    event_bus: framework.EventBus,
) anyerror!*stream_output.StreamOutput {
    const output = try allocator.create(stream_output.StreamOutput);
    output.* = stream_output.StreamOutput.init(allocator, session_store, observer, event_bus);
    return output;
}

pub fn initToolOrchestrator(
    allocator: std.mem.Allocator,
    tool_registry: *tools.ToolRegistry,
    output: *stream_output.StreamOutput,
) anyerror!*tool_orchestrator.ToolOrchestrator {
    const orchestrator = try allocator.create(tool_orchestrator.ToolOrchestrator);
    orchestrator.* = tool_orchestrator.ToolOrchestrator.init(allocator, tool_registry, output);
    return orchestrator;
}

pub fn initAgentRuntime(
    allocator: std.mem.Allocator,
    provider_registry: *providers.ProviderRegistry,
    memory_runtime_ref: *memory_runtime.MemoryRuntime,
    session_store: *session_state.SessionStore,
    output: *stream_output.StreamOutput,
    orchestrator: *tool_orchestrator.ToolOrchestrator,
) anyerror!*agent_runtime.AgentRuntime {
    const runtime_ref = try allocator.create(agent_runtime.AgentRuntime);
    runtime_ref.* = agent_runtime.AgentRuntime.init(allocator, provider_registry, memory_runtime_ref, session_store, output, orchestrator);
    return runtime_ref;
}

pub fn initStreamRegistry(
    allocator: std.mem.Allocator,
    agent_runtime_ref: *agent_runtime.AgentRuntime,
    output: *stream_output.StreamOutput,
) anyerror!*stream_registry.StreamRegistry {
    const registry = try allocator.create(stream_registry.StreamRegistry);
    registry.* = stream_registry.StreamRegistry.init(allocator, agent_runtime_ref, output);
    return registry;
}
