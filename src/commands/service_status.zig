const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");
const service_contract = @import("service_contract.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "service.status",
        .method = "service.status",
        .description = "Return service/daemon/runtime host status",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const service = services.app_context_ptr.?; // just ensure available
    _ = service;
    const app = services.app_context_ptr.?;
    const runtime_app: *const @import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(app));
    return service_contract.buildServiceSnapshotJson(ctx.allocator, runtime_app, null);
}
