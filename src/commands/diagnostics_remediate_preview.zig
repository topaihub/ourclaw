const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");
const support = @import("diagnostics_remediate_support.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "diagnostics.remediate_preview",
        .method = "diagnostics.remediate_preview",
        .description = "Preview a diagnostics remediation action",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{.{ .key = "action", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} }},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const action = try support.RemediationAction.parse(ctx.param("action").?.value.string);
    const result = support.preview(services, action);
    return std.fmt.allocPrint(ctx.allocator, "{{\"action\":\"{s}\",\"wouldChange\":{s},\"requiresRestart\":{s},\"summary\":\"{s}\"}}", .{ @tagName(result.action), if (result.would_change) "true" else "false", if (result.requires_restart) "true" else "false", result.summary });
}
