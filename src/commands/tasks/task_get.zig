const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "task.get",
        .method = "task.get",
        .description = "Get task summary by task id",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{.{ .key = "task_id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} }},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const task_id = ctx.param("task_id").?.value.string;
    const summary = try services.framework_context.task_runner.snapshotById(ctx.allocator, task_id) orelse return error.TaskNotFound;
    defer {
        var mutable = summary;
        mutable.deinit(ctx.allocator);
    }
    return renderTaskSummary(ctx.allocator, summary);
}

pub fn renderTaskSummary(allocator: std.mem.Allocator, summary: framework.TaskSummary) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);
    try writer.writeByte('{');
    try appendStringField(writer, "taskId", summary.id, true);
    try appendStringField(writer, "command", summary.command, false);
    try appendOptionalStringField(writer, "requestId", summary.request_id, false);
    try appendStringField(writer, "state", summary.state.asText(), false);
    try appendOptionalStringField(writer, "errorCode", summary.error_code, false);
    try appendOptionalStringField(writer, "result", summary.result_json, false);
    try writer.writeByte('}');
    return allocator.dupe(u8, buf.items);
}

fn appendStringField(writer: anytype, key: []const u8, value: []const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writeJsonString(writer, value);
}

fn appendOptionalStringField(writer: anytype, key: []const u8, value: ?[]const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    if (value) |actual| {
        try writeJsonString(writer, actual);
    } else {
        try writer.writeAll("null");
    }
}

fn writeJsonString(writer: anytype, value: []const u8) anyerror!void {
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
}
