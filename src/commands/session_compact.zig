const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "session.compact",
        .method = "session.compact",
        .description = "Compact session memory and store summary event",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "session_id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "keep_last", .required = false, .value_kind = .integer, .rules = &.{.{ .int_range = .{ .min = 1, .max = 32 } }} },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const session_id = ctx.param("session_id").?.value.string;
    const keep_last: usize = if (ctx.param("keep_last")) |field| @intCast(field.value.integer) else 2;

    var result = try services.memory_runtime.compactSession(ctx.allocator, session_id, keep_last);
    defer result.deinit(ctx.allocator);
    try services.session_store.appendEvent(session_id, "session.summary", result.summary.summary_text);
    var snapshot = try services.session_store.snapshotMeta(ctx.allocator, session_id);
    defer snapshot.deinit(ctx.allocator);
    const summary_text_json = try jsonString(ctx.allocator, result.summary.summary_text);
    defer ctx.allocator.free(summary_text_json);

    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"sessionId\":\"{s}\",\"keepLast\":{d},\"memoryEntryCount\":{d},\"eventCount\":{d},\"removedCount\":{d},\"keptCount\":{d},\"summaryText\":{s}}}",
        .{ session_id, keep_last, result.result_entry_count, snapshot.event_count, result.removed_count, result.kept_count, summary_text_json },
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
