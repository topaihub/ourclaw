const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "gateway.remote.disable",
        .method = "gateway.remote.disable",
        .description = "Disable remote gateway access",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "revoke_token", .required = false, .value_kind = .boolean },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *const @import("../../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    var trace = try framework.StepTrace.begin(ctx.allocator, app.framework_context.logger, "gateway/remote", "disable", 500);
    defer trace.deinit();
    const revoke_token = if (ctx.param("revoke_token")) |field| field.value.boolean else app.effective_gateway_remote_revoke_on_disable;
    services.tunnel_runtime.deactivate();
    const token_revoked = if (revoke_token) services.secret_store.delete("gateway:shared_token") else false;
    trace.finish(null);
    return std.fmt.allocPrint(ctx.allocator, "{{\"disabled\":true,\"tunnelActive\":false,\"tokenRevoked\":{s}}}", .{if (token_revoked) "true" else "false"});
}
