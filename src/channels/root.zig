const std = @import("std");
const contracts = @import("contracts.zig");
const snapshots = @import("snapshots.zig");
const ingress_runtime = @import("ingress_runtime.zig");
const registry = @import("registry.zig");

pub const MODULE_NAME = "channels";

pub const ChannelDefinition = contracts.ChannelDefinition;
pub const CliChannelSnapshot = snapshots.CliChannelSnapshot;
pub const EdgeChannelSnapshot = snapshots.EdgeChannelSnapshot;
pub const CliChannelRuntime = ingress_runtime.CliChannelRuntime;
pub const EdgeChannelRuntime = ingress_runtime.EdgeChannelRuntime;
pub const ChannelRegistry = registry.ChannelRegistry;

test "channel root keeps exports stable" {
    _ = ChannelDefinition;
    _ = CliChannelSnapshot;
    _ = EdgeChannelSnapshot;
    _ = CliChannelRuntime;
    _ = EdgeChannelRuntime;
    _ = ChannelRegistry;
    try std.testing.expectEqualStrings("channels", MODULE_NAME);
}
