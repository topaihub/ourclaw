const std = @import("std");
const framework = @import("framework");
const runtime = @import("../runtime/app_context.zig");
const cli = @import("cli_adapter.zig");
const stream_sink = @import("stream_sink.zig");
const stream_projection = @import("stream_projection.zig");

pub const BridgeRequest = struct {
    request_id: []const u8,
    method: []const u8,
    params: []const framework.ValidationField,
    authority: framework.Authority = .operator,
};

pub fn handle(allocator: std.mem.Allocator, app: *runtime.AppContext, request: BridgeRequest) anyerror![]u8 {
    try app.channel_registry.recordBridgeRequest(request.method, extractStringParam(request.params, "session_id"));
    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(.{
        .request_id = request.request_id,
        .method = request.method,
        .params = request.params,
        .source = .bridge,
        .authority = request.authority,
    }, false);
    return cli.renderProtocolEnvelopeJson(allocator, envelope);
}

pub fn stream(app: *runtime.AppContext, allocator: std.mem.Allocator, request: BridgeRequest, sink: stream_sink.ByteSink) anyerror!void {
    if (!std.mem.eql(u8, request.method, "agent.stream")) return error.BridgeStreamingMethodNotSupported;
    try app.channel_registry.recordBridgeStream(request.method, extractStringParam(request.params, "session_id"));
    try stream_projection.writeBridgeAgentStream(allocator, app, .{
        .request_id = request.request_id,
        .params = request.params,
        .authority = request.authority,
    }, sink);
}

pub fn handleStreaming(allocator: std.mem.Allocator, app: *runtime.AppContext, request: BridgeRequest) anyerror![]u8 {
    var sink = stream_sink.ArrayListSink.init(allocator);
    defer sink.deinit();
    try stream(app, allocator, request, sink.asByteSink());
    return sink.toOwnedSlice();
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

test "bridge adapter dispatches config get" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    const params = [_]framework.ValidationField{
        .{ .key = "path", .value = .{ .string = "gateway.port" } },
    };
    const json = try handle(std.testing.allocator, app, .{
        .request_id = "bridge_req_01",
        .method = "config.get",
        .params = params[0..],
    });
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"path\":\"gateway.port\"") != null);
}

test "bridge adapter projects agent stream as ndjson" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_bridge_stream",
        .label = "Mock OpenAI Bridge Stream",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    const params = [_]framework.ValidationField{
        .{ .key = "session_id", .value = .{ .string = "sess_bridge_stream" } },
        .{ .key = "prompt", .value = .{ .string = "CALL_TOOL:echo" } },
        .{ .key = "provider_id", .value = .{ .string = "mock_openai_bridge_stream" } },
    };

    const output = try handleStreaming(std.testing.allocator, app, .{
        .request_id = "bridge_req_stream_01",
        .method = "agent.stream",
        .params = params[0..],
        .authority = .admin,
    });
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "\"event\":\"meta\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"event\":\"tool.call.started\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"event\":\"result\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"event\":\"done\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "final response after tool") != null);

    const snapshot = app.channel_registry.bridgeSnapshot();
    try std.testing.expectEqual(@as(usize, 1), snapshot.stream_count);
    try std.testing.expectEqualStrings("agent.stream", snapshot.last_target.?);
    try std.testing.expectEqualStrings("sess_bridge_stream", snapshot.last_session_id.?);
}
