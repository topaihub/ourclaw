const std = @import("std");
const framework = @import("framework");

pub const Authority = framework.Authority;

pub const SecretRecord = struct {
    id: []u8,
    value: []u8,

    pub fn deinit(self: *SecretRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.value);
    }
};

pub const MemorySecretStore = struct {
    allocator: std.mem.Allocator,
    secrets: std.ArrayListUnmanaged(SecretRecord) = .empty,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.secrets.items) |*secret| {
            secret.deinit(self.allocator);
        }
        self.secrets.deinit(self.allocator);
    }

    pub fn put(self: *Self, id: []const u8, value: []const u8) anyerror!void {
        if (self.findIndex(id)) |index| {
            self.allocator.free(self.secrets.items[index].value);
            self.secrets.items[index].value = try self.allocator.dupe(u8, value);
            return;
        }

        try self.secrets.append(self.allocator, .{
            .id = try self.allocator.dupe(u8, id),
            .value = try self.allocator.dupe(u8, value),
        });
    }

    pub fn get(self: *const Self, id: []const u8) ?[]const u8 {
        if (self.findIndex(id)) |index| {
            return self.secrets.items[index].value;
        }
        return null;
    }

    pub fn count(self: *const Self) usize {
        return self.secrets.items.len;
    }

    fn findIndex(self: *const Self, id: []const u8) ?usize {
        for (self.secrets.items, 0..) |secret, index| {
            if (std.mem.eql(u8, secret.id, id)) {
                return index;
            }
        }
        return null;
    }
};

pub const SecurityPolicy = struct {
    pub fn validateSecretRef(secret_ref: []const u8) bool {
        if (secret_ref.len == 0) return false;
        for (secret_ref) |ch| {
            if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-' or ch == ':')) {
                return false;
            }
        }
        return true;
    }

    pub fn canInvokeTool(authority: Authority, tool_id: []const u8) bool {
        if (std.mem.eql(u8, tool_id, "echo") or std.mem.eql(u8, tool_id, "clock")) {
            return Authority.allows(authority, .public);
        }
        if (std.mem.eql(u8, tool_id, "file_read") or std.mem.eql(u8, tool_id, "http_request")) {
            return Authority.allows(authority, .operator);
        }
        if (std.mem.eql(u8, tool_id, "shell")) {
            return Authority.allows(authority, .admin);
        }
        return Authority.allows(authority, .admin);
    }

    pub fn canUseProvider(authority: Authority, provider_id: []const u8) bool {
        if (std.mem.eql(u8, provider_id, "openai")) {
            return Authority.allows(authority, .operator);
        }
        return Authority.allows(authority, .admin);
    }
};

test "security policy validates secret refs and authority" {
    try std.testing.expect(SecurityPolicy.validateSecretRef("openai:api_key"));
    try std.testing.expect(!SecurityPolicy.validateSecretRef("../bad"));
    try std.testing.expect(SecurityPolicy.canInvokeTool(.public, "echo"));
    try std.testing.expect(!SecurityPolicy.canInvokeTool(.public, "dangerous"));
}
