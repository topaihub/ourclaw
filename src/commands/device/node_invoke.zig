const std = @import("std");
const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "node.invoke",
        .method = "node.invoke",
        .description = "Invoke a safe action on a runtime node",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "id", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
            .{ .key = "action", .required = true, .value_kind = .string, .rules = &.{.non_empty_string} },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *const @import("../../runtime/app_context.zig").AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const id = ctx.param("id").?.value.string;
    const action = ctx.param("action").?.value.string;

    var trace = try framework.StepTrace.begin(ctx.allocator, app.framework_context.logger, "node/invoke", action, 500);
    defer trace.deinit();

    const node = if (std.mem.eql(u8, action, "health_check"))
        services.hardware_registry.find(id) orelse {
            trace.finish("HardwareNodeNotFound");
            return error.HardwareNodeNotFound;
        }
    else if (std.mem.eql(u8, action, "probe"))
        services.hardware_registry.probeById(id) catch |err| {
            trace.finish(@errorName(err));
            return err;
        }
    else {
        trace.finish("UnsupportedNodeAction");
        return error.UnsupportedNodeAction;
    };

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.print("{{\"id\":\"{s}\",\"action\":\"{s}\",\"kind\":\"{s}\",\"healthState\":\"{s}\",\"healthMessage\":\"{s}\",\"probeCount\":{d},\"lastCheckedMs\":{?},\"lastErrorCode\":", .{
        node.id,
        action,
        node.kind,
        node.health_state.asText(),
        node.health_message,
        node.probe_count,
        node.last_checked_ms,
    });
    if (node.last_error_code) |value| {
        try writer.print("\"{s}\"", .{value});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeByte('}');
    trace.finish(null);
    return ctx.allocator.dupe(u8, buf.items);
}
