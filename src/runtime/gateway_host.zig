const builtin = @import("builtin");
const std = @import("std");
const framework = @import("framework");
const stream_sink = @import("../interfaces/stream_sink.zig");
const stream_websocket = @import("../interfaces/stream_websocket.zig");

pub const GatewayStatus = struct {
    running: bool,
    bind_host: []const u8,
    bind_port: u16,
    request_count: usize,
    stream_subscriptions: usize,
    handler_attached: bool,
    last_started_ms: ?i64,
    last_stopped_ms: ?i64,
    last_error: ?[]const u8,
};

pub const GatewayResponse = struct {
    status_code: u16,
    content_type: []const u8 = "application/json",
    body: Body,

    pub const StreamingBody = struct {
        ptr: *anyopaque,
        write: *const fn (ptr: *anyopaque, sink: stream_sink.ByteSink) anyerror!void,
        deinit: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,
    };

    pub const WebSocketBody = struct {
        pub const ClientEventHandler = struct {
            ptr: *anyopaque,
            on_text: *const fn (ptr: *anyopaque, text: []const u8) anyerror!void,
            on_close: *const fn (ptr: *anyopaque, close_code: ?u16, close_reason: ?[]const u8) void,
        };

        accept_key: [28]u8,
        ptr: *anyopaque,
        write: *const fn (ptr: *anyopaque, sink: stream_sink.ByteSink) anyerror!void,
        client_events: ?ClientEventHandler = null,
        deinit: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,
    };

    pub const Body = union(enum) {
        buffered: []u8,
        streaming: StreamingBody,
        websocket: WebSocketBody,
    };

    pub fn deinit(self: GatewayResponse, allocator: std.mem.Allocator) void {
        switch (self.body) {
            .buffered => |body_json| allocator.free(body_json),
            .streaming => |streaming| streaming.deinit(streaming.ptr, allocator),
            .websocket => |websocket| websocket.deinit(websocket.ptr, allocator),
        }
    }
};

pub const RequestHandler = struct {
    ptr: *anyopaque,
    handle: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, request: GatewayRequest) anyerror!GatewayResponse,
};

pub const GatewayRequest = struct {
    request_id: []const u8,
    method: []const u8,
    route: []const u8,
    body_json: ?[]const u8 = null,
    websocket_key: ?[]const u8 = null,
    last_event_id: ?[]const u8 = null,
    authority: framework.Authority = .public,
};

pub const GatewayHost = struct {
    allocator: std.mem.Allocator,
    bind_host: []u8,
    bind_port: u16,
    running: bool = false,
    request_count: usize = 0,
    stream_subscriptions: usize = 0,
    last_started_ms: ?i64 = null,
    last_stopped_ms: ?i64 = null,
    last_error: ?[]u8 = null,
    listener_thread: ?std.Thread = null,
    stop_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    handler: ?RequestHandler = null,
    mutex: std.Thread.Mutex = .{},

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, bind_host: []const u8, bind_port: u16) anyerror!Self {
        return .{
            .allocator = allocator,
            .bind_host = try allocator.dupe(u8, bind_host),
            .bind_port = bind_port,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        self.allocator.free(self.bind_host);
        if (self.last_error) |last_error| self.allocator.free(last_error);
    }

    pub fn setHandler(self: *Self, handler: RequestHandler) void {
        self.handler = handler;
    }

    pub fn start(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.running) return;

        self.stop_requested.store(false, .release);
        self.running = true;
        self.last_started_ms = std.time.milliTimestamp();
        self.listener_thread = std.Thread.spawn(.{}, listenerMain, .{self}) catch |err| {
            self.running = false;
            self.setLastError(@errorName(err));
            return;
        };
    }

    pub fn stop(self: *Self) void {
        self.mutex.lock();
        if (!self.running and self.listener_thread == null) {
            self.mutex.unlock();
            return;
        }
        self.stop_requested.store(true, .release);
        const join_thread = self.listener_thread;
        self.listener_thread = null;
        self.running = false;
        self.last_stopped_ms = std.time.milliTimestamp();
        self.mutex.unlock();

        self.wakeListener();
        if (join_thread) |thread| thread.join();
    }

    pub fn status(self: *const Self) GatewayStatus {
        return .{
            .running = self.running,
            .bind_host = self.bind_host,
            .bind_port = self.bind_port,
            .request_count = self.request_count,
            .stream_subscriptions = self.stream_subscriptions,
            .handler_attached = self.handler != null,
            .last_started_ms = self.last_started_ms,
            .last_stopped_ms = self.last_stopped_ms,
            .last_error = self.last_error,
        };
    }

    pub fn subscribeStream(self: *Self, event_bus: framework.EventBus) anyerror!u64 {
        const subscription_id = try event_bus.subscribe(&.{"stream.output"}, event_bus.latestSeq());
        self.stream_subscriptions += 1;
        return subscription_id;
    }

    pub fn handleHttp(self: *Self, allocator: std.mem.Allocator, app: anytype, request: GatewayRequest) anyerror!GatewayResponse {
        _ = app;
        const handler = self.handler orelse return error.GatewayHandlerUnavailable;
        self.request_count += 1;
        return handler.handle(handler.ptr, allocator, request);
    }

    const WebSocketReaderState = struct {
        host: *Self,
        stream: *std.net.Stream,
        websocket: GatewayResponse.WebSocketBody,
        stop_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    };

    fn listenerMain(self: *Self) void {
        const address = std.net.Address.resolveIp(self.bind_host, self.bind_port) catch |err| {
            self.setLastError(@errorName(err));
            return;
        };
        var server = address.listen(.{ .reuse_address = true }) catch |err| {
            self.setLastError(@errorName(err));
            return;
        };
        defer server.deinit();

        while (!self.stop_requested.load(.acquire)) {
            var conn = server.accept() catch |err| {
                self.setLastError(@errorName(err));
                continue;
            };
            defer conn.stream.close();

            self.handleConnection(&conn.stream);
        }
    }

    fn handleConnection(self: *Self, stream: *std.net.Stream) void {
        var buf: [8192]u8 = undefined;
        const n = stream.read(&buf) catch return;
        if (n == 0) return;

        const raw = buf[0..n];
        const first_line_end = std.mem.indexOf(u8, raw, "\r\n") orelse return;
        const first_line = raw[0..first_line_end];
        var parts = std.mem.splitScalar(u8, first_line, ' ');
        const method = parts.next() orelse return;
        const target = parts.next() orelse return;
        const route = if (std.mem.indexOfScalar(u8, target, '?')) |index| target[0..index] else target;

        const body_json = if (std.mem.indexOf(u8, raw, "\r\n\r\n")) |index|
            std.mem.trim(u8, raw[index + 4 ..], "\r\n")
        else
            "";

        if (std.mem.eql(u8, route, "/health")) {
            self.writeHttpResponse(stream, 200, "application/json", "{\"status\":\"ok\"}") catch {};
            return;
        }
        if (std.mem.eql(u8, route, "/ready")) {
            self.writeHttpResponse(stream, 200, "application/json", "{\"ready\":true}") catch {};
            return;
        }

        const allocator = self.allocator;
        const request = GatewayRequest{
            .request_id = "gateway_listener",
            .method = method,
            .route = route,
            .body_json = if (body_json.len > 0) body_json else null,
            .websocket_key = if (std.mem.eql(u8, route, "/v1/agent/stream/ws")) headerValue(raw, "Sec-WebSocket-Key") else null,
            .last_event_id = if (std.mem.eql(u8, route, "/v1/agent/stream/sse")) headerValue(raw, "Last-Event-ID") else null,
            .authority = .admin,
        };

        const response = self.handleHttp(allocator, {}, request) catch |err| {
            self.setLastError(@errorName(err));
            self.writeHttpResponse(stream, 500, "application/json", "{\"ok\":false,\"error\":{\"code\":\"CORE_INTERNAL_ERROR\"}}") catch {};
            return;
        };
        defer response.deinit(allocator);
        switch (response.body) {
            .buffered => |response_body| {
                self.writeHttpResponse(stream, response.status_code, response.content_type, response_body) catch {};
            },
            .streaming => |streaming| {
                self.writeStreamingHeaders(stream, response.status_code, response.content_type) catch {};
                streaming.write(streaming.ptr, stream_sink.netStreamSink(stream)) catch {};
            },
            .websocket => |websocket| {
                self.writeWebSocketUpgradeHeaders(stream, websocket.accept_key) catch {};
                var reader_state = WebSocketReaderState{
                    .host = self,
                    .stream = stream,
                    .websocket = websocket,
                };
                var reader_thread: ?std.Thread = null;
                if (websocket.client_events != null) {
                    reader_thread = std.Thread.spawn(.{}, webSocketReaderMain, .{&reader_state}) catch |err| blk: {
                        self.setLastError(@errorName(err));
                        break :blk null;
                    };
                }
                defer {
                    reader_state.stop_requested.store(true, .release);
                    shutdownStreamRead(stream);
                    if (reader_thread) |thread| thread.join();
                }
                websocket.write(websocket.ptr, stream_sink.netStreamSink(stream)) catch {};
            },
        }
    }

    fn webSocketReaderMain(state: *WebSocketReaderState) void {
        const client_events = state.websocket.client_events orelse return;
        while (!state.stop_requested.load(.acquire)) {
            var frame = stream_websocket.readClientFrame(state.host.allocator, state.stream) catch |err| {
                if (state.stop_requested.load(.acquire) and isWebSocketStopError(err)) return;
                if (isWebSocketDisconnectError(err)) {
                    client_events.on_close(client_events.ptr, null, null);
                    return;
                }
                state.host.setLastError(@errorName(err));
                client_events.on_close(client_events.ptr, null, null);
                return;
            };
            defer frame.deinit(state.host.allocator);

            if (dispatchClientFrame(state.host, client_events, &frame)) {
                return;
            }
        }
    }

    fn dispatchClientFrame(host: *Self, client_events: GatewayResponse.WebSocketBody.ClientEventHandler, frame: *const stream_websocket.ClientFrame) bool {
        switch (frame.opcode) {
            0x1 => client_events.on_text(client_events.ptr, frame.payload) catch |err| {
                host.setLastError(@errorName(err));
            },
            0x8 => {
                const parsed = stream_websocket.parseClosePayload(frame.payload) catch |err| {
                    host.setLastError(@errorName(err));
                    client_events.on_close(client_events.ptr, null, null);
                    return true;
                };
                client_events.on_close(client_events.ptr, parsed.close_code, parsed.close_reason);
                return true;
            },
            else => {},
        }
        return false;
    }

    fn writeHttpResponse(self: *Self, stream: *std.net.Stream, status_code: u16, content_type: []const u8, body_json: []const u8) anyerror!void {
        _ = self;
        var buf: [4096]u8 = undefined;
        var writer = stream.writer(&buf);
        try writer.interface.print(
            "HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
            .{ statusText(status_code), content_type, body_json.len, body_json },
        );
        try writer.interface.flush();
    }

    fn writeStreamingHeaders(self: *Self, stream: *std.net.Stream, status_code: u16, content_type: []const u8) anyerror!void {
        _ = self;
        var buf: [1024]u8 = undefined;
        var writer = stream.writer(&buf);
        try writer.interface.print(
            "HTTP/1.1 {s}\r\nContent-Type: {s}\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n",
            .{ statusText(status_code), content_type },
        );
        try writer.interface.flush();
    }

    fn statusText(status_code: u16) []const u8 {
        return switch (status_code) {
            101 => "101 Switching Protocols",
            200 => "200 OK",
            202 => "202 Accepted",
            400 => "400 Bad Request",
            403 => "403 Forbidden",
            404 => "404 Not Found",
            426 => "426 Upgrade Required",
            422 => "422 Unprocessable Entity",
            500 => "500 Internal Server Error",
            503 => "503 Service Unavailable",
            504 => "504 Gateway Timeout",
            else => "200 OK",
        };
    }

    fn writeWebSocketUpgradeHeaders(self: *Self, stream: *std.net.Stream, accept_key: [28]u8) anyerror!void {
        _ = self;
        var buf: [1024]u8 = undefined;
        var writer = stream.writer(&buf);
        try writer.interface.print(
            "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n",
            .{accept_key},
        );
        try writer.interface.flush();
    }

    fn headerValue(raw: []const u8, name: []const u8) ?[]const u8 {
        const first_line_end = std.mem.indexOf(u8, raw, "\r\n") orelse return null;
        const header_end = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse raw.len;
        var lines = std.mem.splitSequence(u8, raw[first_line_end + 2 .. header_end], "\r\n");
        while (lines.next()) |line| {
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const key = std.mem.trim(u8, line[0..colon], " \t");
            if (!std.ascii.eqlIgnoreCase(key, name)) continue;
            return std.mem.trim(u8, line[colon + 1 ..], " \t");
        }
        return null;
    }

    fn wakeListener(self: *Self) void {
        const address = std.net.Address.resolveIp(self.bind_host, self.bind_port) catch return;
        const stream = std.net.tcpConnectToAddress(address) catch return;
        stream.close();
    }

    fn shutdownStreamRead(stream: *std.net.Stream) void {
        if (comptime builtin.os.tag == .windows) {
            _ = std.os.windows.ws2_32.shutdown(stream.handle, std.os.windows.ws2_32.SD_RECEIVE);
            return;
        }
        std.posix.shutdown(stream.handle, .recv) catch {};
    }

    fn isWebSocketStopError(err: anyerror) bool {
        return switch (err) {
            error.ConnectionAborted,
            error.EndOfStream,
            error.OperationAborted,
            => true,
            else => false,
        };
    }

    fn isWebSocketDisconnectError(err: anyerror) bool {
        return switch (err) {
            error.BrokenPipe,
            error.ConnectionAborted,
            error.ConnectionResetByPeer,
            error.EndOfStream,
            error.NotOpenForReading,
            error.OperationAborted,
            => true,
            else => false,
        };
    }

    fn setLastError(self: *Self, message: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.last_error) |last_error| self.allocator.free(last_error);
        self.last_error = self.allocator.dupe(u8, message) catch null;
    }
};

const TestClientEvents = struct {
    close_count: usize = 0,
    close_code: ?u16 = null,
    close_reason_len: usize = 0,
    close_reason_buf: [32]u8 = [_]u8{0} ** 32,
    text_count: usize = 0,
    text_buf: [32]u8 = [_]u8{0} ** 32,
    text_len: usize = 0,

    fn asHandler(self: *TestClientEvents) GatewayResponse.WebSocketBody.ClientEventHandler {
        return .{
            .ptr = @ptrCast(self),
            .on_text = onText,
            .on_close = onClose,
        };
    }

    fn onText(ptr: *anyopaque, text: []const u8) anyerror!void {
        const self: *TestClientEvents = @ptrCast(@alignCast(ptr));
        self.text_count += 1;
        const copy_len = @min(text.len, self.text_buf.len);
        @memcpy(self.text_buf[0..copy_len], text[0..copy_len]);
        self.text_len = copy_len;
    }

    fn onClose(ptr: *anyopaque, close_code: ?u16, close_reason: ?[]const u8) void {
        const self: *TestClientEvents = @ptrCast(@alignCast(ptr));
        self.close_count += 1;
        self.close_code = close_code;
        const reason = close_reason orelse "";
        const copy_len = @min(reason.len, self.close_reason_buf.len);
        @memcpy(self.close_reason_buf[0..copy_len], reason[0..copy_len]);
        self.close_reason_len = copy_len;
    }
};

test "gateway host forwards websocket close code and reason to callback" {
    var host = try GatewayHost.init(std.testing.allocator, "127.0.0.1", 18081);
    defer host.deinit();

    var events = TestClientEvents{};
    const handler = events.asHandler();

    var payload = [_]u8{ 0x03, 0xE9, 'b', 'y', 'e' };
    var frame = stream_websocket.ClientFrame{
        .fin = true,
        .opcode = 0x8,
        .payload = payload[0..],
    };

    try std.testing.expect(GatewayHost.dispatchClientFrame(&host, handler, &frame));
    try std.testing.expectEqual(@as(usize, 1), events.close_count);
    try std.testing.expectEqual(@as(?u16, 1001), events.close_code);
    try std.testing.expectEqualStrings("bye", events.close_reason_buf[0..events.close_reason_len]);
}

test "gateway host keeps websocket text callback behavior" {
    var host = try GatewayHost.init(std.testing.allocator, "127.0.0.1", 18082);
    defer host.deinit();

    var events = TestClientEvents{};
    const handler = events.asHandler();

    var payload = [_]u8{ 'p', 'i', 'n', 'g' };
    var frame = stream_websocket.ClientFrame{
        .fin = true,
        .opcode = 0x1,
        .payload = payload[0..],
    };

    try std.testing.expect(!GatewayHost.dispatchClientFrame(&host, handler, &frame));
    try std.testing.expectEqual(@as(usize, 1), events.text_count);
    try std.testing.expectEqualStrings("ping", events.text_buf[0..events.text_len]);
    try std.testing.expectEqual(@as(usize, 0), events.close_count);
}

test "gateway host tracks running state" {
    var host = try GatewayHost.init(std.testing.allocator, "127.0.0.1", 8080);
    defer host.deinit();
    host.start();
    try std.testing.expect(host.status().running);
    host.stop();
    try std.testing.expect(!host.status().running);
}
