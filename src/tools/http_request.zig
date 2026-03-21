const std = @import("std");
const http_util = @import("../compat/http_util.zig");
const tools = @import("contracts.zig");

pub fn execute(ctx: tools.ToolExecutionContext, allocator: std.mem.Allocator, input_json: []const u8) anyerror![]u8 {
    if (ctx.isCancelled()) return error.StreamCancelled;
    const url = parseRequiredStringField(input_json, "url") orelse return error.MissingUrl;
    const method = parseOptionalStringField(input_json, "method") orelse "GET";
    const body = parseOptionalStringField(input_json, "body");

    if (!std.mem.startsWith(u8, url, "http://") and !std.mem.startsWith(u8, url, "https://") and !std.mem.startsWith(u8, url, "mock://")) {
        return error.InvalidUrlScheme;
    }

    var response = try http_util.curlRequest(allocator, method, url, &.{}, body, 30, ctx.cancel_requested);
    defer response.deinit(allocator);

    const body_json = try jsonString(allocator, response.body);
    defer allocator.free(body_json);

    return std.fmt.allocPrint(
        allocator,
        "{{\"tool\":\"http_request\",\"status\":{d},\"body\":{s}}}",
        .{ response.status_code, body_json },
    );
}

fn parseRequiredStringField(json: []const u8, key: []const u8) ?[]const u8 {
    return parseOptionalStringField(json, key);
}

fn parseOptionalStringField(json: []const u8, key: []const u8) ?[]const u8 {
    var buf: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&buf, "\"{s}\":\"", .{key}) catch return null;
    const start = std.mem.indexOf(u8, json, needle) orelse return null;
    const value_start = start + needle.len;
    const value_end = std.mem.indexOfScalarPos(u8, json, value_start, '"') orelse return null;
    return json[value_start..value_end];
}

fn jsonString(allocator: std.mem.Allocator, value: []const u8) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);
    try writer.writeByte('"');
    for (value) |ch| {
        switch (ch) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(ch),
        }
    }
    try writer.writeByte('"');
    return allocator.dupe(u8, buf.items);
}

test "http request tool supports mock transport" {
    const result = try execute(.{}, std.testing.allocator, "{\"url\":\"mock://http/ok\"}");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"status\":200") != null);
}

test "http request tool honours cancellation signal" {
    var cancelled = std.atomic.Value(bool).init(true);
    try std.testing.expectError(error.StreamCancelled, execute(.{ .cancel_requested = &cancelled }, std.testing.allocator, "{\"url\":\"mock://http/cancel_wait\"}"));
}
