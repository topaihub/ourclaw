const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "memory.retrieve",
        .method = "memory.retrieve",
        .description = "Retrieve matching memory hits",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "session_id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "query", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "limit", .required = false, .value_kind = .integer, .rules = &.{.{ .int_range = .{ .min = 1, .max = 32 } }} },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const session_id = ctx.param("session_id").?.value.string;
    const query = ctx.param("query").?.value.string;
    const limit: usize = if (ctx.param("limit")) |field| @intCast(field.value.integer) else 5;
    const hits = try services.memory_runtime.retrieve(ctx.allocator, session_id, query, limit);
    defer {
        for (hits) |*hit| hit.deinit(ctx.allocator);
        ctx.allocator.free(hits);
    }

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.writeByte('[');
    for (hits, 0..) |hit, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try appendUnsignedField(writer, "rank", hit.rank, true);
        try appendStringField(writer, "kind", hit.kind, false);
        try appendUnsignedField(writer, "score", hit.score, false);
        try appendStringField(writer, "reason", @tagName(hit.ranking_reason), false);
        try appendStringField(writer, "embeddingStrategy", @tagName(hit.embedding_strategy), false);
        try appendOptionalStringField(writer, "embeddingProvider", hit.embedding_provider, false);
        try appendOptionalStringField(writer, "embeddingModel", hit.embedding_model, false);
        try appendUnsignedField(writer, "embeddingScore", hit.embedding_score, false);
        try appendUnsignedField(writer, "keywordOverlap", hit.keyword_overlap, false);
        try appendUnsignedField(writer, "kindWeight", hit.kind_weight, false);
        try appendSignedField(writer, "tsUnixMs", hit.ts_unix_ms, false);
        try appendRawJsonField(writer, "content", hit.content_json, false);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
    return ctx.allocator.dupe(u8, buf.items);
}

fn appendStringField(writer: anytype, key: []const u8, value: []const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writeJsonString(writer, value);
}

fn appendUnsignedField(writer: anytype, key: []const u8, value: usize, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.print("{d}", .{value});
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

fn appendSignedField(writer: anytype, key: []const u8, value: i64, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.print("{d}", .{value});
}

fn appendRawJsonField(writer: anytype, key: []const u8, value_json: []const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.writeAll(value_json);
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
            else => {
                if (ch < 32) {
                    try writer.print("\\u00{x:0>2}", .{ch});
                } else {
                    try writer.writeByte(ch);
                }
            },
        }
    }
    try writer.writeByte('"');
}
