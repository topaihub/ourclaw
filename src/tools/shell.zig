const std = @import("std");
const builtin = @import("builtin");
const tools = @import("contracts.zig");

pub fn execute(ctx: tools.ToolExecutionContext, allocator: std.mem.Allocator, input_json: []const u8) anyerror![]u8 {
    if (ctx.isCancelled()) return error.StreamCancelled;
    const command = parseRequiredStringField(input_json, "command") orelse return error.MissingCommand;

    const argv = if (@import("builtin").os.tag == .windows)
        &.{ "cmd.exe", "/C", command }
    else
        &.{ "/bin/sh", "-lc", command };

    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    var watcher_done = std.atomic.Value(bool).init(false);
    var watcher_triggered = std.atomic.Value(bool).init(false);
    const watcher = if (ctx.cancel_requested) |signal|
        try std.Thread.spawn(.{}, cancelWatcherMain, .{ child.id, signal, &watcher_done, &watcher_triggered })
    else
        null;
    defer {
        watcher_done.store(true, .release);
        if (watcher) |thread| thread.join();
    }

    const stdout = child.stdout.?.readToEndAlloc(allocator, 128 * 1024) catch |err| {
        if (watcher_triggered.load(.acquire)) return error.StreamCancelled;
        return err;
    };
    defer allocator.free(stdout);
    const stderr = child.stderr.?.readToEndAlloc(allocator, 128 * 1024) catch |err| {
        if (watcher_triggered.load(.acquire)) return error.StreamCancelled;
        return err;
    };
    defer allocator.free(stderr);
    const term = child.wait() catch |err| {
        if (watcher_triggered.load(.acquire)) return error.StreamCancelled;
        return err;
    };
    if (watcher_triggered.load(.acquire) or ctx.isCancelled()) return error.StreamCancelled;

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
    const result = try execute(.{}, std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"tool\":\"shell\"") != null);
}

test "shell tool honours cancellation signal during execution" {
    var cancelled = std.atomic.Value(bool).init(false);
    const worker = try std.Thread.spawn(.{}, triggerCancelLater, .{&cancelled});
    defer worker.join();

    const command = if (builtin.os.tag == .windows)
        "ping -n 3 127.0.0.1 >nul"
    else
        "sleep 1";
    const input = try std.fmt.allocPrint(std.testing.allocator, "{{\"command\":\"{s}\"}}", .{command});
    defer std.testing.allocator.free(input);

    try std.testing.expectError(error.StreamCancelled, execute(.{ .cancel_requested = &cancelled }, std.testing.allocator, input));
}

fn triggerCancelLater(cancelled: *std.atomic.Value(bool)) void {
    std.Thread.sleep(30 * std.time.ns_per_ms);
    cancelled.store(true, .release);
}

fn cancelWatcherMain(
    child_id: std.process.Child.Id,
    cancel_requested: *const std.atomic.Value(bool),
    done: *std.atomic.Value(bool),
    triggered: *std.atomic.Value(bool),
) void {
    while (!done.load(.acquire)) {
        if (cancel_requested.load(.acquire)) {
            triggered.store(true, .release);
            terminateChild(child_id);
            return;
        }
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }
}

fn terminateChild(child_id: std.process.Child.Id) void {
    switch (builtin.os.tag) {
        .windows => std.os.windows.TerminateProcess(child_id, 1) catch {},
        .wasi => {},
        else => std.posix.kill(child_id, std.posix.SIG.TERM) catch {},
    }
}
