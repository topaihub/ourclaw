const std = @import("std");
const builtin = @import("builtin");

pub const HttpResponse = struct {
    status_code: u16,
    body: []u8,

    pub fn deinit(self: *HttpResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};

pub fn curlJsonPost(
    allocator: std.mem.Allocator,
    url: []const u8,
    headers: []const []const u8,
    body: []const u8,
    timeout_secs: u32,
    cancel_requested: ?*const std.atomic.Value(bool),
) anyerror!HttpResponse {
    return curlRequestWithOptions(allocator, "POST", url, headers, body, timeout_secs, cancel_requested, false);
}

pub fn curlJsonPostStreaming(
    allocator: std.mem.Allocator,
    url: []const u8,
    headers: []const []const u8,
    body: []const u8,
    timeout_secs: u32,
    cancel_requested: ?*const std.atomic.Value(bool),
) anyerror!HttpResponse {
    return curlRequestWithOptions(allocator, "POST", url, headers, body, timeout_secs, cancel_requested, true);
}

pub fn curlRequest(
    allocator: std.mem.Allocator,
    method: []const u8,
    url: []const u8,
    headers: []const []const u8,
    body: ?[]const u8,
    timeout_secs: u32,
    cancel_requested: ?*const std.atomic.Value(bool),
) anyerror!HttpResponse {
    return curlRequestWithOptions(allocator, method, url, headers, body, timeout_secs, cancel_requested, false);
}

fn curlRequestWithOptions(
    allocator: std.mem.Allocator,
    method: []const u8,
    url: []const u8,
    headers: []const []const u8,
    body: ?[]const u8,
    timeout_secs: u32,
    cancel_requested: ?*const std.atomic.Value(bool),
    no_buffer: bool,
) anyerror!HttpResponse {
    if (cancel_requested) |signal| {
        if (signal.load(.acquire)) return error.StreamCancelled;
    }

    if (std.mem.eql(u8, url, "mock://openai/chat")) {
        if (body) |payload| {
            if (std.mem.indexOf(u8, payload, "PROMPT_ASSEMBLY_PROBE") != null and
                std.mem.indexOf(u8, payload, "System Prompt:") != null and
                std.mem.indexOf(u8, payload, "Available Tools JSON:") != null)
            {
                return .{
                    .status_code = 200,
                    .body = try allocator.dupe(
                        u8,
                        "{\"id\":\"chatcmpl_prompt_assembly\",\"model\":\"gpt-4o-mini\",\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"role\":\"assistant\",\"content\":\"prompt assembly ok\"}}],\"usage\":{\"prompt_tokens\":20,\"completion_tokens\":3}}",
                    ),
                };
            }

            if (std.mem.indexOf(u8, payload, "CALL_TOOL:echo") != null and std.mem.indexOf(u8, payload, "Tool Result:") == null) {
                return .{
                    .status_code = 200,
                    .body = try allocator.dupe(
                        u8,
                        "{\"id\":\"chatcmpl_mock_tool\",\"model\":\"gpt-4o-mini\",\"choices\":[{\"finish_reason\":\"tool_calls\",\"message\":{\"role\":\"assistant\",\"content\":\"\",\"tool_calls\":[{\"id\":\"call_mock_echo\",\"type\":\"function\",\"function\":{\"name\":\"echo\",\"arguments\":\"{\\\"message\\\":\\\"hello from tool\\\"}\"}}]}}],\"usage\":{\"prompt_tokens\":14,\"completion_tokens\":4}}",
                    ),
                };
            }

            if (std.mem.indexOf(u8, payload, "Tool Result:") != null) {
                return .{
                    .status_code = 200,
                    .body = try allocator.dupe(
                        u8,
                        "{\"id\":\"chatcmpl_mock_after_tool\",\"model\":\"gpt-4o-mini\",\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"role\":\"assistant\",\"content\":\"final response after tool\"}}],\"usage\":{\"prompt_tokens\":18,\"completion_tokens\":9}}",
                    ),
                };
            }
        }

        return .{
            .status_code = 200,
            .body = try allocator.dupe(
                u8,
                "{\"id\":\"chatcmpl_mock\",\"model\":\"gpt-4o-mini\",\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"role\":\"assistant\",\"content\":\"mock openai response\"}}],\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":8}}",
            ),
        };
    }

    if (std.mem.eql(u8, url, "mock://http/cancel_wait")) {
        var index: usize = 0;
        while (index < 20) : (index += 1) {
            if (cancel_requested) |signal| {
                if (signal.load(.acquire)) return error.StreamCancelled;
            }
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
        return .{
            .status_code = 200,
            .body = try allocator.dupe(u8, "{\"mock\":\"cancel_wait_completed\"}"),
        };
    }

    if (std.mem.eql(u8, url, "mock://openai/chat_stream_sse")) {
        return .{
            .status_code = 200,
            .body = try allocator.dupe(
                u8,
                "data: {\"id\":\"chatcmpl_sse_1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}\n\ndata: {\"id\":\"chatcmpl_sse_1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"mock \"},\"finish_reason\":null}]}\n\ndata: {\"id\":\"chatcmpl_sse_1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"openai \"},\"finish_reason\":null}]}\n\ndata: {\"id\":\"chatcmpl_sse_1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"response\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n",
            ),
        };
    }

    if (std.mem.startsWith(u8, url, "mock://http/")) {
        return .{
            .status_code = 200,
            .body = try std.fmt.allocPrint(allocator, "{{\"mock\":\"{s}\"}}", .{url[12..]}),
        };
    }

    var argv_buf: [48][]const u8 = undefined;
    var argc: usize = 0;
    argv_buf[argc] = "curl";
    argc += 1;
    argv_buf[argc] = "-sS";
    argc += 1;
    if (no_buffer) {
        argv_buf[argc] = "-N";
        argc += 1;
    }
    argv_buf[argc] = "-X";
    argc += 1;
    argv_buf[argc] = method;
    argc += 1;
    argv_buf[argc] = "--max-time";
    argc += 1;

    const timeout_string = try std.fmt.allocPrint(allocator, "{d}", .{timeout_secs});
    defer allocator.free(timeout_string);
    argv_buf[argc] = timeout_string;
    argc += 1;

    argv_buf[argc] = "-w";
    argc += 1;
    argv_buf[argc] = "\n__STATUS__:%{http_code}";
    argc += 1;

    for (headers) |header| {
        argv_buf[argc] = "-H";
        argc += 1;
        argv_buf[argc] = header;
        argc += 1;
    }

    if (body != null) {
        argv_buf[argc] = "--data-binary";
        argc += 1;
        argv_buf[argc] = "@-";
        argc += 1;
    }

    argv_buf[argc] = url;
    argc += 1;

    var child = std.process.Child.init(argv_buf[0..argc], allocator);
    child.stdin_behavior = if (body != null) .Pipe else .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();

    var watcher_done = std.atomic.Value(bool).init(false);
    var watcher_triggered = std.atomic.Value(bool).init(false);
    const watcher = if (cancel_requested) |signal|
        try std.Thread.spawn(.{}, cancelWatcherMain, .{ child.id, signal, &watcher_done, &watcher_triggered })
    else
        null;
    defer {
        watcher_done.store(true, .release);
        if (watcher) |thread| thread.join();
    }

    if (body) |payload| {
        if (child.stdin) |stdin_file| {
            try stdin_file.writeAll(payload);
            stdin_file.close();
            child.stdin = null;
        }
    }

    const stdout = child.stdout.?.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        if (watcher_triggered.load(.acquire)) return error.StreamCancelled;
        return err;
    };
    errdefer allocator.free(stdout);
    const term = child.wait() catch |err| {
        if (watcher_triggered.load(.acquire)) return error.StreamCancelled;
        return err;
    };
    if (watcher_triggered.load(.acquire)) {
        allocator.free(stdout);
        return error.StreamCancelled;
    }
    switch (term) {
        .Exited => |code| if (code != 0) return error.CurlFailed,
        else => return error.CurlFailed,
    }

    const marker = std.mem.lastIndexOf(u8, stdout, "\n__STATUS__:") orelse return error.InvalidHttpStatus;
    const status_slice = stdout[marker + 11 ..];
    const status_code = try std.fmt.parseInt(u16, status_slice, 10);
    const body_owned = try allocator.dupe(u8, stdout[0..marker]);
    allocator.free(stdout);

    return .{
        .status_code = status_code,
        .body = body_owned,
    };
}

test "http util returns mock openai response" {
    var response = try curlJsonPost(std.testing.allocator, "mock://openai/chat", &.{}, "{}", 30, null);
    defer response.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 200), response.status_code);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "mock openai response") != null);
}

test "http util honours cancellation signal for mock wait endpoint" {
    var cancelled = std.atomic.Value(bool).init(true);
    try std.testing.expectError(error.StreamCancelled, curlRequest(std.testing.allocator, "GET", "mock://http/cancel_wait", &.{}, null, 30, &cancelled));
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
