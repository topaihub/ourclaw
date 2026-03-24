const std = @import("std");
const framework = @import("framework");
const registry = @import("../../config/field_registry.zig");
const config_runtime = @import("../../config/runtime.zig");
const runtime_app = @import("../../runtime/app_context.zig");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "config.set",
        .method = "config.set",
        .description = "Write a config field",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "path", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "value", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "confirm_risk", .required = false, .value_kind = .boolean },
            .{ .key = "preview", .required = false, .value_kind = .boolean },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *runtime_app.AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const path = ctx.param("path").?.value.string;
    const raw_value = ctx.param("value").?.value.string;
    const confirm_risk = if (ctx.param("confirm_risk")) |field| field.value.boolean else false;
    const preview = if (ctx.param("preview")) |field| field.value.boolean else false;
    const field = registry.ConfigFieldRegistry.find(path) orelse return error.ConfigFieldUnknown;

    const parsed = try config_runtime.parseValue(ctx.allocator, field.value_kind, raw_value);
    defer {
        var mutable = parsed;
        mutable.deinit(ctx.allocator);
    }

    const updates = [_]framework.ValidationField{
        .{ .key = path, .value = parsed },
    };
    const write_fields = [_]framework.FieldDefinition{field.field_definition};

    var pipeline = app.makeConfigPipeline(write_fields[0..], registry.ConfigFieldRegistry.configRules());
    var attempt = if (preview)
        try pipeline.previewWrite(updates[0..], confirm_risk)
    else
        try pipeline.applyWrite(updates[0..], confirm_risk);
    defer attempt.deinit();

    if (!attempt.report.isOk()) return error.ValidationFailed;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);

    try writer.writeByte('{');
    try appendStringField(writer, "path", path, true);
    try appendBoolField(writer, "preview", preview, false);
    try appendBoolField(writer, "applied", attempt.applied(), false);
    try appendBoolField(writer, "confirmRisk", confirm_risk, false);
    try appendBoolField(writer, "requiresRestart", if (attempt.diff_summary) |summary| summary.requires_restart else false, false);
    try writer.writeAll(",\"fieldMeta\":{");
    try appendStringField(writer, "label", field.label, true);
    try appendStringField(writer, "category", @tagName(field.category), false);
    try appendStringField(writer, "displayGroup", @tagName(field.display_group), false);
    try appendStringField(writer, "valueKind", @tagName(field.value_kind), false);
    try appendBoolField(writer, "sensitive", field.sensitive, false);
    try appendBoolField(writer, "requiresRestart", field.requires_restart, false);
    try appendStringField(writer, "riskLevel", @tagName(field.risk_level), false);
    try appendStringField(writer, "sideEffectKind", field.side_effect_kind.asText(), false);
    try appendAllowedSourcesField(writer, field.allowed_in_sources, false);
    try appendOptionalRawJsonField(writer, "defaultValue", field.default_value_json, false);
    try writer.writeByte('}');
    try writer.writeAll(",\"diff\":");
    try writeDiffSummary(writer, attempt.diff_summary);
    try writer.writeAll(",\"writeSummary\":{");
    try appendUnsignedField(writer, "appliedCount", if (attempt.stats) |stats| stats.applied_count else 0, true);
    try appendUnsignedField(writer, "changedCount", if (attempt.stats) |stats| stats.changed_count else (if (attempt.diff_summary) |summary| summary.changed_count else 0), false);
    try appendUnsignedField(writer, "changeLogCount", attempt.change_log_count, false);
    try appendUnsignedField(writer, "sideEffectCount", attempt.side_effect_count, false);
    try appendUnsignedField(writer, "postWriteHookCount", attempt.post_write_hook_count, false);
    try writer.writeByte('}');
    try writer.writeByte('}');

    return ctx.allocator.dupe(u8, buf.items);
}

fn writeDiffSummary(writer: anytype, diff_summary: ?framework.ConfigDiffSummary) anyerror!void {
    if (diff_summary == null) {
        try writer.writeAll("null");
        return;
    }

    const summary = diff_summary.?;
    try writer.writeByte('{');
    try appendUnsignedField(writer, "changedCount", summary.changed_count, true);
    try appendBoolField(writer, "requiresRestart", summary.requires_restart, false);
    try writer.writeAll(",\"changes\":[");
    for (summary.changes, 0..) |change, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try appendStringField(writer, "path", change.path, true);
        try appendStringField(writer, "kind", change.kind.asText(), false);
        try appendBoolField(writer, "changed", change.changed, false);
        try appendBoolField(writer, "sensitive", change.sensitive, false);
        try appendBoolField(writer, "requiresRestart", change.requires_restart, false);
        try appendStringField(writer, "sideEffectKind", change.side_effect_kind.asText(), false);
        try appendStringField(writer, "valueKind", if (change.value_kind) |kind| @tagName(kind) else "unknown", false);
        try appendOptionalRawJsonField(writer, "oldValue", change.old_value_json, false);
        try appendRawJsonField(writer, "newValue", change.new_value_json, false);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
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

fn appendRawJsonField(writer: anytype, key: []const u8, value_json: []const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try writeJsonString(writer, key);
    try writer.writeByte(':');
    try writer.writeAll(value_json);
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
