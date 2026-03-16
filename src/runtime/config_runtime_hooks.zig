const std = @import("std");
const framework = @import("framework");
const memory_runtime = @import("../domain/memory_runtime.zig");
const providers = @import("../providers/root.zig");
const heartbeat = @import("heartbeat.zig");

pub const ConfigRuntimeHooks = struct {
    allocator: std.mem.Allocator,
    logger: *framework.Logger,
    record_sink: *framework.MemoryConfigSideEffectSink,
    post_write_sink: framework.MemoryConfigPostWriteHookSink,
    provider_registry: *providers.ProviderRegistry,
    memory_runtime: *memory_runtime.MemoryRuntime,
    heartbeat: *heartbeat.Heartbeat,

    const Self = @This();

    const side_effect_vtable = framework.ConfigSideEffect.VTable{
        .apply = applySideEffectErased,
    };

    const post_write_vtable = framework.ConfigPostWriteHook.VTable{
        .after_write = afterWriteErased,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        logger: *framework.Logger,
        record_sink: *framework.MemoryConfigSideEffectSink,
        provider_registry: *providers.ProviderRegistry,
        memory_runtime_ref: *memory_runtime.MemoryRuntime,
        hb: *heartbeat.Heartbeat,
    ) Self {
        return .{
            .allocator = allocator,
            .logger = logger,
            .record_sink = record_sink,
            .post_write_sink = framework.MemoryConfigPostWriteHookSink.init(allocator),
            .provider_registry = provider_registry,
            .memory_runtime = memory_runtime_ref,
            .heartbeat = hb,
        };
    }

    pub fn deinit(self: *Self) void {
        self.post_write_sink.deinit();
    }

    pub fn asSideEffect(self: *Self) framework.ConfigSideEffect {
        return .{ .ptr = @ptrCast(self), .vtable = &side_effect_vtable };
    }

    pub fn asPostWriteHook(self: *Self) framework.ConfigPostWriteHook {
        return .{ .ptr = @ptrCast(self), .vtable = &post_write_vtable };
    }

    pub fn postWriteCount(self: *const Self) usize {
        return self.post_write_sink.count();
    }

    fn apply(self: *Self, change: *const framework.ConfigChange) anyerror!void {
        try self.record_sink.apply(change);

        switch (change.side_effect_kind) {
            .reload_logging => try self.applyLoggingReload(change),
            .refresh_providers => try self.provider_registry.markConfigRefresh(change.path),
            .notify_runtime => try self.applyRuntimeNotification(change),
            .restart_required => self.logger.child("config").child("side_effect").warn("config change requires restart", &.{
                framework.LogField.string("path", change.path),
            }),
            .none => {},
        }
    }

    fn afterWrite(self: *Self, summary: *const framework.ConfigPostWriteSummary) anyerror!void {
        try self.post_write_sink.afterWrite(summary);
        self.heartbeat.beat();
        self.logger.child("config").child("post_write").info("config post-write hook applied", &.{
            framework.LogField.int("changed_count", @intCast(summary.changed_count)),
            framework.LogField.boolean("requires_restart", summary.requires_restart),
        });
    }

    fn applyLoggingReload(self: *Self, change: *const framework.ConfigChange) anyerror!void {
        if (std.mem.eql(u8, change.path, "logging.level")) {
            var parsed = try framework.ConfigValueParser.parseJsonValue(self.allocator, .enum_string, change.new_value_json);
            defer parsed.deinit(self.allocator);
            if (parseLogLevel(parsed.string)) |level| {
                self.logger.min_level = level;
            }
        }

        self.logger.child("config").child("side_effect").info("logging side effect applied", &.{
            framework.LogField.string("path", change.path),
        });
    }

    fn applyRuntimeNotification(self: *Self, change: *const framework.ConfigChange) anyerror!void {
        if (std.mem.eql(u8, change.path, "memory.embedding_provider")) {
            const parsed = try parseOptionalString(self.allocator, change.new_value_json);
            defer if (parsed) |value| self.allocator.free(value);
            try self.memory_runtime.setEmbeddingProvider(parsed);
        } else if (std.mem.eql(u8, change.path, "memory.embedding_model")) {
            const parsed = try parseOptionalString(self.allocator, change.new_value_json);
            defer if (parsed) |value| self.allocator.free(value);
            try self.memory_runtime.setEmbeddingModel(parsed);
        }

        self.heartbeat.beat();
    }

    fn parseLogLevel(text: []const u8) ?framework.LogLevel {
        if (std.mem.eql(u8, text, "trace")) return .trace;
        if (std.mem.eql(u8, text, "debug")) return .debug;
        if (std.mem.eql(u8, text, "info")) return .info;
        if (std.mem.eql(u8, text, "warn")) return .warn;
        if (std.mem.eql(u8, text, "error")) return .@"error";
        if (std.mem.eql(u8, text, "fatal")) return .fatal;
        if (std.mem.eql(u8, text, "silent")) return .silent;
        return null;
    }

    fn parseOptionalString(allocator: std.mem.Allocator, value_json: []const u8) anyerror!?[]u8 {
        var parsed = try framework.ConfigValueParser.parseJsonValue(allocator, .string, value_json);
        defer parsed.deinit(allocator);
        return try allocator.dupe(u8, parsed.string);
    }

    fn applySideEffectErased(ptr: *anyopaque, change: *const framework.ConfigChange) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        try self.apply(change);
    }

    fn afterWriteErased(ptr: *anyopaque, summary: *const framework.ConfigPostWriteSummary) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        try self.afterWrite(summary);
    }
};
