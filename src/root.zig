//! ourclaw — claw business application scaffold.

const std = @import("std");
pub const framework = @import("framework");

pub const APP_NAME = "ourclaw";
pub const APP_VERSION = "0.1.0";

pub const commands = @import("commands/root.zig");
pub const domain = @import("domain/root.zig");
pub const compat = @import("compat/root.zig");
pub const interfaces = @import("interfaces/root.zig");
pub const config = @import("config/field_registry.zig");
pub const security = @import("security/policy.zig");
pub const providers = @import("providers/root.zig");
pub const channels = @import("channels/root.zig");
pub const tools = @import("tools/root.zig");
pub const runtime = @import("runtime/root.zig");

test {
    std.testing.refAllDecls(@This());
}

test "metadata constants are non-empty" {
    try std.testing.expect(APP_NAME.len > 0);
    try std.testing.expect(APP_VERSION.len > 0);
}

test "ourclaw scaffold exports are available" {
    try std.testing.expectEqualStrings("framework", framework.PACKAGE_NAME);
    try std.testing.expectEqualStrings("commands", commands.MODULE_NAME);
    try std.testing.expectEqualStrings("domain", domain.MODULE_NAME);
    try std.testing.expectEqualStrings("compat", compat.MODULE_NAME);
    try std.testing.expectEqualStrings("interfaces", interfaces.MODULE_NAME);
    try std.testing.expectEqualStrings("providers", providers.MODULE_NAME);
    try std.testing.expectEqualStrings("channels", channels.MODULE_NAME);
    try std.testing.expectEqualStrings("tools", tools.MODULE_NAME);
    try std.testing.expectEqualStrings("runtime", runtime.MODULE_NAME);
}
