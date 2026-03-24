const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "gateway.remote.policy.set", .method = "gateway.remote.policy.set", .description = "Set remote gateway policy", .authority = .operator, .user_data = @ptrCast(command_services), .params = &.{ .{ .key = "remote_enabled", .required = false, .value_kind = .boolean }, .{ .key = "default_endpoint", .required = false, .value_kind = .string, .rules = &.{.non_empty_string} }, .{ .key = "revoke_token_on_disable", .required = false, .value_kind = .boolean } }, .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *@import("../../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    if (ctx.param("remote_enabled")) |field| app.effective_gateway_remote_enabled = field.value.boolean;
    if (ctx.param("default_endpoint")) |field| {
        app.allocator.free(app.effective_gateway_remote_default_endpoint);
        app.effective_gateway_remote_default_endpoint = try app.allocator.dupe(u8, field.value.string);
    }
    if (ctx.param("revoke_token_on_disable")) |field| app.effective_gateway_remote_revoke_on_disable = field.value.boolean;
    return std.fmt.allocPrint(ctx.allocator, "{{\"remoteEnabled\":{s},\"defaultEndpoint\":\"{s}\",\"revokeTokenOnDisable\":{s}}}", .{ if (app.effective_gateway_remote_enabled) "true" else "false", app.effective_gateway_remote_default_endpoint, if (app.effective_gateway_remote_revoke_on_disable) "true" else "false" });
}
