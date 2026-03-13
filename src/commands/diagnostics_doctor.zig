const std = @import("std");
const framework = @import("framework");
const services_model = @import("../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "diagnostics.doctor",
        .method = "diagnostics.doctor",
        .description = "Run basic runtime health checks",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);

    var issues: std.ArrayListUnmanaged([]const u8) = .empty;
    defer issues.deinit(ctx.allocator);

    if (services.secret_store.count() == 0) try issues.append(ctx.allocator, "no secrets configured");
    if (services.provider_registry.count() == 0) try issues.append(ctx.allocator, "provider registry is empty");
    if (services.channel_registry.count() == 0) try issues.append(ctx.allocator, "channel registry is empty");
    if (services.tool_registry.count() == 0) try issues.append(ctx.allocator, "tool registry is empty");
    if (services.framework_context.command_registry.count() == 0) try issues.append(ctx.allocator, "command registry is empty");

    var maybe_openai_health = services.provider_registry.health(ctx.allocator, "openai") catch null;
    defer if (maybe_openai_health) |*health| health.deinit(ctx.allocator);
    if (maybe_openai_health == null or !maybe_openai_health.?.healthy) {
        try issues.append(ctx.allocator, "openai provider is not healthy");
    }

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(ctx.allocator);
    const writer = buf.writer(ctx.allocator);
    try writer.writeByte('{');
    try writer.print("\"status\":\"{s}\"", .{if (issues.items.len == 0) "ok" else "degraded"});
    try writer.writeAll(",\"issueCount\":");
    try writer.print("{d}", .{issues.items.len});
    try writer.writeAll(",\"issues\":[");
    for (issues.items, 0..) |issue, index| {
        if (index > 0) try writer.writeByte(',');
        try writer.print("\"{s}\"", .{issue});
    }
    try writer.writeByte(']');
    try writer.writeAll(",\"checks\":{");
    try writer.print("\"providerCount\":{d},\"channelCount\":{d},\"toolCount\":{d},\"commandCount\":{d},\"secretCount\":{d}", .{
        services.provider_registry.count(),
        services.channel_registry.count(),
        services.tool_registry.count(),
        services.framework_context.command_registry.count(),
        services.secret_store.count(),
    });
    try writer.writeByte('}');
    try writer.writeByte('}');
    return ctx.allocator.dupe(u8, buf.items);
}
