const std = @import("std");
const ourclaw = @import("ourclaw");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var app = try ourclaw.runtime.AppContext.init(allocator, .{});
    defer app.destroy();

    const default_args = [_][]const u8{"app.meta"};
    const command_args: []const []const u8 = if (args.len > 1) args[1..] else default_args[0..];
    if (ourclaw.interfaces.cli_adapter.shouldStreamLive(command_args)) {
        try ourclaw.interfaces.cli_adapter.streamLiveToStdout(allocator, app, command_args);
        return;
    }

    const output = try ourclaw.interfaces.cli_adapter.dispatchAndRenderJson(allocator, app, command_args);
    defer allocator.free(output);

    try std.fs.File.stdout().writeAll(output);
    try std.fs.File.stdout().writeAll("\n");
}
