const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "gateway.remote.policy.status", .method = "gateway.remote.policy.status", .description = "Show remote gateway policy", .authority = .operator, .user_data = @ptrCast(command_services), .params = &.{}, .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *const @import("../../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    return std.fmt.allocPrint(ctx.allocator, "{{\"remoteEnabled\":{s},\"defaultEndpoint\":\"{s}\",\"revokeTokenOnDisable\":{s}}}", .{ if (app.effective_gateway_remote_enabled) "true" else "false", app.effective_gateway_remote_default_endpoint, if (app.effective_gateway_remote_revoke_on_disable) "true" else "false" });
}
