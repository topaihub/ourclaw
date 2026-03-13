const std = @import("std");

pub const MODULE_NAME = "channels";

pub const ChannelDefinition = struct {
    id: []const u8,
    transport: []const u8,
    description: []const u8,
};

pub const CliChannelSnapshot = struct {
    request_count: usize,
    live_stream_count: usize,
    last_method: ?[]const u8,
    last_session_id: ?[]const u8,
};

pub const EdgeChannelSnapshot = struct {
    request_count: usize,
    stream_count: usize,
    last_target: ?[]const u8,
    last_session_id: ?[]const u8,
};

pub const CliChannelRuntime = struct {
    allocator: std.mem.Allocator,
    request_count: usize = 0,
    live_stream_count: usize = 0,
    last_method: ?[]u8 = null,
    last_session_id: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator) CliChannelRuntime {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CliChannelRuntime) void {
        if (self.last_method) |value| self.allocator.free(value);
        if (self.last_session_id) |value| self.allocator.free(value);
    }

    pub fn recordRequest(self: *CliChannelRuntime, method: []const u8, session_id: ?[]const u8) anyerror!void {
        self.request_count += 1;
        if (self.last_method) |value| self.allocator.free(value);
        self.last_method = try self.allocator.dupe(u8, method);
        if (self.last_session_id) |value| self.allocator.free(value);
        self.last_session_id = if (session_id) |value| try self.allocator.dupe(u8, value) else null;
    }

    pub fn recordLiveStream(self: *CliChannelRuntime, session_id: ?[]const u8) anyerror!void {
        self.live_stream_count += 1;
        try self.recordRequest("agent.stream.live", session_id);
    }

    pub fn snapshot(self: *const CliChannelRuntime) CliChannelSnapshot {
        return .{
            .request_count = self.request_count,
            .live_stream_count = self.live_stream_count,
            .last_method = self.last_method,
            .last_session_id = self.last_session_id,
        };
    }
};

pub const EdgeChannelRuntime = struct {
    allocator: std.mem.Allocator,
    request_count: usize = 0,
    stream_count: usize = 0,
    last_target: ?[]u8 = null,
    last_session_id: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator) EdgeChannelRuntime {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *EdgeChannelRuntime) void {
        if (self.last_target) |value| self.allocator.free(value);
        if (self.last_session_id) |value| self.allocator.free(value);
    }

    pub fn recordRequest(self: *EdgeChannelRuntime, target: []const u8, session_id: ?[]const u8) anyerror!void {
        self.request_count += 1;
        if (self.last_target) |value| self.allocator.free(value);
        self.last_target = try self.allocator.dupe(u8, target);
        if (self.last_session_id) |value| self.allocator.free(value);
        self.last_session_id = if (session_id) |value| try self.allocator.dupe(u8, value) else null;
    }

    pub fn recordStream(self: *EdgeChannelRuntime, target: []const u8, session_id: ?[]const u8) anyerror!void {
        self.stream_count += 1;
        try self.recordRequest(target, session_id);
    }

    pub fn snapshot(self: *const EdgeChannelRuntime) EdgeChannelSnapshot {
        return .{
            .request_count = self.request_count,
            .stream_count = self.stream_count,
            .last_target = self.last_target,
            .last_session_id = self.last_session_id,
        };
    }
};

pub const ChannelRegistry = struct {
    allocator: std.mem.Allocator,
    definitions: std.ArrayListUnmanaged(ChannelDefinition) = .empty,
    cli_runtime: CliChannelRuntime,
    bridge_runtime: EdgeChannelRuntime,
    http_runtime: EdgeChannelRuntime,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .cli_runtime = CliChannelRuntime.init(allocator),
            .bridge_runtime = EdgeChannelRuntime.init(allocator),
            .http_runtime = EdgeChannelRuntime.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.cli_runtime.deinit();
        self.bridge_runtime.deinit();
        self.http_runtime.deinit();
        self.definitions.deinit(self.allocator);
    }

    pub fn register(self: *Self, definition: ChannelDefinition) anyerror!void {
        if (self.find(definition.id) != null) return error.DuplicateChannel;
        try self.definitions.append(self.allocator, definition);
    }

    pub fn registerBuiltins(self: *Self) anyerror!void {
        try self.register(.{ .id = "cli", .transport = "stdio", .description = "Local CLI adapter" });
        try self.register(.{ .id = "bridge", .transport = "json-rpc", .description = "Bridge adapter" });
        try self.register(.{ .id = "http", .transport = "http", .description = "HTTP adapter" });
    }

    pub fn find(self: *const Self, id: []const u8) ?ChannelDefinition {
        for (self.definitions.items) |definition| {
            if (std.mem.eql(u8, definition.id, id)) return definition;
        }
        return null;
    }

    pub fn count(self: *const Self) usize {
        return self.definitions.items.len;
    }

    pub fn recordCliRequest(self: *Self, method: []const u8, session_id: ?[]const u8) anyerror!void {
        try self.cli_runtime.recordRequest(method, session_id);
    }

    pub fn recordCliLiveStream(self: *Self, session_id: ?[]const u8) anyerror!void {
        try self.cli_runtime.recordLiveStream(session_id);
    }

    pub fn cliSnapshot(self: *const Self) CliChannelSnapshot {
        return self.cli_runtime.snapshot();
    }

    pub fn recordBridgeRequest(self: *Self, method: []const u8, session_id: ?[]const u8) anyerror!void {
        try self.bridge_runtime.recordRequest(method, session_id);
    }

    pub fn recordBridgeStream(self: *Self, method: []const u8, session_id: ?[]const u8) anyerror!void {
        try self.bridge_runtime.recordStream(method, session_id);
    }

    pub fn bridgeSnapshot(self: *const Self) EdgeChannelSnapshot {
        return self.bridge_runtime.snapshot();
    }

    pub fn recordHttpRequest(self: *Self, route: []const u8, session_id: ?[]const u8) anyerror!void {
        try self.http_runtime.recordRequest(route, session_id);
    }

    pub fn recordHttpStream(self: *Self, route: []const u8, session_id: ?[]const u8) anyerror!void {
        try self.http_runtime.recordStream(route, session_id);
    }

    pub fn httpSnapshot(self: *const Self) EdgeChannelSnapshot {
        return self.http_runtime.snapshot();
    }
};

test "channel registry registers builtins" {
    var registry = ChannelRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerBuiltins();
    try std.testing.expectEqual(@as(usize, 3), registry.count());
}

test "cli channel runtime records requests and session ids" {
    var registry = ChannelRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.recordCliRequest("agent.run", "sess_cli_channel");
    try registry.recordCliLiveStream("sess_cli_channel");

    const snapshot = registry.cliSnapshot();
    try std.testing.expectEqual(@as(usize, 2), snapshot.request_count);
    try std.testing.expectEqual(@as(usize, 1), snapshot.live_stream_count);
    try std.testing.expectEqualStrings("agent.stream.live", snapshot.last_method.?);
    try std.testing.expectEqualStrings("sess_cli_channel", snapshot.last_session_id.?);
}

test "bridge and http channel runtimes record targets and stream usage" {
    var registry = ChannelRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.recordBridgeRequest("config.get", null);
    try registry.recordBridgeStream("agent.stream", "sess_bridge");
    try registry.recordHttpRequest("/v1/config/get", null);
    try registry.recordHttpStream("/v1/agent/stream/sse", "sess_http");

    const bridge = registry.bridgeSnapshot();
    try std.testing.expectEqual(@as(usize, 2), bridge.request_count);
    try std.testing.expectEqual(@as(usize, 1), bridge.stream_count);
    try std.testing.expectEqualStrings("agent.stream", bridge.last_target.?);

    const http = registry.httpSnapshot();
    try std.testing.expectEqual(@as(usize, 2), http.request_count);
    try std.testing.expectEqual(@as(usize, 1), http.stream_count);
    try std.testing.expectEqualStrings("/v1/agent/stream/sse", http.last_target.?);
    try std.testing.expectEqualStrings("sess_http", http.last_session_id.?);
}
