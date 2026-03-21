const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

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
    var memory_runtime = @import("../domain/memory_runtime.zig").MemoryRuntime.init(std.testing.allocator);
    defer memory_runtime.deinit();
    var skill_registry = @import("../domain/skills.zig").SkillRegistry.init(std.testing.allocator);
    defer skill_registry.deinit();
    var skillforge = @import("../domain/skillforge.zig").SkillForge.init(&skill_registry);
    var tunnel_runtime = @import("../domain/tunnel_runtime.zig").TunnelRuntime.init(std.testing.allocator);
    defer tunnel_runtime.deinit();
    var mcp_runtime = @import("../domain/mcp_runtime.zig").McpRuntime.init(std.testing.allocator);
    defer mcp_runtime.deinit();
    try mcp_runtime.register("local", "stdio", null);
    var peripheral_registry = @import("../domain/peripherals.zig").PeripheralRegistry.init(std.testing.allocator);
    defer peripheral_registry.deinit();
    var hardware_registry = @import("../domain/hardware.zig").HardwareRegistry.init(std.testing.allocator);
    defer hardware_registry.deinit();
    var voice_runtime = @import("../domain/voice_runtime.zig").VoiceRuntime.init(std.testing.allocator);
    defer voice_runtime.deinit();
    var pairing_registry = @import("pairing_registry.zig").PairingRegistry.init(std.testing.allocator);
    defer pairing_registry.deinit();
    var channel_ingress = @import("channel_ingress.zig").ChannelIngressRuntime.init(std.testing.allocator);
    defer channel_ingress.deinit();
    var session_store = @import("../domain/session_state.zig").SessionStore.init(std.testing.allocator);
    defer session_store.deinit();
    var output = @import("../domain/stream_output.zig").StreamOutput.init(std.testing.allocator, &session_store, null, null);
    defer output.deinit();
    var orchestrator = @import("../domain/tool_orchestrator.zig").ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var services = services_model.CommandServices{
        .framework_context = &framework_context,
        .field_registry = &field_registry,
        .secret_store = &secret_store,
        .security_policy = &security_policy,
        .provider_registry = &provider_registry,
        .channel_registry = &channel_registry,
        .tool_registry = &tool_registry,
        .memory_runtime = &memory_runtime,
        .skill_registry = &skill_registry,
        .skillforge = &skillforge,
        .tunnel_runtime = &tunnel_runtime,
        .mcp_runtime = &mcp_runtime,
        .peripheral_registry = &peripheral_registry,
        .hardware_registry = &hardware_registry,
        .voice_runtime = &voice_runtime,
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
