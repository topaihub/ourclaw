const std = @import("std");

pub const McpServer = struct {
    id: []u8,
    transport: []u8,
    registered_at_ms: i64,

    pub fn deinit(self: *McpServer, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.transport);
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

    pub fn register(self: *Self, id: []const u8, transport: []const u8) anyerror!void {
        for (self.servers.items) |server| {
            if (std.mem.eql(u8, server.id, id)) return error.DuplicateMcpServer;
        }
        try self.servers.append(self.allocator, .{
            .id = try self.allocator.dupe(u8, id),
            .transport = try self.allocator.dupe(u8, transport),
            .registered_at_ms = std.time.milliTimestamp(),
        });
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
};

test "mcp runtime registers server" {
    var runtime = McpRuntime.init(std.testing.allocator);
    defer runtime.deinit();
    try runtime.register("local", "stdio");
    try std.testing.expectEqual(@as(usize, 1), runtime.count());
}
