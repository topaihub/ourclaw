const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");
const gateway_contract = @import("gateway_contract.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "gateway.stream_subscribe", .method = "gateway.stream_subscribe", .description = "Subscribe gateway to stream output", .authority = .operator, .user_data = @ptrCast(command_services), .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *@import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const subscription_id = try app.gateway_host.subscribeStream(app.framework_context.event_bus.asEventBus());
    const status = app.gateway_host.status();
    const extra = try std.fmt.allocPrint(ctx.allocator, ",\"action\":\"stream_subscribe\",\"subscriptionId\":{d}", .{subscription_id});
    defer ctx.allocator.free(extra);
    return gateway_contract.buildGatewaySnapshotJson(ctx.allocator, status, extra);
}
