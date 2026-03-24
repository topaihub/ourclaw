const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "providers.status",
        .method = "providers.status",
        .description = "Get provider capability and health snapshot",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);

    try writer.writeByte('{');
    try appendUnsignedField(writer, "count", services.provider_registry.count(), true);
    try appendUnsignedField(writer, "refreshCount", services.provider_registry.refresh_count, false);
    try appendOptionalStringField(writer, "lastRefreshReason", services.provider_registry.last_refresh_reason, false);
    try writer.writeAll(",\"items\":[");
    for (services.provider_registry.definitions.items, 0..) |provider_def, index| {
        if (index > 0) try writer.writeByte(',');
        var health = try services.provider_registry.health(ctx.allocator, provider_def.id);
        defer health.deinit(ctx.allocator);
        const models = try services.provider_registry.listModels(ctx.allocator, provider_def.id);
        defer {
            for (models) |model| {
                ctx.allocator.free(model.id);
                ctx.allocator.free(model.label);
            }
            ctx.allocator.free(models);
        }

        try writer.writeByte('{');
        try appendStringField(writer, "id", provider_def.id, true);
        try appendStringField(writer, "label", provider_def.label, false);
        try appendStringField(writer, "endpoint", provider_def.endpoint, false);
        try appendStringField(writer, "defaultModel", provider_def.default_model, false);
        try appendOptionalStringField(writer, "defaultEmbeddingModel", if (provider_def.default_embedding_model.len > 0) provider_def.default_embedding_model else null, false);
        try appendBoolField(writer, "healthy", health.healthy, false);
        try appendStringField(writer, "healthMessage", health.message, false);
        try appendBoolField(writer, "supportsStreaming", provider_def.supports_streaming, false);
        try appendBoolField(writer, "supportsTools", provider_def.supports_tools, false);
        try appendBoolField(writer, "supportsEmbeddings", provider_def.supports_embeddings, false);
        try appendUnsignedField(writer, "modelCount", models.len, false);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
    try writer.writeByte('}');
    return ctx.allocator.dupe(u8, buf.items);
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
    if (value) |text| {
        try writeJsonString(writer, text);
    } else {
        try writer.writeAll("null");
    }
}

fn appendBoolField(writer: anytype, key: []const u8, value: bool, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.writeAll(if (value) "true" else "false");
}

fn appendUnsignedField(writer: anytype, key: []const u8, value: usize, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.print("{d}", .{value});
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
