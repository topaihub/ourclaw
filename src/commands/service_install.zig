const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");
const service_contract = @import("service_contract.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "service.install", .method = "service.install", .description = "Install service", .authority = .admin, .user_data = @ptrCast(command_services), .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *const @import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const mutable: *@import("../runtime/app_context.zig").AppContext = @constCast(app);
    const changed = mutable.service_manager.install();
    const extra = try std.fmt.allocPrint(ctx.allocator, ",\"action\":\"install\",\"changed\":{s}", .{if (changed) "true" else "false"});
    defer ctx.allocator.free(extra);
    return service_contract.buildServiceSnapshotJson(ctx.allocator, mutable, extra);
}
