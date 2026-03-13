const std = @import("std");

pub const CronJob = struct {
    id: []u8,
    schedule: []u8,
    command: []u8,
    run_count: usize = 0,
    last_run_ms: ?i64 = null,

    pub fn deinit(self: *CronJob, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.schedule);
        allocator.free(self.command);
    }
};

pub const CronScheduler = struct {
    allocator: std.mem.Allocator,
    jobs: std.ArrayListUnmanaged(CronJob) = .empty,
    tick_count: usize = 0,
    last_tick_ms: ?i64 = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.jobs.items) |*job| job.deinit(self.allocator);
        self.jobs.deinit(self.allocator);
    }

    pub fn register(self: *Self, id: []const u8, schedule: []const u8, command: []const u8) anyerror!void {
        for (self.jobs.items) |job| {
            if (std.mem.eql(u8, job.id, id)) return error.DuplicateCronJob;
        }
        try self.jobs.append(self.allocator, .{
            .id = try self.allocator.dupe(u8, id),
            .schedule = try self.allocator.dupe(u8, schedule),
            .command = try self.allocator.dupe(u8, command),
        });
    }

    pub fn registerBuiltins(self: *Self) anyerror!void {
        try self.register("heartbeat", "*/1 * * * *", "diagnostics.summary");
    }

    pub fn count(self: *const Self) usize {
        return self.jobs.items.len;
    }

    pub fn tick(self: *Self) usize {
        const now = std.time.milliTimestamp();
        for (self.jobs.items) |*job| {
            job.run_count += 1;
            job.last_run_ms = now;
        }
        self.tick_count += self.jobs.items.len;
        self.last_tick_ms = std.time.milliTimestamp();
        return self.jobs.items.len;
    }
};

test "cron scheduler registers jobs" {
    var scheduler = CronScheduler.init(std.testing.allocator);
    defer scheduler.deinit();
    try scheduler.registerBuiltins();
    try std.testing.expectEqual(@as(usize, 1), scheduler.count());
}
