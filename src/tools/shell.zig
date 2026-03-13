const std = @import("std");

pub fn execute(allocator: std.mem.Allocator, input_json: []const u8) anyerror![]u8 {
    const command = parseRequiredStringField(input_json, "command") orelse return error.MissingCommand;

    const argv = if (@import("builtin").os.tag == .windows)
        &.{ "cmd.exe", "/C", command }
    else
        &.{ "/bin/sh", "-lc", command };

    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 128 * 1024);
    defer allocator.free(stdout);
    const stderr = try child.stderr.?.readToEndAlloc(allocator, 128 * 1024);
    defer allocator.free(stderr);
    const term = try child.wait();

    const exit_code: i64 = switch (term) {
        .Exited => |code| code,
        else => -1,
    };

    const stdout_json = try jsonString(allocator, stdout);
    defer allocator.free(stdout_json);
    const stderr_json = try jsonString(allocator, stderr);
    defer allocator.free(stderr_json);

    return std.fmt.allocPrint(
        allocator,
        "{{\"tool\":\"shell\",\"success\":{s},\"exitCode\":{d},\"stdout\":{s},\"stderr\":{s}}}",
        .{ if (exit_code == 0) "true" else "false", exit_code, stdout_json, stderr_json },
    );
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

test "shell tool executes command" {
    const input = "{\"command\":\"echo hello\"}";
    const result = try execute(std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"tool\":\"shell\"") != null);
}
