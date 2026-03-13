const std = @import("std");
const framework = @import("framework");
const config_migration = @import("../config/migration.zig");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "config.migrate_preview",
        .method = "config.migrate_preview",
        .description = "Preview config migration",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{.{ .key = "config_json", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} }},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const config_json = ctx.param("config_json").?.value.string;
    const preview = try config_migration.previewMigration(ctx.allocator, config_json);
    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"fromVersion\":{d},\"toVersion\":{d},\"changed\":{s},\"mappedCount\":{d},\"aliasRewriteCount\":{d},\"unknownCount\":{d}}}",
        .{
            preview.from_version,
            preview.to_version,
            if (preview.changed) "true" else "false",
            preview.mapped_count,
            preview.alias_rewrite_count,
            preview.unknown_count,
        },
    );
}
