const std = @import("std");
const framework = @import("framework");
const config = @import("../../config/field_registry.zig");
const security = @import("../../security/policy.zig");
const providers = @import("../../providers/root.zig");
const channels = @import("../../channels/root.zig");
const tools = @import("../../tools/root.zig");

pub const FrameworkSetup = struct {
    framework_context: framework.AppContext,
    trace_file_sink: ?*framework.TraceTextFileSink,

    pub fn deinit(self: *FrameworkSetup, allocator: std.mem.Allocator) void {
        if (self.trace_file_sink) |sink| {
            sink.deinit();
            allocator.destroy(sink);
        }
        self.framework_context.deinit();
    }
};

pub fn initFieldRegistry(allocator: std.mem.Allocator) anyerror!*config.ConfigFieldRegistry {
    const field_registry = try allocator.create(config.ConfigFieldRegistry);
    field_registry.* = .{};
    return field_registry;
}

pub fn initSecretStore(allocator: std.mem.Allocator) anyerror!*security.MemorySecretStore {
    const secret_store = try allocator.create(security.MemorySecretStore);
    secret_store.* = security.MemorySecretStore.init(allocator);
    return secret_store;
}

pub fn initSecurityPolicy(allocator: std.mem.Allocator) anyerror!*security.SecurityPolicy {
    const security_policy = try allocator.create(security.SecurityPolicy);
    security_policy.* = .{};
    return security_policy;
}

pub fn initProviderRegistry(allocator: std.mem.Allocator, secret_store: *security.MemorySecretStore) anyerror!*providers.ProviderRegistry {
    const provider_registry = try allocator.create(providers.ProviderRegistry);
    provider_registry.* = providers.ProviderRegistry.init(allocator);
    provider_registry.setSecretStore(secret_store);
    try provider_registry.registerBuiltins();
    return provider_registry;
}

pub fn initChannelRegistry(allocator: std.mem.Allocator) anyerror!*channels.ChannelRegistry {
    const channel_registry = try allocator.create(channels.ChannelRegistry);
    channel_registry.* = channels.ChannelRegistry.init(allocator);
    try channel_registry.registerBuiltins();
    return channel_registry;
}

pub fn initToolRegistry(allocator: std.mem.Allocator) anyerror!*tools.ToolRegistry {
    const tool_registry = try allocator.create(tools.ToolRegistry);
    tool_registry.* = tools.ToolRegistry.init(allocator);
    try tool_registry.registerBuiltins();
    return tool_registry;
}

pub fn initFrameworkSetup(
    allocator: std.mem.Allocator,
    framework_bootstrap: framework.AppBootstrapConfig,
    trace_log_path: ?[]const u8,
    trace_log_max_bytes: ?u64,
) anyerror!FrameworkSetup {
    var framework_context = try framework.AppContext.init(allocator, framework_bootstrap);
    errdefer framework_context.deinit();

    var trace_file_sink: ?*framework.TraceTextFileSink = null;
    if (trace_log_path) |path| {
        const sink = try allocator.create(framework.TraceTextFileSink);
        errdefer allocator.destroy(sink);
        sink.* = try framework.TraceTextFileSink.init(
            allocator,
            path,
            trace_log_max_bytes,
            .{
                .include_observer = false,
                .include_runtime_dispatch = false,
                .include_framework_method_trace = false,
            },
        );
        trace_file_sink = sink;

        var sinks: std.ArrayListUnmanaged(framework.LogSink) = .empty;
        defer sinks.deinit(allocator);
        try sinks.append(allocator, framework_context.memory_sink.asLogSink());
        try sinks.append(allocator, sink.asLogSink());

        if (framework_context.logger_multi_sink) |old_multi_sink| {
            old_multi_sink.deinit();
            allocator.destroy(old_multi_sink);
        }

        const new_multi_sink = try allocator.create(framework.MultiSink);
        errdefer allocator.destroy(new_multi_sink);
        new_multi_sink.* = try framework.MultiSink.init(allocator, sinks.items);
        framework_context.logger_multi_sink = new_multi_sink;

        framework_context.logger.deinit();
        framework_context.logger.* = framework.Logger.init(new_multi_sink.asLogSink(), framework_bootstrap.log_level);
    }

    return .{ .framework_context = framework_context, .trace_file_sink = trace_file_sink };
}
