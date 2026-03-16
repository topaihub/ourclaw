const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");
const gateway_contract = @import("gateway_contract.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "gateway.start", .method = "gateway.start", .description = "Start gateway host", .authority = .admin, .user_data = @ptrCast(command_services), .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *@import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const before = app.gateway_host.status();
    app.runtime_host.start();
    const status = app.gateway_host.status();
    const extra = try std.fmt.allocPrint(ctx.allocator, ",\"action\":\"start\",\"changed\":{s},\"hostRunning\":{s}", .{
        if (!before.running and status.running) "true" else "false",
        if (app.runtime_host.status().running) "true" else "false",
    });
    defer ctx.allocator.free(extra);
    return gateway_contract.buildGatewaySnapshotJson(ctx.allocator, status, extra);
}
