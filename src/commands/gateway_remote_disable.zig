const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

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
    const revoke_token = if (ctx.param("revoke_token")) |field| field.value.boolean else true;
    services.tunnel_runtime.deactivate();
    const token_revoked = if (revoke_token) services.secret_store.delete("gateway:shared_token") else false;
    return std.fmt.allocPrint(ctx.allocator, "{{\"disabled\":true,\"tunnelActive\":false,\"tokenRevoked\":{s}}}", .{if (token_revoked) "true" else "false"});
}
