const std = @import("std");

pub const ProviderModelInfo = struct {
    id: []const u8,
    label: []const u8,
    supports_streaming: bool,
    supports_tools: bool,
};

pub const ProviderHealth = struct {
    provider_id: []u8,
    healthy: bool,
    supports_streaming: bool,
    endpoint: []u8,
    message: []u8,

    pub fn deinit(self: *ProviderHealth, allocator: std.mem.Allocator) void {
        allocator.free(self.provider_id);
        allocator.free(self.endpoint);
        allocator.free(self.message);
    }
};
