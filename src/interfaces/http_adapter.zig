const std = @import("std");
const framework = @import("framework");
const runtime = @import("../runtime/app_context.zig");
const gateway_host = @import("../runtime/gateway_host.zig");
const cli = @import("cli_adapter.zig");
const stream_sink = @import("stream_sink.zig");
const stream_projection = @import("stream_projection.zig");
const stream_websocket = @import("stream_websocket.zig");

pub const HttpRequest = struct {
    request_id: []const u8,
    route: []const u8,
    params: []const framework.ValidationField,
    websocket_key: ?[]const u8 = null,
    last_event_id: ?[]const u8 = null,
    authority: framework.Authority = .public,
};

pub const HttpResponse = struct {
    status_code: u16,
    content_type: []const u8 = "application/json",
    body_json: []u8,

    pub fn deinit(self: *HttpResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.body_json);
    }
};

const GatewaySseContext = struct {
    allocator: std.mem.Allocator,
    app: *runtime.AppContext,
    request_id: []u8,
    params: []framework.ValidationField,
    authority: framework.Authority,

    fn init(allocator: std.mem.Allocator, app: *runtime.AppContext, request: HttpRequest) anyerror!*GatewaySseContext {
        const self = try allocator.create(GatewaySseContext);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .app = app,
            .request_id = try allocator.dupe(u8, request.request_id),
            .params = try cloneValidationFieldsWithOptionalStringParam(allocator, request.params, "last_event_id", request.last_event_id),
            .authority = request.authority,
        };
        return self;
    }

    fn asStreamingBody(self: *GatewaySseContext) gateway_host.GatewayResponse.StreamingBody {
        return .{
            .ptr = @ptrCast(self),
            .write = write,
            .deinit = deinitErased,
        };
    }

    fn write(ptr: *anyopaque, sink: stream_sink.ByteSink) anyerror!void {
        const self: *GatewaySseContext = @ptrCast(@alignCast(ptr));
        try stream_projection.writeSseAgentStream(self.allocator, self.app, .{
            .request_id = self.request_id,
            .params = self.params,
            .authority = self.authority,
        }, sink);
    }

    fn deinitErased(ptr: *anyopaque, allocator: std.mem.Allocator) void {
        const self: *GatewaySseContext = @ptrCast(@alignCast(ptr));
        deinitGatewayStreamContext(self.request_id, self.params, allocator, self);
    }
};

const GatewayWebSocketContext = struct {
    allocator: std.mem.Allocator,
    app: *runtime.AppContext,
    request_id: []u8,
    params: []framework.ValidationField,
    websocket_key: []u8,
    authority: framework.Authority,
    cancel_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    client_closed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    websocket_acked_seq: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    websocket_pause_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    websocket_resume_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    websocket_resume_from_seq: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    client_close_code: std.atomic.Value(u16) = std.atomic.Value(u16).init(1005),
    client_close_reason_len: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    client_close_reason_buf: [123]u8 = [_]u8{0} ** 123,

    fn init(allocator: std.mem.Allocator, app: *runtime.AppContext, request: HttpRequest) anyerror!*GatewayWebSocketContext {
        const self = try allocator.create(GatewayWebSocketContext);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .app = app,
            .request_id = try allocator.dupe(u8, request.request_id),
            .params = try cloneValidationFields(allocator, request.params),
            .websocket_key = try allocator.dupe(u8, request.websocket_key orelse return error.MissingWebSocketKey),
            .authority = request.authority,
        };
        return self;
    }

    fn asWebSocketBody(self: *GatewayWebSocketContext) gateway_host.GatewayResponse.WebSocketBody {
        return .{
            .accept_key = stream_websocket.computeAcceptKey(self.websocket_key),
            .ptr = @ptrCast(self),
            .write = write,
            .client_events = clientEventHandler(self),
            .deinit = deinitErased,
        };
    }

    fn write(ptr: *anyopaque, sink: stream_sink.ByteSink) anyerror!void {
        const self: *GatewayWebSocketContext = @ptrCast(@alignCast(ptr));
        try stream_projection.writeWebSocketAgentStream(self.allocator, self.app, .{
            .request_id = self.request_id,
            .params = self.params,
            .authority = self.authority,
            .cancel_requested = &self.cancel_requested,
            .client_closed = &self.client_closed,
            .websocket_acked_seq = &self.websocket_acked_seq,
            .websocket_pause_requested = &self.websocket_pause_requested,
            .websocket_resume_requested = &self.websocket_resume_requested,
            .websocket_resume_from_seq = &self.websocket_resume_from_seq,
        }, sink);
    }

    fn clientEventHandler(self: *GatewayWebSocketContext) gateway_host.GatewayResponse.WebSocketBody.ClientEventHandler {
        return .{
            .ptr = @ptrCast(self),
            .on_text = onClientTextErased,
            .on_close = onClientCloseErased,
        };
    }

    fn onClientTextErased(ptr: *anyopaque, text: []const u8) anyerror!void {
        const self: *GatewayWebSocketContext = @ptrCast(@alignCast(ptr));
        switch (try parseWebSocketControlMessage(self.allocator, text)) {
            .invalid => {},
            .cancel => {
                self.cancel_requested.store(true, .release);
            },
            .ack => |acked_seq| {
                self.websocket_acked_seq.store(acked_seq, .release);
            },
            .pause => {
                self.websocket_pause_requested.store(true, .release);
            },
            .resume_request => |resume_from_seq| {
                self.websocket_resume_from_seq.store(resume_from_seq, .release);
                self.websocket_resume_requested.store(true, .release);
            },
        }
    }

    fn onClientCloseErased(ptr: *anyopaque, close_code: ?u16, close_reason: ?[]const u8) void {
        const self: *GatewayWebSocketContext = @ptrCast(@alignCast(ptr));
        self.client_closed.store(true, .release);
        if (close_code) |raw_code| {
            self.client_close_code.store(raw_code, .release);
        }
        const reason = close_reason orelse "";
        const reason_len = @min(reason.len, self.client_close_reason_buf.len);
        @memcpy(self.client_close_reason_buf[0..reason_len], reason[0..reason_len]);
        self.client_close_reason_len.store(reason_len, .release);
    }

    fn deinitErased(ptr: *anyopaque, allocator: std.mem.Allocator) void {
        const self: *GatewayWebSocketContext = @ptrCast(@alignCast(ptr));
        allocator.free(self.websocket_key);
        deinitGatewayStreamContext(self.request_id, self.params, allocator, self);
    }
};

fn deinitGatewayStreamContext(request_id: []u8, params: []framework.ValidationField, allocator: std.mem.Allocator, ptr: anytype) void {
    allocator.free(request_id);
    freeValidationFields(allocator, params);
    allocator.destroy(ptr);
}

pub fn handle(allocator: std.mem.Allocator, app: *runtime.AppContext, request: HttpRequest) anyerror!HttpResponse {
    try app.channel_registry.recordHttpRequest(request.route, extractStringParam(request.params, "session_id"));
    if (std.mem.eql(u8, request.route, "/v1/agent/stream/sse")) {
        const stream_params = try cloneValidationFieldsWithOptionalStringParam(allocator, request.params, "last_event_id", request.last_event_id);
        defer freeValidationFields(allocator, stream_params);
        var sink = stream_sink.ArrayListSink.init(allocator);
        defer sink.deinit();
        try stream_projection.writeSseAgentStream(allocator, app, .{
            .request_id = request.request_id,
            .params = stream_params,
            .authority = request.authority,
        }, sink.asByteSink());
        return .{
            .status_code = 200,
            .content_type = "text/event-stream",
            .body_json = try sink.toOwnedSlice(),
        };
    }

    if (std.mem.eql(u8, request.route, "/v1/agent/stream/ws")) {
        return makeProtocolErrorResponse(allocator, request.request_id, 426, "HTTP_UPGRADE_REQUIRED", "websocket upgrade required");
    }

    const method = routeToMethod(request.route) orelse return makeProtocolErrorResponse(allocator, request.request_id, 404, "CORE_METHOD_NOT_FOUND", "route not found");

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = request.request_id,
        .method = method,
        .params = request.params,
        .source = .http,
        .authority = request.authority,
    }, false);

    return .{
        .status_code = statusCodeForEnvelope(envelope),
        .body_json = try cli.renderProtocolEnvelopeJson(allocator, envelope),
    };
}

pub fn handleGatewayAgentStreamSse(allocator: std.mem.Allocator, app: *runtime.AppContext, request: HttpRequest) anyerror!gateway_host.GatewayResponse {
    try app.channel_registry.recordHttpStream(request.route, extractStringParam(request.params, "session_id"));
    const context = try GatewaySseContext.init(allocator, app, request);
    return .{
        .status_code = 200,
        .content_type = "text/event-stream",
        .body = .{ .streaming = context.asStreamingBody() },
    };
}

pub fn handleGatewayAgentStreamWebSocket(allocator: std.mem.Allocator, app: *runtime.AppContext, request: HttpRequest) anyerror!gateway_host.GatewayResponse {
    try app.channel_registry.recordHttpStream(request.route, extractStringParam(request.params, "session_id"));
    if (request.websocket_key == null) {
        const response = try makeProtocolErrorResponse(allocator, request.request_id, 426, "HTTP_UPGRADE_REQUIRED", "websocket upgrade required");
        return .{
            .status_code = response.status_code,
            .content_type = response.content_type,
            .body = .{ .buffered = response.body_json },
        };
    }

    const context = try GatewayWebSocketContext.init(allocator, app, request);
    return .{
        .status_code = 101,
        .content_type = "application/websocket",
        .body = .{ .websocket = context.asWebSocketBody() },
    };
}

fn routeToMethod(route: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, route, "/v1/status")) return "status.all";
    if (std.mem.eql(u8, route, "/v1/app/meta")) return "app.meta";
    if (std.mem.eql(u8, route, "/v1/agent/run")) return "agent.run";
    if (std.mem.eql(u8, route, "/v1/agent/stream")) return "agent.stream";
    if (std.mem.eql(u8, route, "/v1/config/get")) return "config.get";
    if (std.mem.eql(u8, route, "/v1/config/set")) return "config.set";
    if (std.mem.eql(u8, route, "/v1/config/migrate-preview")) return "config.migrate_preview";
    if (std.mem.eql(u8, route, "/v1/config/migrate-apply")) return "config.migrate_apply";
    if (std.mem.eql(u8, route, "/v1/config/compat-import")) return "config.compat_import";
    if (std.mem.eql(u8, route, "/v1/diagnostics/summary")) return "diagnostics.summary";
    if (std.mem.eql(u8, route, "/v1/diagnostics/doctor")) return "diagnostics.doctor";
    if (std.mem.eql(u8, route, "/v1/onboard/summary")) return "onboard.summary";
    if (std.mem.eql(u8, route, "/v1/onboard/apply-defaults")) return "onboard.apply_defaults";
    if (std.mem.eql(u8, route, "/v1/device/pair/list")) return "device.pair.list";
    if (std.mem.eql(u8, route, "/v1/device/pair/approve")) return "device.pair.approve";
    if (std.mem.eql(u8, route, "/v1/device/pair/reject")) return "device.pair.reject";
    if (std.mem.eql(u8, route, "/v1/device/token/rotate")) return "device.token.rotate";
    if (std.mem.eql(u8, route, "/v1/device/token/revoke")) return "device.token.revoke";
    if (std.mem.eql(u8, route, "/v1/devices/list")) return "devices.list";
    if (std.mem.eql(u8, route, "/v1/node/list")) return "node.list";
    if (std.mem.eql(u8, route, "/v1/node/describe")) return "node.describe";
    if (std.mem.eql(u8, route, "/v1/metrics/summary")) return "metrics.summary";
    if (std.mem.eql(u8, route, "/v1/observer/recent")) return "observer.recent";
    if (std.mem.eql(u8, route, "/v1/events/subscribe")) return "events.subscribe";
    if (std.mem.eql(u8, route, "/v1/memory/summary")) return "memory.summary";
    if (std.mem.eql(u8, route, "/v1/session/get")) return "session.get";
    if (std.mem.eql(u8, route, "/v1/session/compact")) return "session.compact";
    if (std.mem.eql(u8, route, "/v1/memory/snapshot-export")) return "memory.snapshot_export";
    if (std.mem.eql(u8, route, "/v1/memory/retrieve")) return "memory.retrieve";
    if (std.mem.eql(u8, route, "/v1/memory/migrate-preview")) return "memory.migrate_preview";
    if (std.mem.eql(u8, route, "/v1/memory/migrate-apply")) return "memory.migrate_apply";
    if (std.mem.eql(u8, route, "/v1/logs/recent")) return "logs.recent";
    if (std.mem.eql(u8, route, "/v1/task/get")) return "task.get";
    if (std.mem.eql(u8, route, "/v1/task/by-request")) return "task.by_request";
    if (std.mem.eql(u8, route, "/v1/events/poll")) return "events.poll";
    if (std.mem.eql(u8, route, "/v1/gateway/status")) return "gateway.status";
    if (std.mem.eql(u8, route, "/v1/gateway/auth/status")) return "gateway.auth.status";
    if (std.mem.eql(u8, route, "/v1/gateway/token/generate")) return "gateway.token.generate";
    if (std.mem.eql(u8, route, "/v1/gateway/access/link")) return "gateway.access.link";
    if (std.mem.eql(u8, route, "/v1/gateway/start")) return "gateway.start";
    if (std.mem.eql(u8, route, "/v1/gateway/stop")) return "gateway.stop";
    if (std.mem.eql(u8, route, "/v1/gateway/reload")) return "gateway.reload";
    if (std.mem.eql(u8, route, "/v1/gateway/stream-subscribe")) return "gateway.stream_subscribe";
    if (std.mem.eql(u8, route, "/v1/service/status")) return "service.status";
    if (std.mem.eql(u8, route, "/v1/service/install")) return "service.install";
    if (std.mem.eql(u8, route, "/v1/service/start")) return "service.start";
    if (std.mem.eql(u8, route, "/v1/service/stop")) return "service.stop";
    if (std.mem.eql(u8, route, "/v1/service/restart")) return "service.restart";
    if (std.mem.eql(u8, route, "/v1/skills/list")) return "skills.list";
    if (std.mem.eql(u8, route, "/v1/skills/install")) return "skills.install";
    if (std.mem.eql(u8, route, "/v1/skills/run")) return "skills.run";
    if (std.mem.eql(u8, route, "/v1/cron/list")) return "cron.list";
    if (std.mem.eql(u8, route, "/v1/cron/register")) return "cron.register";
    if (std.mem.eql(u8, route, "/v1/cron/tick")) return "cron.tick";
    if (std.mem.eql(u8, route, "/v1/heartbeat/status")) return "heartbeat.status";
    if (std.mem.eql(u8, route, "/v1/tunnel/status")) return "tunnel.status";
    if (std.mem.eql(u8, route, "/v1/tunnel/activate")) return "tunnel.activate";
    if (std.mem.eql(u8, route, "/v1/tunnel/deactivate")) return "tunnel.deactivate";
    if (std.mem.eql(u8, route, "/v1/mcp/list")) return "mcp.list";
    if (std.mem.eql(u8, route, "/v1/mcp/register")) return "mcp.register";
    if (std.mem.eql(u8, route, "/v1/hardware/list")) return "hardware.list";
    if (std.mem.eql(u8, route, "/v1/hardware/register")) return "hardware.register";
    if (std.mem.eql(u8, route, "/v1/peripheral/register")) return "peripheral.register";
    if (std.mem.eql(u8, route, "/v1/voice/status")) return "voice.status";
    if (std.mem.eql(u8, route, "/v1/voice/attach")) return "voice.attach";
    if (std.mem.eql(u8, route, "/v1/voice/detach")) return "voice.detach";
    return null;
}

fn makeProtocolErrorResponse(
    allocator: std.mem.Allocator,
    request_id: []const u8,
    status_code: u16,
    code: []const u8,
    message: []const u8,
) anyerror!HttpResponse {
    return .{
        .status_code = status_code,
        .body_json = try std.fmt.allocPrint(
            allocator,
            "{{\"ok\":false,\"error\":{{\"code\":\"{s}\",\"message\":\"{s}\"}},\"meta\":{{\"requestId\":\"{s}\",\"traceId\":null,\"taskId\":null}}}}",
            .{ code, message, request_id },
        ),
    };
}

fn extractStringParam(params: []const framework.ValidationField, key: []const u8) ?[]const u8 {
    for (params) |field| {
        if (std.mem.eql(u8, field.key, key)) {
            return switch (field.value) {
                .string => |value| value,
                else => null,
            };
        }
    }
    return null;
}

fn statusCodeForEnvelope(envelope: framework.CommandEnvelope) u16 {
    if (envelope.ok) {
        return switch (envelope.result.?) {
            .success_json => 200,
            .task_accepted => 202,
        };
    }

    const code = envelope.app_error.?.code;
    if (std.mem.eql(u8, code, framework.core.error_model.code.CORE_METHOD_NOT_FOUND) or std.mem.eql(u8, code, framework.core.error_model.code.RUNTIME_TASK_NOT_FOUND)) return 404;
    if (std.mem.eql(u8, code, framework.core.error_model.code.CORE_METHOD_NOT_ALLOWED) or std.mem.eql(u8, code, framework.core.error_model.code.SECURITY_POLICY_DENIED) or std.mem.eql(u8, code, framework.core.error_model.code.SECURITY_COMMAND_NOT_ALLOWED) or std.mem.eql(u8, code, framework.core.error_model.code.SECURITY_PATH_NOT_ALLOWED)) return 403;
    if (std.mem.startsWith(u8, code, "VALIDATION_")) return 422;
    if (std.mem.eql(u8, code, framework.core.error_model.code.CORE_TIMEOUT)) return 504;
    if (std.mem.eql(u8, code, framework.core.error_model.code.RUNTIME_TASK_FAILED) or std.mem.eql(u8, code, framework.core.error_model.code.PROVIDER_OPERATION_FAILED)) return 503;
    return 500;
}

fn cloneValidationFields(allocator: std.mem.Allocator, fields: []const framework.ValidationField) anyerror![]framework.ValidationField {
    const cloned = try allocator.alloc(framework.ValidationField, fields.len);
    errdefer allocator.free(cloned);

    for (fields, 0..) |field, index| {
        cloned[index] = .{
            .key = try allocator.dupe(u8, field.key),
            .value = try cloneValidationValue(allocator, field.value),
        };
    }
    return cloned;
}

fn cloneValidationFieldsWithOptionalStringParam(
    allocator: std.mem.Allocator,
    fields: []const framework.ValidationField,
    key: []const u8,
    value: ?[]const u8,
) anyerror![]framework.ValidationField {
    const extra_count: usize = if (value != null) 1 else 0;
    const cloned = try allocator.alloc(framework.ValidationField, fields.len + extra_count);
    errdefer allocator.free(cloned);

    for (fields, 0..) |field, index| {
        cloned[index] = .{
            .key = try allocator.dupe(u8, field.key),
            .value = try cloneValidationValue(allocator, field.value),
        };
    }
    if (value) |actual| {
        cloned[fields.len] = .{
            .key = try allocator.dupe(u8, key),
            .value = .{ .string = try allocator.dupe(u8, actual) },
        };
    }
    return cloned;
}

const WebSocketControlMessage = union(enum) {
    invalid,
    cancel,
    ack: u64,
    pause,
    resume_request: u64,
};

fn parseWebSocketControlMessage(allocator: std.mem.Allocator, text: []const u8) anyerror!WebSocketControlMessage {
    const trimmed = std.mem.trim(u8, text, " \r\n\t");
    if (std.ascii.eqlIgnoreCase(trimmed, "cancel")) {
        return .cancel;
    }

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch return .invalid;
    defer parsed.deinit();
    if (parsed.value != .object) return .invalid;

    const object = parsed.value.object;
    const type_value = object.get("type") orelse return .invalid;
    if (type_value != .string) return .invalid;

    if (std.mem.eql(u8, type_value.string, "cancel")) {
        return .cancel;
    }
    if (std.mem.eql(u8, type_value.string, "ack")) {
        const acked_seq = parseControlU64Field(object, "ackedSeq") orelse return .invalid;
        return .{ .ack = acked_seq };
    }
    if (std.mem.eql(u8, type_value.string, "pause")) {
        return .pause;
    }
    if (std.mem.eql(u8, type_value.string, "resume")) {
        const resume_from_seq = parseControlU64Field(object, "resumeFromSeq") orelse return .invalid;
        return .{ .resume_request = resume_from_seq };
    }
    return .invalid;
}

fn parseControlU64Field(object: std.json.ObjectMap, key: []const u8) ?u64 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .integer => |number| if (number >= 0) @as(u64, @intCast(number)) else null,
        else => null,
    };
}

fn cloneValidationValue(allocator: std.mem.Allocator, value: framework.ValidationValue) anyerror!framework.ValidationValue {
    return switch (value) {
        .null => .null,
        .boolean => |flag| .{ .boolean = flag },
        .integer => |number| .{ .integer = number },
        .float => |number| .{ .float = number },
        .string => |text| .{ .string = try allocator.dupe(u8, text) },
        .array => |items| blk: {
            const cloned = try allocator.alloc(framework.ValidationValue, items.len);
            errdefer allocator.free(cloned);
            for (items, 0..) |item, index| {
                cloned[index] = try cloneValidationValue(allocator, item);
            }
            break :blk .{ .array = cloned };
        },
        .object => |fields| blk: {
            const cloned = try allocator.alloc(framework.ValidationField, fields.len);
            errdefer allocator.free(cloned);
            for (fields, 0..) |field, index| {
                cloned[index] = .{
                    .key = try allocator.dupe(u8, field.key),
                    .value = try cloneValidationValue(allocator, field.value),
                };
            }
            break :blk .{ .object = cloned };
        },
    };
}

fn freeValidationFields(allocator: std.mem.Allocator, fields: []framework.ValidationField) void {
    for (fields) |field| {
        allocator.free(field.key);
        field.value.deinit(allocator);
    }
    allocator.free(fields);
}

test "http adapter maps route to app meta" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    var response = try handle(std.testing.allocator, app, .{
        .request_id = "http_req_01",
        .route = "/v1/app/meta",
        .params = &.{},
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u16, 200), response.status_code);
    try std.testing.expect(std.mem.indexOf(u8, response.body_json, "\"ok\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body_json, "\"result\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body_json, "\"meta\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body_json, "\"appName\":\"ourclaw\"") != null);
}

test "http adapter returns protocol envelope for missing route and websocket upgrade" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    var not_found = try handle(std.testing.allocator, app, .{
        .request_id = "http_req_missing_route",
        .route = "/v1/unknown",
        .params = &.{},
    });
    defer not_found.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 404), not_found.status_code);
    try std.testing.expect(std.mem.indexOf(u8, not_found.body_json, "\"ok\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, not_found.body_json, "\"code\":\"CORE_METHOD_NOT_FOUND\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, not_found.body_json, "\"requestId\":\"http_req_missing_route\"") != null);

    var upgrade = try handle(std.testing.allocator, app, .{
        .request_id = "http_req_upgrade_needed",
        .route = "/v1/agent/stream/ws",
        .params = &.{},
    });
    defer upgrade.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 426), upgrade.status_code);
    try std.testing.expect(std.mem.indexOf(u8, upgrade.body_json, "\"code\":\"HTTP_UPGRADE_REQUIRED\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, upgrade.body_json, "\"requestId\":\"http_req_upgrade_needed\"") != null);
}

test "http adapter exposes gateway control-plane routes" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    var gateway_status = try handle(std.testing.allocator, app, .{
        .request_id = "http_req_gateway_status",
        .route = "/v1/gateway/status",
        .params = &.{},
        .authority = .admin,
    });
    defer gateway_status.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 200), gateway_status.status_code);
    try std.testing.expect(std.mem.indexOf(u8, gateway_status.body_json, "\"ok\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway_status.body_json, "\"healthState\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway_status.body_json, "\"bindHost\":") != null);

    var gateway_reload = try handle(std.testing.allocator, app, .{
        .request_id = "http_req_gateway_reload",
        .route = "/v1/gateway/reload",
        .params = &.{},
        .authority = .admin,
    });
    defer gateway_reload.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 200), gateway_reload.status_code);
    try std.testing.expect(std.mem.indexOf(u8, gateway_reload.body_json, "\"action\":\"reload\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway_reload.body_json, "\"healthMessage\":") != null);

    var gateway_subscribe = try handle(std.testing.allocator, app, .{
        .request_id = "http_req_gateway_subscribe",
        .route = "/v1/gateway/stream-subscribe",
        .params = &.{},
        .authority = .admin,
    });
    defer gateway_subscribe.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 200), gateway_subscribe.status_code);
    try std.testing.expect(std.mem.indexOf(u8, gateway_subscribe.body_json, "\"subscriptionId\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, gateway_subscribe.body_json, "\"streamSubscriptions\":1") != null);
}

test "http adapter projects agent stream as sse" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_http_sse",
        .label = "Mock OpenAI HTTP SSE",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_http_sse" } },
        .{ .key = "prompt", .value = .{ .string = "CALL_TOOL:echo" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_http_sse" } },
    };

    var response = try handle(std.testing.allocator, app, .{
        .request_id = "http_req_sse_01",
        .route = "/v1/agent/stream/sse",
        .params = params[0..],
        .authority = .admin,
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u16, 200), response.status_code);
    try std.testing.expectEqualStrings("text/event-stream", response.content_type);
    try std.testing.expect(std.mem.indexOf(u8, response.body_json, "event: meta") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body_json, "event: status.update") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body_json, "event: tool.call.started") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body_json, "event: final.result") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body_json, "event: result") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body_json, "event: done") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body_json, "final response after tool") != null);
}

test "http gateway sse response exposes streaming body" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_gateway_sse",
        .label = "Mock OpenAI Gateway SSE",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_gateway_sse" } },
        .{ .key = "prompt", .value = .{ .string = "CALL_TOOL:echo" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_gateway_sse" } },
    };

    var response = try handleGatewayAgentStreamSse(std.testing.allocator, app, .{
        .request_id = "gateway_req_sse_01",
        .route = "/v1/agent/stream/sse",
        .params = params[0..],
        .authority = .admin,
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u16, 200), response.status_code);
    try std.testing.expectEqualStrings("text/event-stream", response.content_type);

    var sink = stream_sink.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();
    switch (response.body) {
        .streaming => |streaming| try streaming.write(streaming.ptr, sink.asByteSink()),
        .buffered => return error.ExpectedStreamingGatewayBody,
        .websocket => return error.ExpectedStreamingGatewayBody,
    }

    const output = try sink.toOwnedSlice();
    defer std.testing.allocator.free(output);
    try std.testing.expect(sink.flush_count >= 4);
    try std.testing.expect(std.mem.indexOf(u8, output, "event: tool.result") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "event: done") != null);

    const snapshot = app.channel_registry.httpSnapshot();
    try std.testing.expectEqual(@as(usize, 1), snapshot.stream_count);
    try std.testing.expectEqualStrings("/v1/agent/stream/sse", snapshot.last_target.?);
    try std.testing.expectEqualStrings("sess_gateway_sse", snapshot.last_session_id.?);
}

test "http gateway websocket response exposes websocket frames" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_gateway_ws",
        .label = "Mock OpenAI Gateway WS",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_gateway_ws" } },
        .{ .key = "prompt", .value = .{ .string = "CALL_TOOL:echo" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_gateway_ws" } },
    };

    var response = try handleGatewayAgentStreamWebSocket(std.testing.allocator, app, .{
        .request_id = "gateway_req_ws_01",
        .route = "/v1/agent/stream/ws",
        .params = params[0..],
        .websocket_key = "dGhlIHNhbXBsZSBub25jZQ==",
        .authority = .admin,
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u16, 101), response.status_code);

    var sink = stream_sink.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();
    switch (response.body) {
        .websocket => |websocket| try websocket.write(websocket.ptr, sink.asByteSink()),
        .streaming => return error.ExpectedWebSocketGatewayBody,
        .buffered => return error.ExpectedWebSocketGatewayBody,
    }

    const bytes = try sink.toOwnedSlice();
    defer std.testing.allocator.free(bytes);

    var offset: usize = 0;
    const meta = try stream_websocket.parseServerFrame(bytes[offset..]);
    offset += meta.header_len + meta.payload_len;
    try std.testing.expectEqual(@as(u8, 0x1), meta.opcode);
    try std.testing.expect(std.mem.indexOf(u8, bytes[meta.header_len .. meta.header_len + meta.payload_len], "\"event\":\"meta\"") != null);

    var found_done = false;
    while (offset < bytes.len) {
        const frame = try stream_websocket.parseServerFrame(bytes[offset..]);
        const payload_start = offset + frame.header_len;
        const payload_end = payload_start + frame.payload_len;
        const payload = bytes[payload_start..payload_end];
        if (frame.opcode == 0x8) {
            break;
        }
        if (std.mem.indexOf(u8, payload, "\"event\":\"done\"") != null) {
            found_done = true;
        }
        offset = payload_end;
    }

    try std.testing.expect(found_done);
}

test "http websocket parser supports ack pause resume and cancel" {
    const allocator = std.testing.allocator;

    const parsed_ack = try parseWebSocketControlMessage(allocator, "{\"type\":\"ack\",\"ackedSeq\":7}");
    try std.testing.expectEqualDeep(WebSocketControlMessage{ .ack = 7 }, parsed_ack);

    const parsed_pause = try parseWebSocketControlMessage(allocator, "{\"type\":\"pause\"}");
    try std.testing.expectEqualDeep(WebSocketControlMessage.pause, parsed_pause);

    const parsed_resume = try parseWebSocketControlMessage(allocator, "{\"type\":\"resume\",\"resumeFromSeq\":5}");
    try std.testing.expectEqualDeep(WebSocketControlMessage{ .resume_request = 5 }, parsed_resume);

    const parsed_cancel_json = try parseWebSocketControlMessage(allocator, "{\"type\":\"cancel\"}");
    try std.testing.expectEqualDeep(WebSocketControlMessage.cancel, parsed_cancel_json);

    const parsed_cancel_legacy = try parseWebSocketControlMessage(allocator, " cancel ");
    try std.testing.expectEqualDeep(WebSocketControlMessage.cancel, parsed_cancel_legacy);
}

test "http websocket parser ignores malformed and unknown control payloads" {
    const allocator = std.testing.allocator;
    try std.testing.expectEqualDeep(WebSocketControlMessage.invalid, try parseWebSocketControlMessage(allocator, "{"));
    try std.testing.expectEqualDeep(WebSocketControlMessage.invalid, try parseWebSocketControlMessage(allocator, "{\"type\":\"noop\"}"));
    try std.testing.expectEqualDeep(WebSocketControlMessage.invalid, try parseWebSocketControlMessage(allocator, "hello cancel world"));
    try std.testing.expectEqualDeep(WebSocketControlMessage.invalid, try parseWebSocketControlMessage(allocator, "{\"type\":\"ack\"}"));
    try std.testing.expectEqualDeep(WebSocketControlMessage.invalid, try parseWebSocketControlMessage(allocator, "{\"type\":\"resume\"}"));
}

test "http websocket control handler wires signals and preserves raw close payload" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_gateway_ws_control",
        .label = "Mock OpenAI Gateway WS Control",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_gateway_ws_control" } },
        .{ .key = "prompt", .value = .{ .string = "CALL_TOOL:echo" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_gateway_ws_control" } },
    };

    var response = try handleGatewayAgentStreamWebSocket(std.testing.allocator, app, .{
        .request_id = "gateway_req_ws_control_01",
        .route = "/v1/agent/stream/ws",
        .params = params[0..],
        .websocket_key = "dGhlIHNhbXBsZSBub25jZQ==",
        .authority = .admin,
    });
    defer response.deinit(std.testing.allocator);

    switch (response.body) {
        .websocket => |websocket| {
            const client_events = websocket.client_events orelse return error.ExpectedClientEventHandler;
            const context: *GatewayWebSocketContext = @ptrCast(@alignCast(websocket.ptr));

            try client_events.on_text(client_events.ptr, "{\"type\":\"ack\",\"ackedSeq\":7}");
            try std.testing.expectEqual(@as(u64, 7), context.websocket_acked_seq.load(.acquire));

            try client_events.on_text(client_events.ptr, "{\"type\":\"pause\"}");
            try std.testing.expect(context.websocket_pause_requested.load(.acquire));

            try client_events.on_text(client_events.ptr, "{\"type\":\"resume\",\"resumeFromSeq\":5}");
            try std.testing.expect(context.websocket_resume_requested.load(.acquire));
            try std.testing.expectEqual(@as(u64, 5), context.websocket_resume_from_seq.load(.acquire));

            context.cancel_requested.store(false, .release);
            try client_events.on_text(client_events.ptr, "{\"type\":\"cancel\"}");
            try std.testing.expect(context.cancel_requested.load(.acquire));

            context.cancel_requested.store(false, .release);
            try client_events.on_text(client_events.ptr, "cancel");
            try std.testing.expect(context.cancel_requested.load(.acquire));

            context.websocket_acked_seq.store(11, .release);
            context.websocket_pause_requested.store(false, .release);
            context.websocket_resume_requested.store(false, .release);
            context.websocket_resume_from_seq.store(13, .release);
            context.cancel_requested.store(false, .release);
            try client_events.on_text(client_events.ptr, "{");
            try client_events.on_text(client_events.ptr, "{\"type\":\"noop\"}");
            try client_events.on_text(client_events.ptr, "hello cancel world");
            try std.testing.expectEqual(@as(u64, 11), context.websocket_acked_seq.load(.acquire));
            try std.testing.expect(!context.websocket_pause_requested.load(.acquire));
            try std.testing.expect(!context.websocket_resume_requested.load(.acquire));
            try std.testing.expectEqual(@as(u64, 13), context.websocket_resume_from_seq.load(.acquire));
            try std.testing.expect(!context.cancel_requested.load(.acquire));

            client_events.on_close(client_events.ptr, 1001, "bye");
            try std.testing.expect(context.client_closed.load(.acquire));
            try std.testing.expectEqual(@as(u16, 1001), context.client_close_code.load(.acquire));
            const close_reason_len = context.client_close_reason_len.load(.acquire);
            try std.testing.expectEqualStrings("bye", context.client_close_reason_buf[0..close_reason_len]);
        },
        else => return error.ExpectedWebSocketGatewayBody,
    }
}
