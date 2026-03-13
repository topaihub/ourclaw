const std = @import("std");

pub const MODULE_NAME = "interfaces";

pub const cli_adapter = @import("cli_adapter.zig");
pub const bridge_adapter = @import("bridge_adapter.zig");
pub const http_adapter = @import("http_adapter.zig");

test "interfaces exports are stable" {
    try std.testing.expectEqualStrings("interfaces", MODULE_NAME);
    _ = cli_adapter.OwnedRequest;
    _ = bridge_adapter.BridgeRequest;
    _ = http_adapter.HttpResponse;
}
