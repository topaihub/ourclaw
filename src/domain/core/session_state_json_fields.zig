const std = @import("std");

pub fn cloneJsonStringField(allocator: std.mem.Allocator, payload_json: []const u8, key: []const u8) anyerror!?[]u8 {
    var pattern_buf: [64]u8 = undefined;
    const pattern = try std.fmt.bufPrint(&pattern_buf, "\"{s}\":\"", .{key});
    const start = std.mem.indexOf(u8, payload_json, pattern) orelse return null;
    const value_start = start + pattern.len;
    const suffix = payload_json[value_start..];
    const value_end_rel = std.mem.indexOfScalar(u8, suffix, '"') orelse return null;
    const cloned = try allocator.dupe(u8, suffix[0..value_end_rel]);
    return cloned;
}

pub fn parseJsonUnsignedField(payload_json: []const u8, key: []const u8) ?u64 {
    var pattern_buf: [64]u8 = undefined;
    const pattern = std.fmt.bufPrint(&pattern_buf, "\"{s}\":", .{key}) catch return null;
    const start = std.mem.indexOf(u8, payload_json, pattern) orelse return null;
    const value_start = start + pattern.len;
    const suffix = payload_json[value_start..];
    var value_end: usize = 0;
    while (value_end < suffix.len and suffix[value_end] >= '0' and suffix[value_end] <= '9') : (value_end += 1) {}
    if (value_end == 0) return null;
    return std.fmt.parseUnsigned(u64, suffix[0..value_end], 10) catch null;
}

pub fn parseJsonBoolField(payload_json: []const u8, key: []const u8) ?bool {
    var pattern_buf: [64]u8 = undefined;
    const pattern = std.fmt.bufPrint(&pattern_buf, "\"{s}\":", .{key}) catch return null;
    const start = std.mem.indexOf(u8, payload_json, pattern) orelse return null;
    const value_start = start + pattern.len;
    const suffix = payload_json[value_start..];
    if (std.mem.startsWith(u8, suffix, "true")) return true;
    if (std.mem.startsWith(u8, suffix, "false")) return false;
    return null;
}

test "session json field helpers parse common shapes" {
    const payload = "{\"providerId\":\"mock_openai\",\"allowProviderTools\":true,\"promptTokens\":12}";
    const provider_id = try cloneJsonStringField(std.testing.allocator, payload, "providerId");
    defer if (provider_id) |value| std.testing.allocator.free(value);
    try std.testing.expectEqualStrings("mock_openai", provider_id.?);
    try std.testing.expectEqual(@as(?bool, true), parseJsonBoolField(payload, "allowProviderTools"));
    try std.testing.expectEqual(@as(?u64, 12), parseJsonUnsignedField(payload, "promptTokens"));
}
