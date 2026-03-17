const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "devices.list",
        .method = "devices.list",
        .description = "List paired devices, runtime nodes, and peripherals",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);

    var pending_pairings: usize = 0;
    var approved_pairings: usize = 0;
    for (services.pairing_registry.items()) |request| {
        switch (request.state) {
            .pending => pending_pairings += 1,
            .approved => approved_pairings += 1,
            .rejected => {},
        }
    }

    var ready_nodes: usize = 0;
    var broken_nodes: usize = 0;
    for (services.hardware_registry.nodes.items) |node| {
        if (node.health_state == .ready) ready_nodes += 1 else broken_nodes += 1;
    }

    var ready_peripherals: usize = 0;
    var broken_peripherals: usize = 0;
    for (services.peripheral_registry.devices.items) |device| {
        if (device.health_state == .ready) ready_peripherals += 1 else broken_peripherals += 1;
    }

    return std.fmt.allocPrint(
        ctx.allocator,
        "{{\"requirePairing\":{s},\"pairing\":{{\"total\":{d},\"pending\":{d},\"approved\":{d}}},\"nodes\":{{\"total\":{d},\"ready\":{d},\"broken\":{d}}},\"peripherals\":{{\"total\":{d},\"ready\":{d},\"broken\":{d}}}}}",
        .{
            if (@as(*const @import("../runtime/app_context.zig").AppContext, @ptrCast(@alignCast(services.app_context_ptr.?))).effective_gateway_require_pairing) "true" else "false",
            services.pairing_registry.count(),
            pending_pairings,
            approved_pairings,
            services.hardware_registry.count(),
            ready_nodes,
            broken_nodes,
            services.peripheral_registry.count(),
            ready_peripherals,
            broken_peripherals,
        },
    );
}
