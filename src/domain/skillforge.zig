const std = @import("std");
const skills = @import("skills.zig");

pub const SkillForge = struct {
    registry: *skills.SkillRegistry,

    pub fn init(registry: *skills.SkillRegistry) SkillForge {
        return .{ .registry = registry };
    }

    pub fn installBuiltin(self: *SkillForge, id: []const u8) anyerror!void {
        if (std.mem.eql(u8, id, "doctor")) {
            try self.registry.register("doctor", "Diagnostics Doctor", "diagnostics.doctor");
            return;
        }
        if (std.mem.eql(u8, id, "summary")) {
            try self.registry.register("summary", "Diagnostics Summary", "diagnostics.summary");
            return;
        }
        return error.SkillNotFound;
    }
};

test "skillforge installs builtin skill" {
    var registry = skills.SkillRegistry.init(std.testing.allocator);
    defer registry.deinit();
    var forge = SkillForge.init(&registry);
    try forge.installBuiltin("doctor");
    try std.testing.expectEqual(@as(usize, 1), registry.count());
}
