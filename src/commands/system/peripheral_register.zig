const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "peripheral.register", .method = "peripheral.register", .description = "Register peripheral device", .authority = .admin, .user_data = @ptrCast(command_services), .params = &.{
        .{ .key = "id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
        .{ .key = "kind", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
    }, .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const id = ctx.param("id").?.value.string;
    const kind = ctx.param("kind").?.value.string;
    services.peripheral_registry.register(id, kind) catch |err| {
        const health_message = switch (err) {
            error.PeripheralUnsupportedKind => "unsupported_kind",
            error.PeripheralOffline => "device_offline",
            error.DuplicatePeripheral => "duplicate_peripheral",
            else => "registration_failed",
        };
        return std.fmt.allocPrint(ctx.allocator, "{{\"registered\":false,\"id\":\"{s}\",\"kind\":\"{s}\",\"status\":\"failed\",\"errorCode\":\"{s}\",\"healthState\":\"broken\",\"healthMessage\":\"{s}\"}}", .{ id, kind, @errorName(err), health_message });
    };
    const device = services.peripheral_registry.find(id).?;
    return std.fmt.allocPrint(ctx.allocator, "{{\"registered\":true,\"id\":\"{s}\",\"kind\":\"{s}\",\"registeredAtMs\":{d},\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"probeCount\":{d},\"lastCheckedMs\":{?}}}", .{ id, device.kind, device.registered_at_ms, device.health_state.asText(), device.health_message, device.probe_count, device.last_checked_ms });
}
