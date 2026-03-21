const std = @import("std");
const contracts = @import("contracts.zig");
const ingress_runtime = @import("ingress_runtime.zig");
const snapshots = @import("snapshots.zig");

pub const ChannelDefinition = contracts.ChannelDefinition;
pub const CliChannelSnapshot = snapshots.CliChannelSnapshot;
pub const EdgeChannelSnapshot = snapshots.EdgeChannelSnapshot;
pub const CliChannelRuntime = ingress_runtime.CliChannelRuntime;
pub const EdgeChannelRuntime = ingress_runtime.EdgeChannelRuntime;

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
    try std.testing.expectEqualStrings("agent", bridge.last_route_group);
    try std.testing.expectEqualStrings("active", bridge.health_state);

    const http = registry.httpSnapshot();
    try std.testing.expectEqual(@as(usize, 2), http.request_count);
    try std.testing.expectEqual(@as(usize, 1), http.stream_count);
    try std.testing.expectEqualStrings("/v1/agent/stream/sse", http.last_target.?);
    try std.testing.expectEqualStrings("agent", http.last_route_group);
    try std.testing.expectEqualStrings("active", http.health_state);
    try std.testing.expectEqualStrings("sess_http", http.last_session_id.?);
}
