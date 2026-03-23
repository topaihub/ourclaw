const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "voice.attach", .method = "voice.attach", .description = "Attach voice runtime to audio peripheral", .authority = .admin, .user_data = @ptrCast(command_services), .params = &.{
        .{ .key = "peripheral_id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
    }, .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const peripheral_id = ctx.param("peripheral_id").?.value.string;
    services.voice_runtime.attach(services.peripheral_registry, peripheral_id) catch |err| {
        return std.fmt.allocPrint(ctx.allocator, "{{\"active\":false,\"peripheralId\":\"{s}\",\"status\":\"failed\",\"errorCode\":\"{s}\",\"healthState\":\"{s}\",\"healthMessage\":\"{s}\"}}", .{ peripheral_id, @errorName(err), services.voice_runtime.health_state.asText(), services.voice_runtime.health_message });
    };
    return std.fmt.allocPrint(ctx.allocator, "{{\"active\":true,\"peripheralId\":\"{s}\",\"status\":\"ready\",\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"attachCount\":{d},\"lastAttachedMs\":{?}}}", .{ services.voice_runtime.attached_peripheral_id, services.voice_runtime.health_state.asText(), services.voice_runtime.health_message, services.voice_runtime.attach_count, services.voice_runtime.last_attached_ms });
}
