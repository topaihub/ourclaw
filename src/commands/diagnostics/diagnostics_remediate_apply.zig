const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;
const support = @import("diagnostics_remediate_support.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "diagnostics.remediate_apply",
        .method = "diagnostics.remediate_apply",
        .description = "Apply a diagnostics remediation action",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{.{ .key = "action", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} }},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const action = try support.RemediationAction.parse(ctx.param("action").?.value.string);
    return support.apply(ctx, services, action);
}
