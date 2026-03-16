const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");
const service_contract = @import("service_contract.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{ .id = "service.restart", .method = "service.restart", .description = "Restart service", .authority = .admin, .user_data = @ptrCast(command_services), .handler = handle };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *@import("../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const restart = app.service_manager.restart();
    const extra = try std.fmt.allocPrint(ctx.allocator, ",\"action\":\"restart\",\"stopApplied\":{s},\"startApplied\":{s},\"budgetExhausted\":{s}", .{ if (restart.stop_changed) "true" else "false", if (restart.start_changed) "true" else "false", if (restart.budget_exhausted) "true" else "false" });
    defer ctx.allocator.free(extra);
    return service_contract.buildServiceSnapshotJson(ctx.allocator, app, extra);
}
