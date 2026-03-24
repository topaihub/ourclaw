const std = @import("std");
const framework = @import("framework");
const config_migration = @import("../../config/migration.zig");
const runtime_app = @import("../../runtime/app_context.zig");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "config.migrate_apply",
        .method = "config.migrate_apply",
        .description = "Apply config migration",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "config_json", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "confirm_risk", .required = false, .value_kind = .boolean },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *runtime_app.AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const config_json = ctx.param("config_json").?.value.string;
    const confirm_risk = if (ctx.param("confirm_risk")) |field| field.value.boolean else false;

    var pipeline = app.makeConfigPipeline(null, null);
    var result = try config_migration.applyMigration(ctx.allocator, config_json, &pipeline, confirm_risk);
    defer result.deinit(ctx.allocator);

    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"fromVersion\":{d},\"toVersion\":{d},\"changed\":{s},\"mappedCount\":{d},\"aliasRewriteCount\":{d},\"unknownCount\":{d},\"applied\":{s},\"changedCount\":{d},\"requiresRestart\":{s}}}",
        .{
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
