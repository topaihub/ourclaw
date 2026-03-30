const std = @import("std");
const framework = @import("framework");
const domain = @import("../domain/root.zig");
const services_model = domain.services;
const memory_runtime = domain.memory_runtime;
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
const framework_integration = @import("../framework_integration/root.zig");

const adapters = [_][]const u8{ "cli", "bridge", "http" };

pub const BuiltCapabilityManifest = struct {
    providers: [][]const u8,
    channels: [][]const u8,
    tools: [][]const u8,
    commands: [][]const u8,
    groups: [5]framework.CapabilityGroup,
    flags: [8]framework.CapabilityFlag,

    pub fn deinit(self: *BuiltCapabilityManifest, allocator: std.mem.Allocator) void {
        allocator.free(self.providers);
        allocator.free(self.channels);
        allocator.free(self.tools);
        allocator.free(self.commands);
    }

    pub fn asManifest(self: *const BuiltCapabilityManifest) framework.CapabilityManifest {
        return .{
            .groups = self.groups[0..],
            .flags = self.flags[0..],
        };
    }
};

pub fn build(allocator: std.mem.Allocator, services: *services_model.CommandServices) anyerror!BuiltCapabilityManifest {
    var built: BuiltCapabilityManifest = .{
        .providers = try allocator.alloc([]const u8, services.provider_registry.definitions.items.len),
        .channels = try allocator.alloc([]const u8, services.channel_registry.definitions.items.len),
        .tools = try allocator.alloc([]const u8, services.tool_registry.definitions.items.len),
        .commands = try allocator.alloc([]const u8, services.framework_context.command_registry.commands.items.len),
        .groups = undefined,
        .flags = undefined,
    };
    errdefer built.deinit(allocator);

    for (services.provider_registry.definitions.items, 0..) |provider_def, index| built.providers[index] = provider_def.id;
    for (services.channel_registry.definitions.items, 0..) |channel_def, index| built.channels[index] = channel_def.id;
    for (services.tool_registry.definitions.items, 0..) |tool_def, index| built.tools[index] = tool_def.id;
    for (services.framework_context.command_registry.commands.items, 0..) |command_def, index| built.commands[index] = command_def.id;

    built.groups = .{
        .{ .key = "adapters", .items = adapters[0..] },
        .{ .key = "providers", .items = built.providers },
        .{ .key = "channels", .items = built.channels },
        .{ .key = "tools", .items = built.tools },
        .{ .key = "commands", .items = built.commands },
    };
    built.flags = .{
        .{ .key = "supportsAsyncTasks", .enabled = true },
        .{ .key = "supportsEventBus", .enabled = true },
        .{ .key = "supportsObservers", .enabled = true },
        .{ .key = "supportsConfigWrite", .enabled = true },
        .{ .key = "supportsSecrets", .enabled = true },
        .{ .key = "supportsSessionStore", .enabled = true },
        .{ .key = "supportsStreamOutput", .enabled = true },
        .{ .key = "supportsToolOrchestration", .enabled = true },
    };
    return built;
}

test "build capability manifest from command services" {
    var framework_context = try framework.AppContext.init(std.testing.allocator, .{});
    defer framework_context.deinit();
    const framework_tooling = try framework_integration.ToolingBridge.init(std.testing.allocator, &framework_context);
    defer framework_tooling.deinit();
    var field_registry = @import("../config/field_registry.zig").ConfigFieldRegistry{};
    var secret_store = @import("../security/policy.zig").MemorySecretStore.init(std.testing.allocator);
    defer secret_store.deinit();
    var security_policy = @import("../security/policy.zig").SecurityPolicy{};
    var provider_registry = @import("../providers/root.zig").ProviderRegistry.init(std.testing.allocator);
    defer provider_registry.deinit();
    try provider_registry.registerBuiltins();
    var channel_registry = @import("../channels/root.zig").ChannelRegistry.init(std.testing.allocator);
    defer channel_registry.deinit();
    try channel_registry.registerBuiltins();
    var tool_registry = @import("../tools/root.zig").ToolRegistry.init(std.testing.allocator);
    defer tool_registry.deinit();
    try tool_registry.registerBuiltins();
    var memory_runtime_ref = memory_runtime.MemoryRuntime.init(std.testing.allocator);
    defer memory_runtime_ref.deinit();
    var skill_registry = skills.SkillRegistry.init(std.testing.allocator);
    defer skill_registry.deinit();
    var skillforge_ref = skillforge.SkillForge.init(&skill_registry);
    var tunnel_runtime_ref = tunnel_runtime.TunnelRuntime.init(std.testing.allocator);
    defer tunnel_runtime_ref.deinit();
    var mcp_runtime_ref = mcp_runtime.McpRuntime.init(std.testing.allocator);
    defer mcp_runtime_ref.deinit();
    try mcp_runtime_ref.register("local", "stdio", null);
    var peripheral_registry = peripherals.PeripheralRegistry.init(std.testing.allocator);
    defer peripheral_registry.deinit();
    var hardware_registry = hardware.HardwareRegistry.init(std.testing.allocator);
    defer hardware_registry.deinit();
    var voice_runtime_ref = voice_runtime.VoiceRuntime.init(std.testing.allocator);
    defer voice_runtime_ref.deinit();
    var pairing_registry = @import("pairing_registry.zig").PairingRegistry.init(std.testing.allocator);
    defer pairing_registry.deinit();
    var channel_ingress = @import("channel_ingress.zig").ChannelIngressRuntime.init(std.testing.allocator);
    defer channel_ingress.deinit();
    var session_store = session_state.SessionStore.init(std.testing.allocator);
    defer session_store.deinit();
    var output = stream_output.StreamOutput.init(std.testing.allocator, &session_store, null, null);
    defer output.deinit();
    var orchestrator = tool_orchestrator.ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var services = services_model.CommandServices{
        .app_context_ptr = null,
        .framework_context = &framework_context,
        .framework_tooling = framework_tooling,
        .field_registry = &field_registry,
        .secret_store = &secret_store,
        .security_policy = &security_policy,
        .provider_registry = &provider_registry,
        .channel_registry = &channel_registry,
        .tool_registry = &tool_registry,
        .memory_runtime = &memory_runtime_ref,
        .skill_registry = &skill_registry,
        .skillforge = &skillforge_ref,
        .tunnel_runtime = &tunnel_runtime_ref,
        .mcp_runtime = &mcp_runtime_ref,
        .peripheral_registry = &peripheral_registry,
        .hardware_registry = &hardware_registry,
        .voice_runtime = &voice_runtime_ref,
        .pairing_registry = &pairing_registry,
        .channel_ingress = &channel_ingress,
        .session_store = &session_store,
        .stream_output = &output,
        .tool_orchestrator = &orchestrator,
    };

    try framework_context.command_registry.register(.{ .id = "app.meta", .method = "app.meta", .description = "meta", .handler = undefined });
    var built = try build(std.testing.allocator, &services);
    defer built.deinit(std.testing.allocator);

    const manifest = built.asManifest();
    try std.testing.expectEqual(@as(usize, 5), manifest.groups.len);
    try std.testing.expectEqualStrings("adapters", manifest.groups[0].key);
    try std.testing.expectEqualStrings("app.meta", built.commands[0]);
}
