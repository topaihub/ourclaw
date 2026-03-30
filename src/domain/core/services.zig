const framework = @import("framework");
const field_registry = @import("../../config/field_registry.zig");
const security = @import("../../security/policy.zig");
const providers = @import("../../providers/root.zig");
const channels = @import("../../channels/root.zig");
const tools = @import("../../tools/root.zig");
const session_state = @import("session_state.zig");
const memory_runtime = @import("memory_runtime.zig");
const skills = @import("../extensions/skills.zig");
const skillforge = @import("../extensions/skillforge.zig");
const tunnel_runtime = @import("../extensions/tunnel_runtime.zig");
const mcp_runtime = @import("../extensions/mcp_runtime.zig");
const peripherals = @import("../extensions/peripherals.zig");
const hardware = @import("../extensions/hardware.zig");
const voice_runtime = @import("../extensions/voice_runtime.zig");
const pairing_registry = @import("../../runtime/pairing_registry.zig");
const channel_ingress = @import("../../runtime/channel_ingress.zig");
const stream_output = @import("stream_output.zig");
const tool_orchestrator = @import("tool_orchestrator.zig");
const framework_integration = @import("../../framework_integration/root.zig");

pub const CommandServices = struct {
    app_context_ptr: ?*anyopaque = null,
    framework_context: *framework.AppContext,
    framework_tooling: *framework_integration.ToolingBridge,
    field_registry: *field_registry.ConfigFieldRegistry,
    secret_store: *security.MemorySecretStore,
    security_policy: *security.SecurityPolicy,
    provider_registry: *providers.ProviderRegistry,
    channel_registry: *channels.ChannelRegistry,
    tool_registry: *tools.ToolRegistry,
    memory_runtime: *memory_runtime.MemoryRuntime,
    skill_registry: *skills.SkillRegistry,
    skillforge: *skillforge.SkillForge,
    tunnel_runtime: *tunnel_runtime.TunnelRuntime,
    mcp_runtime: *mcp_runtime.McpRuntime,
    peripheral_registry: *peripherals.PeripheralRegistry,
    hardware_registry: *hardware.HardwareRegistry,
    voice_runtime: *voice_runtime.VoiceRuntime,
    pairing_registry: *pairing_registry.PairingRegistry,
    channel_ingress: *channel_ingress.ChannelIngressRuntime,
    session_store: *session_state.SessionStore,
    stream_output: *stream_output.StreamOutput,
    tool_orchestrator: *tool_orchestrator.ToolOrchestrator,

    pub fn fromCommandContext(ctx: *const framework.CommandContext) *CommandServices {
        return @ptrCast(@alignCast(ctx.user_data.?));
    }
};
