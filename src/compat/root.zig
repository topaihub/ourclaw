const std = @import("std");

pub const MODULE_NAME = "compat";
pub const config_import = @import("config_import.zig");
pub const http_util = @import("http_util.zig");

pub const ModuleStage = enum {
    scaffold,
};

pub const MODULE_STAGE: ModuleStage = .scaffold;

test "compat scaffold exports are stable" {
    try std.testing.expectEqualStrings("compat", MODULE_NAME);
    try std.testing.expect(MODULE_STAGE == .scaffold);
    _ = http_util.HttpResponse;
    _ = config_import.SourceKind;
}
