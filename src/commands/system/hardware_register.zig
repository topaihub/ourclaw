const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "hardware.register", .method = "hardware.register", .description = "Register hardware node", .authority = .admin, .user_data = @ptrCast(command_services), .params = &.{
        .{ .key = "id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
        .{ .key = "label", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
    }, .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const id = ctx.param("id").?.value.string;
    const label = ctx.param("label").?.value.string;
    services.hardware_registry.register(id, label) catch |err| {
        const health_message = switch (err) {
            error.HardwareUnsupportedKind => "unsupported_kind",
            error.HardwareNodeOffline => "device_offline",
            error.DuplicateHardwareNode => "duplicate_node",
            else => "registration_failed",
        };
        return std.fmt.allocPrint(ctx.allocator, "{{\"registered\":false,\"id\":\"{s}\",\"status\":\"failed\",\"errorCode\":\"{s}\",\"healthState\":\"broken\",\"healthMessage\":\"{s}\"}}", .{ id, @errorName(err), health_message });
    };
    const node = services.hardware_registry.find(id).?;
    return std.fmt.allocPrint(ctx.allocator, "{{\"registered\":true,\"id\":\"{s}\",\"kind\":\"{s}\",\"registeredAtMs\":{d},\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"probeCount\":{d},\"lastCheckedMs\":{?}}}", .{ id, node.kind, node.registered_at_ms, node.health_state.asText(), node.health_message, node.probe_count, node.last_checked_ms });
}
