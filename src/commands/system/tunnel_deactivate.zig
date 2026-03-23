const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "tunnel.deactivate", .method = "tunnel.deactivate", .description = "Deactivate tunnel runtime", .authority = .admin, .user_data = @ptrCast(command_services), .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    services.tunnel_runtime.deactivate();
    return std.fmt.allocPrint(ctx.allocator, "{{\"active\":false,\"activationCount\":{d},\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"lastDeactivatedMs\":{?}}}", .{ services.tunnel_runtime.activation_count, services.tunnel_runtime.health_state.asText(), services.tunnel_runtime.health_message, services.tunnel_runtime.last_deactivated_ms });
}
