const std = @import("std");
const framework = @import("framework");
const compat_import = @import("../../compat/config_import.zig");
const runtime_app = @import("../../runtime/app_context.zig");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "config.compat_import",
        .method = "config.compat_import",
        .description = "Import legacy compatible config",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "source_json", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "source_kind", .required = false, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "preview", .required = false, .value_kind = .boolean },
            .{ .key = "confirm_risk", .required = false, .value_kind = .boolean },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *runtime_app.AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const source_json = ctx.param("source_json").?.value.string;
    const source_kind = if (ctx.param("source_kind")) |field|
        try compat_import.parseSourceKind(field.value.string)
    else
        compat_import.SourceKind.generic;
    const preview_only = if (ctx.param("preview")) |field| field.value.boolean else false;
    const confirm_risk = if (ctx.param("confirm_risk")) |field| field.value.boolean else false;

    if (preview_only) {
        const preview = try compat_import.previewImport(ctx.allocator, source_kind, source_json);
        return std.fmt.allocPrint(
            ctx.allocator,
            "{{\"sourceKind\":\"{s}\",\"preview\":true,\"fromVersion\":{d},\"toVersion\":{d},\"changed\":{s},\"mappedCount\":{d},\"aliasRewriteCount\":{d},\"unknownCount\":{d}}}",
            .{
                @tagName(preview.source_kind),
                preview.migration_preview.from_version,
                preview.migration_preview.to_version,
                if (preview.migration_preview.changed) "true" else "false",
                preview.migration_preview.mapped_count,
                preview.migration_preview.alias_rewrite_count,
                preview.migration_preview.unknown_count,
            },
        );
    }

    var pipeline = app.makeConfigPipeline(null, null);
    var result = try compat_import.applyImport(ctx.allocator, source_kind, source_json, &pipeline, confirm_risk);
    defer result.deinit(ctx.allocator);

    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"sourceKind\":\"{s}\",\"preview\":false,\"fromVersion\":{d},\"toVersion\":{d},\"changed\":{s},\"mappedCount\":{d},\"aliasRewriteCount\":{d},\"unknownCount\":{d},\"applied\":{s},\"changedCount\":{d},\"requiresRestart\":{s}}}",
        .{
            @tagName(source_kind),
            result.preview.from_version,
            result.preview.to_version,
            if (result.preview.changed) "true" else "false",
            result.preview.mapped_count,
            result.preview.alias_rewrite_count,
            result.preview.unknown_count,
            if (result.attempt.applied()) "true" else "false",
            if (result.attempt.stats) |stats| stats.changed_count else 0,
            if (result.attempt.requiresRestart()) "true" else "false",
        },
    );
}
