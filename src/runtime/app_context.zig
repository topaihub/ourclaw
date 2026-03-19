const std = @import("std");
const framework = @import("framework");
const commands = @import("../commands/root.zig");
const config = @import("../config/field_registry.zig");
const config_runtime = @import("../config/runtime.zig");
const security = @import("../security/policy.zig");
const providers = @import("../providers/root.zig");
const channels = @import("../channels/root.zig");
const tools = @import("../tools/root.zig");
const memory_runtime = @import("../domain/memory_runtime.zig");
const agent_runtime = @import("../domain/agent_runtime.zig");
const skills = @import("../domain/skills.zig");
const skillforge = @import("../domain/skillforge.zig");
const tunnel_runtime = @import("../domain/tunnel_runtime.zig");
const mcp_runtime = @import("../domain/mcp_runtime.zig");
const peripherals = @import("../domain/peripherals.zig");
const hardware = @import("../domain/hardware.zig");
const voice_runtime = @import("../domain/voice_runtime.zig");
const session_state = @import("../domain/session_state.zig");
const stream_output = @import("../domain/stream_output.zig");
const tool_orchestrator = @import("../domain/tool_orchestrator.zig");
const services_model = @import("../domain/services.zig");
const heartbeat = @import("heartbeat.zig");
const cron = @import("cron.zig");
const gateway_host = @import("gateway_host.zig");
const runtime_host = @import("runtime_host.zig");
const service_manager = @import("service_manager.zig");
const daemon = @import("daemon.zig");
const pairing_registry = @import("pairing_registry.zig");
const channel_ingress = @import("channel_ingress.zig");
const stream_registry = @import("stream_registry.zig");
const config_runtime_hooks = @import("config_runtime_hooks.zig");
const http_adapter = @import("../interfaces/http_adapter.zig");

pub const AppBootstrapConfig = struct {
    framework: framework.AppBootstrapConfig = .{},
    trace_log_path: ?[]const u8 = "logs/ourclaw.log",
    trace_log_max_bytes: ?u64 = 8 * 1024 * 1024,
};

pub const AppContext = struct {
    allocator: std.mem.Allocator,
    framework_context: framework.AppContext,
    trace_file_sink: ?*framework.TraceTextFileSink,
    field_registry: *config.ConfigFieldRegistry,
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
    agent_runtime: *agent_runtime.AgentRuntime,
    session_store: *session_state.SessionStore,
    stream_output: *stream_output.StreamOutput,
    stream_registry: *stream_registry.StreamRegistry,
    tool_orchestrator: *tool_orchestrator.ToolOrchestrator,
    heartbeat: *heartbeat.Heartbeat,
    cron_scheduler: *cron.CronScheduler,
    gateway_host: *gateway_host.GatewayHost,
    runtime_host: *runtime_host.RuntimeHost,
    service_manager: *service_manager.ServiceManager,
    daemon: *daemon.Daemon,
    effective_gateway_require_pairing: bool,
    effective_runtime_max_tool_rounds: usize,
    effective_gateway_remote_enabled: bool,
    effective_gateway_remote_default_endpoint: []u8,
    effective_gateway_remote_revoke_on_disable: bool,
    config_hooks: *config_runtime_hooks.ConfigRuntimeHooks,
    services: services_model.CommandServices,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, bootstrap: AppBootstrapConfig) anyerror!*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        self.effective_gateway_require_pairing = true;
        self.effective_runtime_max_tool_rounds = 4;
        self.effective_gateway_remote_enabled = true;
        self.effective_gateway_remote_default_endpoint = try allocator.dupe(u8, "mock://tunnel/healthy");
        self.effective_gateway_remote_revoke_on_disable = true;

        const field_registry = try allocator.create(config.ConfigFieldRegistry);
        errdefer allocator.destroy(field_registry);
        field_registry.* = .{};

        const secret_store = try allocator.create(security.MemorySecretStore);
        errdefer allocator.destroy(secret_store);
        secret_store.* = security.MemorySecretStore.init(allocator);

        const security_policy = try allocator.create(security.SecurityPolicy);
        errdefer allocator.destroy(security_policy);
        security_policy.* = .{};

        const provider_registry = try allocator.create(providers.ProviderRegistry);
        errdefer allocator.destroy(provider_registry);
        provider_registry.* = providers.ProviderRegistry.init(allocator);
        provider_registry.setSecretStore(secret_store);
        try provider_registry.registerBuiltins();

        const channel_registry = try allocator.create(channels.ChannelRegistry);
        errdefer allocator.destroy(channel_registry);
        channel_registry.* = channels.ChannelRegistry.init(allocator);
        try channel_registry.registerBuiltins();

        const tool_registry = try allocator.create(tools.ToolRegistry);
        errdefer allocator.destroy(tool_registry);
        tool_registry.* = tools.ToolRegistry.init(allocator);
        try tool_registry.registerBuiltins();

        const session_store = try allocator.create(session_state.SessionStore);
        errdefer allocator.destroy(session_store);
        session_store.* = session_state.SessionStore.init(allocator);

        const skill_registry = try allocator.create(skills.SkillRegistry);
        errdefer allocator.destroy(skill_registry);
        skill_registry.* = skills.SkillRegistry.init(allocator);

        const skillforge_ref = try allocator.create(skillforge.SkillForge);
        errdefer allocator.destroy(skillforge_ref);
        skillforge_ref.* = skillforge.SkillForge.init(skill_registry);
        try skillforge_ref.installBuiltin("doctor");

        const tunnel_runtime_ref = try allocator.create(tunnel_runtime.TunnelRuntime);
        errdefer allocator.destroy(tunnel_runtime_ref);
        tunnel_runtime_ref.* = tunnel_runtime.TunnelRuntime.init(allocator);

        const mcp_runtime_ref = try allocator.create(mcp_runtime.McpRuntime);
        errdefer allocator.destroy(mcp_runtime_ref);
        mcp_runtime_ref.* = mcp_runtime.McpRuntime.init(allocator);
        try mcp_runtime_ref.register("local", "stdio", null);

        const peripheral_registry = try allocator.create(peripherals.PeripheralRegistry);
        errdefer allocator.destroy(peripheral_registry);
        peripheral_registry.* = peripherals.PeripheralRegistry.init(allocator);
        try peripheral_registry.register("camera", "video");

        const hardware_registry = try allocator.create(hardware.HardwareRegistry);
        errdefer allocator.destroy(hardware_registry);
        hardware_registry.* = hardware.HardwareRegistry.init(allocator);
        try hardware_registry.register("gpu0", "Primary GPU");

        const voice_runtime_ref = try allocator.create(voice_runtime.VoiceRuntime);
        errdefer allocator.destroy(voice_runtime_ref);
        voice_runtime_ref.* = voice_runtime.VoiceRuntime.init(allocator);

        const pairing_registry_ref = try allocator.create(pairing_registry.PairingRegistry);
        errdefer allocator.destroy(pairing_registry_ref);
        pairing_registry_ref.* = pairing_registry.PairingRegistry.init(allocator);

        const channel_ingress_ref = try allocator.create(channel_ingress.ChannelIngressRuntime);
        errdefer allocator.destroy(channel_ingress_ref);
        channel_ingress_ref.* = channel_ingress.ChannelIngressRuntime.init(allocator);

        const memory_runtime_ref = try allocator.create(memory_runtime.MemoryRuntime);
        errdefer allocator.destroy(memory_runtime_ref);
        memory_runtime_ref.* = memory_runtime.MemoryRuntime.init(allocator);
        memory_runtime_ref.bindProviderRegistry(provider_registry);

        var framework_context = try framework.AppContext.init(allocator, bootstrap.framework);
        errdefer framework_context.deinit();

        // 创建 TraceTextFileSink 并替换 framework 的 logger sink
        var trace_file_sink: ?*framework.TraceTextFileSink = null;
        if (bootstrap.trace_log_path) |trace_log_path| {
            const sink = try allocator.create(framework.TraceTextFileSink);
            errdefer allocator.destroy(sink);
            sink.* = try framework.TraceTextFileSink.init(
                allocator,
                trace_log_path,
                bootstrap.trace_log_max_bytes,
                .{
                    .include_observer = false,
                    .include_runtime_dispatch = false,
                    .include_framework_method_trace = false,
                },
            );
            trace_file_sink = sink;

            // 重新创建 logger，使用 TraceTextFileSink
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
            framework_context.logger.* = framework.Logger.init(
                new_multi_sink.asLogSink(),
                bootstrap.framework.log_level,
            );
        }

        const output = try allocator.create(stream_output.StreamOutput);
        errdefer allocator.destroy(output);
        output.* = stream_output.StreamOutput.init(
            allocator,
            session_store,
            framework_context.observer(),
            framework_context.eventBus(),
        );

        const orchestrator = try allocator.create(tool_orchestrator.ToolOrchestrator);
        errdefer allocator.destroy(orchestrator);
        orchestrator.* = tool_orchestrator.ToolOrchestrator.init(allocator, tool_registry, output);

        const heartbeat_ref = try allocator.create(heartbeat.Heartbeat);
        errdefer allocator.destroy(heartbeat_ref);
        heartbeat_ref.* = heartbeat.Heartbeat.init();

        const cron_scheduler = try allocator.create(cron.CronScheduler);
        errdefer allocator.destroy(cron_scheduler);
        cron_scheduler.* = cron.CronScheduler.init(allocator);
        try cron_scheduler.registerBuiltins();

        const gateway = try allocator.create(gateway_host.GatewayHost);
        errdefer allocator.destroy(gateway);
        gateway.* = try gateway_host.GatewayHost.init(allocator, "127.0.0.1", 8080);

        const runtime_host_ref = try allocator.create(runtime_host.RuntimeHost);
        errdefer allocator.destroy(runtime_host_ref);
        runtime_host_ref.* = runtime_host.RuntimeHost.init(gateway, heartbeat_ref, cron_scheduler);

        const service_manager_ref = try allocator.create(service_manager.ServiceManager);
        errdefer allocator.destroy(service_manager_ref);
        service_manager_ref.* = service_manager.ServiceManager.init(runtime_host_ref);

        const daemon_ref = try allocator.create(daemon.Daemon);
        errdefer allocator.destroy(daemon_ref);
        daemon_ref.* = daemon.Daemon.init(service_manager_ref);

        const agent_runtime_ref = try allocator.create(agent_runtime.AgentRuntime);
        errdefer allocator.destroy(agent_runtime_ref);
        agent_runtime_ref.* = agent_runtime.AgentRuntime.init(allocator, provider_registry, memory_runtime_ref, session_store, output, orchestrator);

        const stream_registry_ref = try allocator.create(stream_registry.StreamRegistry);
        errdefer allocator.destroy(stream_registry_ref);
        stream_registry_ref.* = stream_registry.StreamRegistry.init(allocator, agent_runtime_ref, output);

        const config_hooks = try allocator.create(config_runtime_hooks.ConfigRuntimeHooks);
        errdefer allocator.destroy(config_hooks);

        self.* = .{
            .allocator = allocator,
            .framework_context = framework_context,
            .trace_file_sink = trace_file_sink,
            .field_registry = field_registry,
            .secret_store = secret_store,
            .security_policy = security_policy,
            .provider_registry = provider_registry,
            .channel_registry = channel_registry,
            .tool_registry = tool_registry,
            .memory_runtime = memory_runtime_ref,
            .skill_registry = skill_registry,
            .skillforge = skillforge_ref,
            .tunnel_runtime = tunnel_runtime_ref,
            .mcp_runtime = mcp_runtime_ref,
            .peripheral_registry = peripheral_registry,
            .hardware_registry = hardware_registry,
            .voice_runtime = voice_runtime_ref,
            .pairing_registry = pairing_registry_ref,
            .channel_ingress = channel_ingress_ref,
            .agent_runtime = agent_runtime_ref,
            .session_store = session_store,
            .stream_output = output,
            .stream_registry = stream_registry_ref,
            .tool_orchestrator = orchestrator,
            .heartbeat = heartbeat_ref,
            .cron_scheduler = cron_scheduler,
            .gateway_host = gateway,
            .runtime_host = runtime_host_ref,
            .service_manager = service_manager_ref,
            .daemon = daemon_ref,
            .effective_gateway_require_pairing = self.effective_gateway_require_pairing,
            .effective_runtime_max_tool_rounds = self.effective_runtime_max_tool_rounds,
            .effective_gateway_remote_enabled = self.effective_gateway_remote_enabled,
            .effective_gateway_remote_default_endpoint = self.effective_gateway_remote_default_endpoint,
            .effective_gateway_remote_revoke_on_disable = self.effective_gateway_remote_revoke_on_disable,
            .config_hooks = config_hooks,
            .services = undefined,
        };

        // 设置 logger 到各个运行时组件
        agent_runtime_ref.setLogger(self.framework_context.logger);
        orchestrator.setLogger(self.framework_context.logger);
        provider_registry.setLogger(self.framework_context.logger);

        config_hooks.* = config_runtime_hooks.ConfigRuntimeHooks.init(
            allocator,
            self.framework_context.logger,
            self.framework_context.config_side_effects,
            provider_registry,
            memory_runtime_ref,
            heartbeat_ref,
            &self.effective_gateway_require_pairing,
            &self.effective_runtime_max_tool_rounds,
            self.framework_context.console_sink,
            &self.framework_context.current_console_style,
        );

        self.services = .{
            .app_context_ptr = @ptrCast(self),
            .framework_context = &self.framework_context,
            .field_registry = self.field_registry,
            .secret_store = self.secret_store,
            .security_policy = self.security_policy,
            .provider_registry = self.provider_registry,
            .channel_registry = self.channel_registry,
            .tool_registry = self.tool_registry,
            .memory_runtime = self.memory_runtime,
            .skill_registry = self.skill_registry,
            .skillforge = self.skillforge,
            .tunnel_runtime = self.tunnel_runtime,
            .mcp_runtime = self.mcp_runtime,
            .peripheral_registry = self.peripheral_registry,
            .hardware_registry = self.hardware_registry,
            .voice_runtime = self.voice_runtime,
            .pairing_registry = self.pairing_registry,
            .channel_ingress = self.channel_ingress,
            .session_store = self.session_store,
            .stream_output = self.stream_output,
            .tool_orchestrator = self.tool_orchestrator,
        };

        self.gateway_host.setHandler(self.gatewayRequestHandler());

        try commands.registerBuiltins(self.framework_context.command_registry, &self.services);
        try self.bootstrapDefaults();
        try self.syncMemoryEmbeddingConfigFromStore();
        try self.syncRuntimeConfigFromStore();
        try self.secret_store.put("openai:api_key", "demo-secret");
        return self;
    }

    pub fn destroy(self: *Self) void {
        self.stream_registry.deinit();
        self.allocator.destroy(self.stream_registry);
        self.allocator.destroy(self.agent_runtime);
        self.allocator.destroy(self.tool_orchestrator);
        self.stream_output.deinit();
        self.allocator.destroy(self.stream_output);
        self.config_hooks.deinit();
        self.allocator.destroy(self.config_hooks);
        self.allocator.destroy(self.daemon);
        self.allocator.destroy(self.service_manager);
        self.allocator.destroy(self.runtime_host);
        self.gateway_host.deinit();
        self.allocator.destroy(self.gateway_host);
        self.cron_scheduler.deinit();
        self.allocator.destroy(self.cron_scheduler);
        self.allocator.destroy(self.heartbeat);
        self.hardware_registry.deinit();
        self.allocator.destroy(self.hardware_registry);
        self.peripheral_registry.deinit();
        self.allocator.destroy(self.peripheral_registry);
        self.voice_runtime.deinit();
        self.allocator.destroy(self.voice_runtime);
        self.pairing_registry.deinit();
        self.allocator.destroy(self.pairing_registry);
        self.channel_ingress.deinit();
        self.allocator.destroy(self.channel_ingress);
        self.allocator.free(self.effective_gateway_remote_default_endpoint);
        self.mcp_runtime.deinit();
        self.allocator.destroy(self.mcp_runtime);
        self.tunnel_runtime.deinit();
        self.allocator.destroy(self.tunnel_runtime);
        self.allocator.destroy(self.skillforge);
        self.skill_registry.deinit();
        self.allocator.destroy(self.skill_registry);
        self.memory_runtime.deinit();
        self.allocator.destroy(self.memory_runtime);
        self.session_store.deinit();
        self.allocator.destroy(self.session_store);
        self.tool_registry.deinit();
        self.allocator.destroy(self.tool_registry);
        self.channel_registry.deinit();
        self.allocator.destroy(self.channel_registry);
        self.provider_registry.deinit();
        self.allocator.destroy(self.provider_registry);
        self.allocator.destroy(self.security_policy);
        self.secret_store.deinit();
        self.allocator.destroy(self.secret_store);
        self.allocator.destroy(self.field_registry);
        if (self.trace_file_sink) |sink| {
            sink.deinit();
            self.allocator.destroy(sink);
        }
        self.framework_context.deinit();
        self.allocator.destroy(self);
    }

    pub fn makeDispatcher(self: *Self) framework.CommandDispatcher {
        return self.framework_context.makeDispatcher();
    }

    pub fn gatewayRequestHandler(self: *Self) gateway_host.RequestHandler {
        return .{
            .ptr = @ptrCast(self),
            .handle = handleGatewayRequest,
        };
    }

    pub fn makeConfigPipeline(
        self: *Self,
        field_definitions: ?[]const framework.FieldDefinition,
        config_rules: ?[]const framework.ConfigRule,
    ) framework.ConfigWritePipeline {
        return framework.ConfigWritePipeline.initWithDependencies(
            self.allocator,
            field_definitions orelse config.ConfigFieldRegistry.fieldDefinitions(),
            config_rules orelse config.ConfigFieldRegistry.configRules(),
            self.framework_context.config_store.asConfigStore(),
            self.framework_context.config_change_log.asChangeLog(),
            self.config_hooks.asSideEffect(),
            self.config_hooks.asPostWriteHook(),
            self.framework_context.observer(),
            self.framework_context.eventBus(),
            self.framework_context.logger,
        );
    }

    pub fn defaultConfigValueJson(self: *Self, allocator: std.mem.Allocator, path: []const u8) anyerror!?[]u8 {
        _ = self;
        return config_runtime.defaultValueJson(allocator, path);
    }

    fn bootstrapDefaults(self: *Self) anyerror!void {
        _ = try config_runtime.bootstrapDefaults(self.allocator, self.framework_context.config_store.asConfigStore());
    }

    fn syncMemoryEmbeddingConfigFromStore(self: *Self) anyerror!void {
        const provider = self.framework_context.config_store.get("memory.embedding_provider");
        if (provider) |value| {
            if (value.* == .string) {
                try self.memory_runtime.setEmbeddingProvider(value.string);
            }
        }

        const model = self.framework_context.config_store.get("memory.embedding_model");
        if (model) |value| {
            if (value.* == .string) {
                try self.memory_runtime.setEmbeddingModel(value.string);
            }
        }
    }

    fn syncRuntimeConfigFromStore(self: *Self) anyerror!void {
        const require_pairing = self.framework_context.config_store.get("gateway.require_pairing");
        if (require_pairing) |value| {
            if (value.* == .boolean) self.effective_gateway_require_pairing = value.boolean;
        }

        const max_tool_rounds = self.framework_context.config_store.get("runtime.max_tool_rounds");
        if (max_tool_rounds) |value| {
            if (value.* == .integer) self.effective_runtime_max_tool_rounds = @intCast(value.integer);
        }
    }
};

fn handleGatewayRequest(ptr: *anyopaque, allocator: std.mem.Allocator, request: gateway_host.GatewayRequest) anyerror!gateway_host.GatewayResponse {
    const self: *AppContext = @ptrCast(@alignCast(ptr));
    const owned_fields = try parseGatewayBody(allocator, request.body_json);
    defer freeValidationFields(allocator, owned_fields);

    if (std.mem.eql(u8, request.route, "/v1/agent/stream/sse")) {
        return http_adapter.handleGatewayAgentStreamSse(allocator, self, .{
            .request_id = request.request_id,
            .route = request.route,
            .params = owned_fields,
            .last_event_id = request.last_event_id,
            .authority = request.authority,
        });
    }
    if (std.mem.eql(u8, request.route, "/v1/agent/stream/ws")) {
        return http_adapter.handleGatewayAgentStreamWebSocket(allocator, self, .{
            .request_id = request.request_id,
            .route = request.route,
            .params = owned_fields,
            .websocket_key = request.websocket_key,
            .authority = request.authority,
        });
    }

    const response = try http_adapter.handle(allocator, self, .{
        .request_id = request.request_id,
        .route = request.route,
        .params = owned_fields,
        .authority = request.authority,
    });
    return .{
        .status_code = response.status_code,
        .content_type = response.content_type,
        .body = .{ .buffered = response.body_json },
    };
}

fn parseGatewayBody(allocator: std.mem.Allocator, body_json: ?[]const u8) anyerror![]framework.ValidationField {
    if (body_json == null or body_json.?.len == 0) {
        return allocator.alloc(framework.ValidationField, 0);
    }

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body_json.?, .{});
    defer parsed.deinit();

    if (parsed.value != .object) {
        return error.InvalidGatewayBody;
    }

    const object = parsed.value.object;
    const fields = try allocator.alloc(framework.ValidationField, object.count());
    errdefer allocator.free(fields);

    var iter = object.iterator();
    var index: usize = 0;
    while (iter.next()) |entry| {
        fields[index] = .{
            .key = try allocator.dupe(u8, entry.key_ptr.*),
            .value = try jsonValueToValidationValue(allocator, entry.value_ptr.*),
        };
        index += 1;
    }

    return fields;
}

fn jsonValueToValidationValue(allocator: std.mem.Allocator, value: std.json.Value) anyerror!framework.ValidationValue {
    return switch (value) {
        .null => .null,
        .bool => |flag| .{ .boolean = flag },
        .integer => |number| .{ .integer = number },
        .float => |number| .{ .float = number },
        .string => |text| .{ .string = try allocator.dupe(u8, text) },
        .array => |array| blk: {
            const items = try allocator.alloc(framework.ValidationValue, array.items.len);
            errdefer allocator.free(items);
            for (array.items, 0..) |item, index| {
                items[index] = try jsonValueToValidationValue(allocator, item);
            }
            break :blk .{ .array = items };
        },
        .object => |object| blk: {
            const fields = try allocator.alloc(framework.ValidationField, object.count());
            errdefer allocator.free(fields);
            var iter = object.iterator();
            var index: usize = 0;
            while (iter.next()) |entry| {
                fields[index] = .{
                    .key = try allocator.dupe(u8, entry.key_ptr.*),
                    .value = try jsonValueToValidationValue(allocator, entry.value_ptr.*),
                };
                index += 1;
            }
            break :blk .{ .object = fields };
        },
        else => error.UnsupportedJsonValue,
    };
}

fn freeValidationFields(allocator: std.mem.Allocator, fields: []framework.ValidationField) void {
    for (fields) |field| {
        allocator.free(field.key);
        field.value.deinit(allocator);
    }
    allocator.free(fields);
}

test "ourclaw app context initializes registries and commands" {
    var app = try AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try std.testing.expectEqual(@as(usize, 2), app.provider_registry.count());
    try std.testing.expectEqual(@as(usize, 3), app.channel_registry.count());
    try std.testing.expectEqual(@as(usize, 5), app.tool_registry.count());
    try std.testing.expectEqual(@as(usize, 1), app.skill_registry.count());
    try std.testing.expect(app.framework_context.command_registry.count() >= 30);
}
