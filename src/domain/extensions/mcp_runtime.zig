const std = @import("std");
const http_util = @import("../../compat/http_util.zig");

pub const McpHealthState = enum {
    ready,
    broken,

    pub fn asText(self: McpHealthState) []const u8 {
        return switch (self) {
            .ready => "ready",
            .broken => "broken",
        };
    }
};

pub const McpServer = struct {
    id: []u8,
    transport: []u8,
    endpoint: ?[]u8,
    registered_at_ms: i64,
    probe_count: usize = 0,
    last_checked_ms: ?i64 = null,
    last_connected_ms: ?i64 = null,
    last_error_code: ?[]u8 = null,
    health_state: McpHealthState = .ready,
    health_message: []const u8 = "ready",

    pub fn deinit(self: *McpServer, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.transport);
        if (self.endpoint) |value| allocator.free(value);
        if (self.last_error_code) |value| allocator.free(value);
    }
};

pub const McpRuntime = struct {
    allocator: std.mem.Allocator,
    servers: std.ArrayListUnmanaged(McpServer) = .empty,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.servers.items) |*server| server.deinit(self.allocator);
        self.servers.deinit(self.allocator);
    }

    pub fn register(self: *Self, id: []const u8, transport: []const u8, endpoint: ?[]const u8) anyerror!void {
        for (self.servers.items) |server| {
            if (std.mem.eql(u8, server.id, id)) return error.DuplicateMcpServer;
        }
        var server = McpServer{
            .id = try self.allocator.dupe(u8, id),
            .transport = try self.allocator.dupe(u8, transport),
            .endpoint = if (endpoint) |value| try self.allocator.dupe(u8, value) else null,
            .registered_at_ms = std.time.milliTimestamp(),
        };
        errdefer server.deinit(self.allocator);
        try probeServer(self.allocator, &server);
        try self.servers.append(self.allocator, .{
            .id = server.id,
            .transport = server.transport,
            .endpoint = server.endpoint,
            .registered_at_ms = server.registered_at_ms,
            .probe_count = server.probe_count,
            .last_checked_ms = server.last_checked_ms,
            .last_connected_ms = server.last_connected_ms,
            .last_error_code = server.last_error_code,
            .health_state = server.health_state,
            .health_message = server.health_message,
        });
        server.id = &.{};
        server.transport = &.{};
        server.endpoint = null;
        server.last_error_code = null;
    }

    pub fn count(self: *const Self) usize {
        return self.servers.items.len;
    }

    pub fn find(self: *const Self, id: []const u8) ?*const McpServer {
        for (self.servers.items) |*server| {
            if (std.mem.eql(u8, server.id, id)) return server;
        }
        return null;
    }

    fn probeServer(allocator: std.mem.Allocator, server: *McpServer) anyerror!void {
        server.probe_count += 1;
        server.last_checked_ms = std.time.milliTimestamp();

        if (std.mem.eql(u8, server.transport, "stdio")) {
            server.health_state = .ready;
            server.health_message = "registered_stdio";
            server.last_connected_ms = server.last_checked_ms;
            return;
        }

        const endpoint = server.endpoint orelse return markProbeFailure(allocator, server, error.McpInvalidEndpoint, "missing_endpoint");
        if (!(std.mem.eql(u8, server.transport, "http") or std.mem.eql(u8, server.transport, "sse"))) {
            return markProbeFailure(allocator, server, error.McpInvalidTransport, "invalid_transport");
        }
        if (!(std.mem.startsWith(u8, endpoint, "https://") or std.mem.startsWith(u8, endpoint, "http://") or std.mem.startsWith(u8, endpoint, "mock://mcp/"))) {
            return markProbeFailure(allocator, server, error.McpInvalidEndpoint, "invalid_endpoint");
        }
        if (std.mem.eql(u8, endpoint, "mock://mcp/down")) {
            return markProbeFailure(allocator, server, error.McpServerUnreachable, "endpoint_unreachable");
        }
        if (!std.mem.startsWith(u8, endpoint, "mock://mcp/")) {
            var response = try http_util.curlRequest(allocator, "GET", endpoint, &.{}, null, 5, null);
            defer response.deinit(allocator);
            if (response.status_code >= 500) return markProbeFailure(allocator, server, error.McpServerUnreachable, "endpoint_unreachable");
        }

        server.health_state = .ready;
        server.health_message = "endpoint_reachable";
        server.last_connected_ms = server.last_checked_ms;
    }

    fn markProbeFailure(allocator: std.mem.Allocator, server: *McpServer, err: anyerror, message: []const u8) anyerror!void {
        server.health_state = .broken;
        server.health_message = message;
        if (server.last_error_code) |value| allocator.free(value);
        server.last_error_code = try allocator.dupe(u8, @errorName(err));
        return err;
    }
};

test "mcp runtime registers server" {
    var runtime = McpRuntime.init(std.testing.allocator);
    defer runtime.deinit();
    try runtime.register("local", "stdio", null);
    try std.testing.expectEqual(@as(usize, 1), runtime.count());
}

test "mcp runtime probes http-like endpoint" {
    var runtime = McpRuntime.init(std.testing.allocator);
    defer runtime.deinit();
    try runtime.register("remote", "sse", "mock://mcp/healthy");
    const server = runtime.find("remote").?;
    try std.testing.expectEqualStrings("ready", server.health_state.asText());
    try std.testing.expect(server.last_connected_ms != null);
}

test "mcp runtime maps invalid endpoint failures" {
    var runtime = McpRuntime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(error.McpServerUnreachable, runtime.register("remote", "sse", "mock://mcp/down"));
}
