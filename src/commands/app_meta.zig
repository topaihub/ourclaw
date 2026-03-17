const std = @import("std");
const builtin = @import("builtin");
const framework = @import("framework");
const field_registry = @import("../config/field_registry.zig");
const services_model = @import("../domain/services.zig");
const capability_manifest = @import("../runtime/capability_manifest.zig");

const APP_NAME = "ourclaw";
const APP_VERSION = "0.1.0";

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "app.meta",
        .method = "app.meta",
        .description = "Return application metadata",
        .user_data = @ptrCast(command_services),
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const metrics = services.framework_context.metrics_observer.snapshot();
    const provider_count = services.provider_registry.count();
    const channel_count = services.channel_registry.count();
    const tool_count = services.tool_registry.count();
    const command_count = services.framework_context.command_registry.count();
    const config_field_count = field_registry.ConfigFieldRegistry.all().len;
    const config_entry_count = services.framework_context.config_store.count();
    const secret_count = services.secret_store.count();
    const session_count = services.session_store.count();
    const log_entry_count = services.framework_context.memory_sink.count();
    const observer_event_count = services.framework_context.memory_observer.count();
    const event_count = services.framework_context.event_bus.count();
    const subscription_count = services.framework_context.event_bus.subscriptionCount();
    const task_count = services.framework_context.task_runner.count();
    const queued_tasks = services.framework_context.task_runner.countByState(.queued);
    const running_tasks = services.framework_context.task_runner.countByState(.running);
    const completed_tasks =
        services.framework_context.task_runner.countByState(.succeeded) +
        services.framework_context.task_runner.countByState(.failed) +
        services.framework_context.task_runner.countByState(.cancelled);

    const registries_ready = provider_count > 0 and channel_count > 0 and tool_count > 0 and command_count > 0;
    const defaults_loaded = config_entry_count >= 5;
    const status = if (registries_ready and defaults_loaded and secret_count > 0) "ok" else "degraded";
    var built_manifest = try capability_manifest.build(ctx.allocator, services);
    defer built_manifest.deinit(ctx.allocator);
    const capabilities_json = try framework.renderCapabilityManifestJson(ctx.allocator, built_manifest.asManifest());
    defer ctx.allocator.free(capabilities_json);

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);

    try writer.writeByte('{');
    try appendStringField(writer, "appName", APP_NAME, true);
    try appendStringField(writer, "appVersion", APP_VERSION, false);

    try writer.writeAll(",\"build\":{");
    try appendStringField(writer, "mode", buildModeText(), true);
    try appendStringField(writer, "arch", @tagName(builtin.target.cpu.arch), false);
    try appendStringField(writer, "os", @tagName(builtin.target.os.tag), false);
    try writer.writeByte('}');

    try writer.writeAll(",\"runtime\":{");
    try appendUnsignedField(writer, "providerCount", provider_count, true);
    try appendUnsignedField(writer, "channelCount", channel_count, false);
    try appendUnsignedField(writer, "toolCount", tool_count, false);
    try appendUnsignedField(writer, "commandCount", command_count, false);
    try appendUnsignedField(writer, "configFieldCount", config_field_count, false);
    try appendUnsignedField(writer, "configEntryCount", config_entry_count, false);
    try appendUnsignedField(writer, "secretCount", secret_count, false);
    try appendUnsignedField(writer, "sessionCount", session_count, false);
    try appendUnsignedField(writer, "logEntryCount", log_entry_count, false);
    try appendUnsignedField(writer, "observerEventCount", observer_event_count, false);
    try appendUnsignedField(writer, "eventCount", event_count, false);
    try appendUnsignedField(writer, "subscriptionCount", subscription_count, false);
    try appendUnsignedField(writer, "taskCount", task_count, false);
    try appendUnsignedField(writer, "queuedTasks", queued_tasks, false);
    try appendUnsignedField(writer, "runningTasks", running_tasks, false);
    try appendUnsignedField(writer, "completedTasks", completed_tasks, false);
    try appendBoolField(writer, "gatewayRequirePairing", services.app_context_ptr != null and @as(*const @import("../runtime/app_context.zig").AppContext, @ptrCast(@alignCast(services.app_context_ptr.?))).effective_gateway_require_pairing, false);
    try appendUnsignedField(writer, "runtimeMaxToolRounds", if (services.app_context_ptr != null) @as(*const @import("../runtime/app_context.zig").AppContext, @ptrCast(@alignCast(services.app_context_ptr.?))).effective_runtime_max_tool_rounds else 0, false);
    try writer.writeByte('}');

    try writer.writeAll(",\"capabilities\":");
    try writer.writeAll(capabilities_json);

    try writer.writeAll(",\"health\":{");
    try appendStringField(writer, "status", status, true);
    try appendBoolField(writer, "registriesReady", registries_ready, false);
    try appendBoolField(writer, "defaultsLoaded", defaults_loaded, false);
    try appendBoolField(writer, "secretsReady", secret_count > 0, false);
    try appendBoolField(writer, "providerRegistryReady", provider_count > 0, false);
    try appendBoolField(writer, "channelRegistryReady", channel_count > 0, false);
    try appendBoolField(writer, "toolRegistryReady", tool_count > 0, false);
    try appendBoolField(writer, "commandRegistryReady", command_count > 0, false);
    try writer.writeAll(",\"metrics\":{");
    try appendUnsignedField(writer, "totalEvents", metrics.total_events, true);
    try appendUnsignedField(writer, "activeTasks", metrics.active_tasks, false);
    try appendUnsignedField(writer, "queueDepth", metrics.queue_depth, false);
    try appendUnsignedField(writer, "commandAccepted", metrics.command_accepted, false);
    try appendUnsignedField(writer, "configChanged", metrics.config_changed, false);
    try writer.writeByte('}');
    try writer.writeByte('}');

    try writer.writeByte('}');
    return ctx.allocator.dupe(u8, buf.items);
}

fn buildModeText() []const u8 {
    return switch (builtin.mode) {
        .Debug => "debug",
        .ReleaseSafe => "release-safe",
        .ReleaseFast => "release-fast",
        .ReleaseSmall => "release-small",
    };
}

fn appendStringField(writer: anytype, key: []const u8, value: []const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writeJsonString(writer, value);
}

fn appendUnsignedField(writer: anytype, key: []const u8, value: usize, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.print("{d}", .{value});
}

fn appendBoolField(writer: anytype, key: []const u8, value: bool, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.writeAll(if (value) "true" else "false");
}

fn writeJsonString(writer: anytype, value: []const u8) anyerror!void {
    try writer.writeByte('"');
    for (value) |ch| {
        switch (ch) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (ch < 32) {
                    try writer.print("\\u00{x:0>2}", .{ch});
                } else {
                    try writer.writeByte(ch);
                }
            },
        }
    }
    try writer.writeByte('"');
}

test "app meta command definition is stable" {
    var framework_context = try framework.AppContext.init(std.testing.allocator, .{});
    defer framework_context.deinit();
    var config_registry = @import("../config/field_registry.zig").ConfigFieldRegistry{};
    var secret_store = @import("../security/policy.zig").MemorySecretStore.init(std.testing.allocator);
    defer secret_store.deinit();
    var security_policy = @import("../security/policy.zig").SecurityPolicy{};
    var provider_registry = @import("../providers/root.zig").ProviderRegistry.init(std.testing.allocator);
    defer provider_registry.deinit();
    var channel_registry = @import("../channels/root.zig").ChannelRegistry.init(std.testing.allocator);
    defer channel_registry.deinit();
    var tool_registry = @import("../tools/root.zig").ToolRegistry.init(std.testing.allocator);
    defer tool_registry.deinit();
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
    var pairing_registry = @import("../runtime/pairing_registry.zig").PairingRegistry.init(std.testing.allocator);
    defer pairing_registry.deinit();
    var memory_runtime = @import("../domain/memory_runtime.zig").MemoryRuntime.init(std.testing.allocator);
    defer memory_runtime.deinit();
    var session_store = @import("../domain/session_state.zig").SessionStore.init(std.testing.allocator);
    defer session_store.deinit();
    var output = @import("../domain/stream_output.zig").StreamOutput.init(std.testing.allocator, &session_store, null, null);
    var orchestrator = @import("../domain/tool_orchestrator.zig").ToolOrchestrator.init(std.testing.allocator, &tool_registry, &output);
    var services = services_model.CommandServices{
        .app_context_ptr = null,
        .framework_context = &framework_context,
        .field_registry = &config_registry,
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
        .session_store = &session_store,
        .stream_output = &output,
        .tool_orchestrator = &orchestrator,
    };
    const def = definition(&services);
    try std.testing.expectEqualStrings("app.meta", def.method);
}
