const std = @import("std");
const framework = @import("framework");
const config_migration = @import("../../config/migration.zig");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

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
    var prepared = try config_migration.prepareMigration(ctx.allocator, config_json);
    defer prepared.deinit(ctx.allocator);
    const preview = prepared.preview;

    var unknown_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer unknown_buf.deinit(ctx.allocator);
    const unknown_writer = unknown_buf.writer(ctx.allocator);
    try unknown_writer.writeByte('[');
    for (prepared.unknown_paths, 0..) |path, index| {
        if (index > 0) try unknown_writer.writeByte(',');
        try unknown_writer.print("\"{s}\"", .{path});
    }
    try unknown_writer.writeByte(']');

    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"fromVersion\":{d},\"toVersion\":{d},\"changed\":{s},\"mappedCount\":{d},\"aliasRewriteCount\":{d},\"unknownCount\":{d},\"unknownPaths\":{s}}}",
        .{
            preview.from_version,
            preview.to_version,
            if (preview.changed) "true" else "false",
            preview.mapped_count,
            preview.alias_rewrite_count,
            preview.unknown_count,
            unknown_buf.items,
        },
    );
}
