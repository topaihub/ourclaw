const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "voice.detach", .method = "voice.detach", .description = "Detach voice runtime", .authority = .admin, .user_data = @ptrCast(command_services), .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    services.voice_runtime.detach();
    return std.fmt.allocPrint(ctx.allocator, "{{\"active\":false,\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"lastDetachedMs\":{?}}}", .{ services.voice_runtime.health_state.asText(), services.voice_runtime.health_message, services.voice_runtime.last_detached_ms });
}
