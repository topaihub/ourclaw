const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");
const gateway_contract = @import("gateway_contract.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "gateway.status",
        .method = "gateway.status",
        .description = "Return gateway host status",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *const @import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const status = app.gateway_host.status();
    return gateway_contract.buildGatewaySnapshotJson(ctx.allocator, status, null);
}
