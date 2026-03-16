const std = @import("std");
const tools = @import("root.zig");

pub fn execute(ctx: tools.ToolExecutionContext, allocator: std.mem.Allocator, input_json: []const u8) anyerror![]u8 {
    if (ctx.isCancelled()) return error.StreamCancelled;
    const path = parseRequiredStringField(input_json, "path") orelse return error.MissingPath;
    if (hasTraversal(path)) return error.PathTraversalNotAllowed;

    const content = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(content);
    const content_json = try jsonString(allocator, content);
    defer allocator.free(content_json);

    return std.fmt.allocPrint(
        allocator,
        "{{\"tool\":\"file_read\",\"path\":\"{s}\",\"byteCount\":{d},\"content\":{s}}}",
        .{ path, content.len, content_json },
    );
}

fn hasTraversal(path: []const u8) bool {
    var parts = std.mem.splitAny(u8, path, "/\\");
    while (parts.next()) |segment| {
        if (std.mem.eql(u8, segment, "..")) return true;
    }
    return false;
}

fn parseRequiredStringField(json: []const u8, key: []const u8) ?[]const u8 {
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

test "file read tool reads local file" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    try tmp_dir.dir.writeFile(.{ .sub_path = "sample.txt", .data = "hello" });

    const root_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root_path);
    const path = try std.fs.path.join(std.testing.allocator, &.{ root_path, "sample.txt" });
    defer std.testing.allocator.free(path);
    const input = try std.fmt.allocPrint(std.testing.allocator, "{{\"path\":\"{s}\"}}", .{path});
    defer std.testing.allocator.free(input);

    const result = try execute(.{}, std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"tool\":\"file_read\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "hello") != null);
}
