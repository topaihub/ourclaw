const std = @import("std");

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
) anyerror!HttpResponse {
    return curlRequest(allocator, "POST", url, headers, body, timeout_secs);
}

pub fn curlRequest(
    allocator: std.mem.Allocator,
    method: []const u8,
    url: []const u8,
    headers: []const []const u8,
    body: ?[]const u8,
    timeout_secs: u32,
) anyerror!HttpResponse {
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

    if (body) |payload| {
        if (child.stdin) |stdin_file| {
            try stdin_file.writeAll(payload);
            stdin_file.close();
            child.stdin = null;
        }
    }

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    errdefer allocator.free(stdout);
    const term = try child.wait();
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
    var response = try curlJsonPost(std.testing.allocator, "mock://openai/chat", &.{}, "{}", 30);
    defer response.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 200), response.status_code);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "mock openai response") != null);
}
