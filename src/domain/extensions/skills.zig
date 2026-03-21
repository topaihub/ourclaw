const std = @import("std");

pub const SkillSource = enum {
    builtin,
    external,

    pub fn asText(self: SkillSource) []const u8 {
        return switch (self) {
            .builtin => "builtin",
            .external => "external",
        };
    }
};

pub const SkillRunStatus = enum {
    never_run,
    completed,
    failed,

    pub fn asText(self: SkillRunStatus) []const u8 {
        return switch (self) {
            .never_run => "never_run",
            .completed => "completed",
            .failed => "failed",
        };
    }
};

pub const SkillHealthState = enum {
    ready,
    degraded,
    broken,

    pub fn asText(self: SkillHealthState) []const u8 {
        return switch (self) {
            .ready => "ready",
            .degraded => "degraded",
            .broken => "broken",
        };
    }
};

pub const SkillHealth = struct {
    state: SkillHealthState,
    message: []const u8,
};

pub const SkillManifest = struct {
    id: []u8,
    label: []u8,
    entry_command: []u8,
    source: SkillSource,
    installed_at_ms: i64,
    run_count: usize = 0,
    last_run_ms: ?i64 = null,
    last_run_status: SkillRunStatus = .never_run,
    last_error_code: ?[]u8 = null,

    pub fn deinit(self: *SkillManifest, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.label);
        allocator.free(self.entry_command);
        if (self.last_error_code) |value| allocator.free(value);
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

    pub fn register(self: *Self, id: []const u8, label: []const u8, entry_command: []const u8, source: SkillSource) anyerror!void {
        if (self.find(id) != null) return error.DuplicateSkill;
        try self.skills.append(self.allocator, .{
            .id = try self.allocator.dupe(u8, id),
            .label = try self.allocator.dupe(u8, label),
            .entry_command = try self.allocator.dupe(u8, entry_command),
            .source = source,
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

    pub fn markRunSuccess(self: *Self, id: []const u8) void {
        const skill = self.findMutable(id) orelse return;
        skill.run_count += 1;
        skill.last_run_ms = std.time.milliTimestamp();
        skill.last_run_status = .completed;
        if (skill.last_error_code) |value| self.allocator.free(value);
        skill.last_error_code = null;
    }

    pub fn markRunFailure(self: *Self, id: []const u8, error_code: []const u8) anyerror!void {
        const skill = self.findMutable(id) orelse return;
        skill.run_count += 1;
        skill.last_run_ms = std.time.milliTimestamp();
        skill.last_run_status = .failed;
        if (skill.last_error_code) |value| self.allocator.free(value);
        skill.last_error_code = try self.allocator.dupe(u8, error_code);
    }

    pub fn health(skill: *const SkillManifest, command_exists: bool) SkillHealth {
        if (!command_exists) return .{ .state = .broken, .message = "entry_command_missing" };
        if (skill.last_error_code != null) return .{ .state = .degraded, .message = "last_run_failed" };
        return .{ .state = .ready, .message = if (skill.run_count == 0) "installed" else "ready" };
    }
};

test "skill registry registers skills" {
    var registry = SkillRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register("doctor", "Diagnostics Doctor", "diagnostics.doctor", .builtin);
    try std.testing.expectEqual(@as(usize, 1), registry.count());
}

test "skill registry tracks run status and health" {
    var registry = SkillRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.register("doctor", "Diagnostics Doctor", "diagnostics.doctor", .builtin);
    const installed = registry.find("doctor").?;
    try std.testing.expectEqualStrings("builtin", installed.source.asText());
    try std.testing.expectEqualStrings("ready", SkillRegistry.health(installed, true).state.asText());

    try registry.markRunFailure("doctor", "COMMAND_FAILED");
    const failed = registry.find("doctor").?;
    try std.testing.expectEqualStrings("failed", failed.last_run_status.asText());
    try std.testing.expectEqualStrings("degraded", SkillRegistry.health(failed, true).state.asText());
    try std.testing.expectEqualStrings("broken", SkillRegistry.health(failed, false).state.asText());
}
