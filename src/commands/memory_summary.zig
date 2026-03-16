const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "memory.summary",
        .method = "memory.summary",
        .description = "Summarize session memory",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "session_id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "max_items", .required = false, .value_kind = .integer, .rules = &.{.{ .int_range = .{ .min = 1, .max = 64 } }} },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const session_id = ctx.param("session_id").?.value.string;
    const max_items: usize = if (ctx.param("max_items")) |field| @intCast(field.value.integer) else 8;
    var summary = try services.memory_runtime.summarizeSession(ctx.allocator, session_id, max_items);
    defer summary.deinit(ctx.allocator);
    const summary_text_json = try jsonString(ctx.allocator, summary.summary_text);
    defer ctx.allocator.free(summary_text_json);
    return std.fmt.allocPrint(ctx.allocator, "{{\"sessionId\":\"{s}\",\"sourceCount\":{d},\"summaryText\":{s}}}", .{ summary.session_id, summary.source_count, summary_text_json });
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
