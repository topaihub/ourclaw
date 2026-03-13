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
    executed_job_count: usize = 0,
    last_executed_count: usize = 0,
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
        var executed: usize = 0;
        for (self.jobs.items) |*job| {
            if (!shouldRun(job.*, now)) continue;
            job.run_count += 1;
            job.last_run_ms = now;
            executed += 1;
        }
        self.tick_count += 1;
        self.executed_job_count += executed;
        self.last_executed_count = executed;
        self.last_tick_ms = now;
        return executed;
    }

    fn shouldRun(job: CronJob, now: i64) bool {
        const interval_ms = scheduleIntervalMs(job.schedule) orelse return true;
        const last_run_ms = job.last_run_ms orelse return true;
        return now - last_run_ms >= interval_ms;
    }

    fn scheduleIntervalMs(schedule: []const u8) ?i64 {
        if (!std.mem.startsWith(u8, schedule, "*/")) return null;
        const end = std.mem.indexOfScalar(u8, schedule, ' ') orelse return null;
        const minutes = std.fmt.parseUnsigned(u64, schedule[2..end], 10) catch return null;
        return @as(i64, @intCast(minutes * 60 * 1000));
    }
};

test "cron scheduler registers jobs" {
    var scheduler = CronScheduler.init(std.testing.allocator);
    defer scheduler.deinit();
    try scheduler.registerBuiltins();
    try std.testing.expectEqual(@as(usize, 1), scheduler.count());
}

test "cron scheduler tracks tick invocations separately from executed jobs" {
    var scheduler = CronScheduler.init(std.testing.allocator);
    defer scheduler.deinit();
    try scheduler.registerBuiltins();

    try std.testing.expectEqual(@as(usize, 1), scheduler.tick());
    try std.testing.expectEqual(@as(usize, 1), scheduler.tick_count);
    try std.testing.expectEqual(@as(usize, 1), scheduler.executed_job_count);

    try std.testing.expectEqual(@as(usize, 0), scheduler.tick());
    try std.testing.expectEqual(@as(usize, 2), scheduler.tick_count);
    try std.testing.expectEqual(@as(usize, 1), scheduler.executed_job_count);
}
