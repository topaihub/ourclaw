const std = @import("std");

pub const SkillManifest = struct {
    id: []u8,
    label: []u8,
    entry_command: []u8,
    installed_at_ms: i64,
    run_count: usize = 0,
    last_run_ms: ?i64 = null,

    pub fn deinit(self: *SkillManifest, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.label);
        allocator.free(self.entry_command);
    }
};

pub const SkillRegistry = struct {
    allocator: std.mem.Allocator,
    skills: std.ArrayListUnmanaged(SkillManifest) = .empty,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.skills.items) |*skill| skill.deinit(self.allocator);
        self.skills.deinit(self.allocator);
    }

    pub fn register(self: *Self, id: []const u8, label: []const u8, entry_command: []const u8) anyerror!void {
        if (self.find(id) != null) return error.DuplicateSkill;
        try self.skills.append(self.allocator, .{
            .id = try self.allocator.dupe(u8, id),
            .label = try self.allocator.dupe(u8, label),
            .entry_command = try self.allocator.dupe(u8, entry_command),
            .installed_at_ms = std.time.milliTimestamp(),
        });
    }

    pub fn count(self: *const Self) usize {
        return self.skills.items.len;
    }

    pub fn find(self: *const Self, id: []const u8) ?*const SkillManifest {
        for (self.skills.items) |*skill| {
            if (std.mem.eql(u8, skill.id, id)) return skill;
        }
        return null;
    }

    pub fn findMutable(self: *Self, id: []const u8) ?*SkillManifest {
        for (self.skills.items) |*skill| {
            if (std.mem.eql(u8, skill.id, id)) return skill;
        }
        return null;
    }

    pub fn markRun(self: *Self, id: []const u8) void {
        const skill = self.findMutable(id) orelse return;
        skill.run_count += 1;
        skill.last_run_ms = std.time.milliTimestamp();
    }
};

test "skill registry registers skills" {
    var registry = SkillRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register("doctor", "Diagnostics Doctor", "diagnostics.doctor");
    try std.testing.expectEqual(@as(usize, 1), registry.count());
}
