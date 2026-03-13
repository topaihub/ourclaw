const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");
const runtime_model = @import("../runtime/app_context.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "agent.run",
        .method = "agent.run",
        .description = "Run a minimal agent turn",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "session_id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "prompt", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "provider_id", .required = false, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "tool_id", .required = false, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "tool_input_json", .required = false, .value_kind = .string },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *runtime_model.AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));

    var result = try app.agent_runtime.run(.{
        .session_id = ctx.param("session_id").?.value.string,
        .prompt = ctx.param("prompt").?.value.string,
        .provider_id = if (ctx.param("provider_id")) |field| field.value.string else "openai",
        .tool_id = if (ctx.param("tool_id")) |field| field.value.string else null,
        .tool_input_json = if (ctx.param("tool_input_json")) |field| field.value.string else null,
        .authority = ctx.request.authority,
    });
    defer result.deinit(ctx.allocator);

    const response_text_json = try jsonString(ctx.allocator, result.response_text);
    defer ctx.allocator.free(response_text_json);

    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"sessionId\":\"{s}\",\"providerId\":\"{s}\",\"model\":\"{s}\",\"responseText\":{s},\"sessionEventCount\":{d},\"providerLatencyMs\":{d}}}",
        .{ result.session_id, result.provider_id, result.model, response_text_json, result.session_event_count, result.provider_latency_ms },
    );
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
