const std = @import("std");
const framework = @import("framework");
const registry = @import("../../config/field_registry.zig");
const config_runtime = @import("../../config/runtime.zig");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "config.get",
        .method = "config.get",
        .description = "Read a config field",
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "path", .required = false, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "paths", .required = false, .value_kind = .string, .rules = &.{.non_empty_string} },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const path_list = try collectPaths(ctx);
    defer {
        for (path_list) |path| ctx.allocator.free(path);
        ctx.allocator.free(path_list);
    }

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);

    try writer.writeByte('{');
    try appendUnsignedField(writer, "count", path_list.len, true);
    try writer.writeAll(",\"items\":[");

    for (path_list, 0..) |path, index| {
        if (index > 0) try writer.writeByte(',');
        try writeConfigItem(ctx, services, writer, path);
    }

    try writer.writeByte(']');
    try writer.writeByte('}');
    return ctx.allocator.dupe(u8, buf.items);
}

fn collectPaths(ctx: *const framework.CommandContext) anyerror![][]u8 {
    if (ctx.param("path")) |field| {
        const paths = try ctx.allocator.alloc([]u8, 1);
        paths[0] = try ctx.allocator.dupe(u8, field.value.string);
        return paths;
    }

    if (ctx.param("paths")) |field| {
        var parts = std.mem.splitScalar(u8, field.value.string, ',');
        var list: std.ArrayListUnmanaged([]u8) = .empty;
        defer list.deinit(ctx.allocator);

        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t\r\n");
            if (trimmed.len == 0) continue;
            try list.append(ctx.allocator, try ctx.allocator.dupe(u8, trimmed));
        }

        return ctx.allocator.dupe([]u8, list.items);
    }

    return error.MissingConfigPath;
}

fn writeConfigItem(ctx: *const framework.CommandContext, services: *services_model.CommandServices, writer: anytype, path: []const u8) anyerror!void {
    try writer.writeByte('{');
    try appendStringField(writer, "path", path, true);

    if (registry.ConfigFieldRegistry.find(path)) |field| {
        var loader = config_runtime.loader(ctx.allocator, services.framework_context.config_store.asConfigStore());
        var loaded = try loader.loadValue(path);
        defer loaded.deinit(ctx.allocator);

        const value_present = loaded.present();
        const source = loaded.source.asText();
        const source_hint = loaded.source.hint();
        const display_value = if (field.sensitive)
            "\"[REDACTED]\""
        else
            (loaded.effectiveValueJson() orelse "null");

        try appendBoolField(writer, "found", true, false);
        try appendStringField(writer, "source", source, false);
        try appendStringField(writer, "sourceHint", source_hint, false);
        try appendBoolField(writer, "present", value_present, false);
        try writer.writeAll(",\"metadata\":{");
        try appendStringField(writer, "label", field.label, true);
        try appendStringField(writer, "description", field.description, false);
        try appendStringField(writer, "category", @tagName(field.category), false);
        try appendStringField(writer, "displayGroup", @tagName(field.display_group), false);
        try appendStringField(writer, "valueKind", @tagName(field.value_kind), false);
        try appendBoolField(writer, "required", field.required, false);
        try appendBoolField(writer, "sensitive", field.sensitive, false);
        try appendBoolField(writer, "requiresRestart", field.requires_restart, false);
        try appendStringField(writer, "riskLevel", @tagName(field.risk_level), false);
        try appendStringField(writer, "sideEffectKind", field.side_effect_kind.asText(), false);
        try appendAllowedSourcesField(writer, field.allowed_in_sources, false);
        try appendOptionalRawJsonField(writer, "defaultValue", field.default_value_json, false);
        try writer.writeByte('}');
        try writer.writeAll(",\"value\":");
        try writer.writeAll(display_value);
    } else {
        try appendBoolField(writer, "found", false, false);
        try appendStringField(writer, "errorCode", "CONFIG_FIELD_UNKNOWN", false);
    }

    try writer.writeByte('}');
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

fn appendBoolField(writer: anytype, key: []const u8, value: bool, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.writeAll(if (value) "true" else "false");
}

fn appendAllowedSourcesField(writer: anytype, sources: []const registry.AllowedSource, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, "allowedSources");
    try writer.writeByte(':');
    try writer.writeByte('[');
    for (sources, 0..) |source, index| {
        if (index > 0) try writer.writeByte(',');
        try writeJsonString(writer, @tagName(source));
    }
    try writer.writeByte(']');
}

fn appendOptionalRawJsonField(writer: anytype, key: []const u8, value_json: ?[]const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    if (value_json) |actual| {
        try writer.writeAll(actual);
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
