const std = @import("std");
const snapshots = @import("snapshots.zig");

pub const CliChannelSnapshot = snapshots.CliChannelSnapshot;
pub const EdgeChannelSnapshot = snapshots.EdgeChannelSnapshot;

pub const CliChannelRuntime = struct {
    allocator: std.mem.Allocator,
    request_count: usize = 0,
    live_stream_count: usize = 0,
    last_method: ?[]u8 = null,
    last_route_group: []const u8 = "idle",
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
        self.last_route_group = classifyTarget(method);
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
            .last_route_group = self.last_route_group,
            .health_state = if (self.request_count > 0 or self.live_stream_count > 0) "active" else "idle",
            .last_session_id = self.last_session_id,
        };
    }
};

pub const EdgeChannelRuntime = struct {
    allocator: std.mem.Allocator,
    request_count: usize = 0,
    stream_count: usize = 0,
    last_target: ?[]u8 = null,
    last_route_group: []const u8 = "idle",
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
        self.last_route_group = classifyTarget(target);
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
            .last_route_group = self.last_route_group,
            .health_state = if (self.request_count > 0 or self.stream_count > 0) "active" else "idle",
            .last_session_id = self.last_session_id,
        };
    }
};

fn classifyTarget(target: []const u8) []const u8 {
    if (std.mem.startsWith(u8, target, "agent.")) return "agent";
    if (std.mem.startsWith(u8, target, "config.")) return "config";
    if (std.mem.startsWith(u8, target, "session.")) return "session";
    if (std.mem.startsWith(u8, target, "memory.")) return "memory";
    if (std.mem.startsWith(u8, target, "gateway.")) return "gateway";
    if (std.mem.startsWith(u8, target, "service.")) return "service";
    if (std.mem.startsWith(u8, target, "/v1/agent/")) return "agent";
    if (std.mem.startsWith(u8, target, "/v1/config/")) return "config";
    if (std.mem.startsWith(u8, target, "/v1/session/")) return "session";
    if (std.mem.startsWith(u8, target, "/v1/memory/")) return "memory";
    if (std.mem.startsWith(u8, target, "/v1/gateway/")) return "gateway";
    if (std.mem.startsWith(u8, target, "/v1/service/")) return "service";
    return "other";
}

test "cli channel runtime records requests and session ids" {
    var cli_runtime = CliChannelRuntime.init(std.testing.allocator);
    defer cli_runtime.deinit();
    try cli_runtime.recordRequest("agent.run", "sess_cli_channel");
    try cli_runtime.recordLiveStream("sess_cli_channel");

    const snapshot = cli_runtime.snapshot();
    try std.testing.expectEqual(@as(usize, 2), snapshot.request_count);
    try std.testing.expectEqual(@as(usize, 1), snapshot.live_stream_count);
    try std.testing.expectEqualStrings("agent.stream.live", snapshot.last_method.?);
    try std.testing.expectEqualStrings("agent", snapshot.last_route_group);
    try std.testing.expectEqualStrings("active", snapshot.health_state);
    try std.testing.expectEqualStrings("sess_cli_channel", snapshot.last_session_id.?);
}

test "edge channel runtime records targets and stream usage" {
    var edge_runtime = EdgeChannelRuntime.init(std.testing.allocator);
    defer edge_runtime.deinit();
    try edge_runtime.recordRequest("config.get", null);
    try edge_runtime.recordStream("agent.stream", "sess_bridge");

    const snapshot = edge_runtime.snapshot();
    try std.testing.expectEqual(@as(usize, 2), snapshot.request_count);
    try std.testing.expectEqual(@as(usize, 1), snapshot.stream_count);
    try std.testing.expectEqualStrings("agent.stream", snapshot.last_target.?);
    try std.testing.expectEqualStrings("agent", snapshot.last_route_group);
    try std.testing.expectEqualStrings("active", snapshot.health_state);
    try std.testing.expectEqualStrings("sess_bridge", snapshot.last_session_id.?);
}
