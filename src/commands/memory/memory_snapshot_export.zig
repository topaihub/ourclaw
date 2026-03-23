const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "memory.snapshot_export",
        .method = "memory.snapshot_export",
        .description = "Export memory snapshot JSON",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const snapshot = try services.memory_runtime.exportSnapshotJson(ctx.allocator);
    defer ctx.allocator.free(snapshot);
    const snapshot_json = try jsonString(ctx.allocator, snapshot);
    defer ctx.allocator.free(snapshot_json);
    return std.fmt.allocPrint(ctx.allocator, "{{\"snapshot\":{s},\"snapshotJson\":{s},\"entryCount\":{d},\"readyForImport\":true}}", .{ snapshot, snapshot_json, services.memory_runtime.count() });
}

fn jsonString(allocator: std.mem.Allocator, value: []const u8) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);
    try writer.writeByte('"');
    for (value) |ch| {
        switch (ch) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(ch),
        }
    }
    try writer.writeByte('"');
    return allocator.dupe(u8, buf.items);
}
