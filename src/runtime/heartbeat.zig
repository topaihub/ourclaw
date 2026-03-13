const std = @import("std");

pub const HeartbeatSnapshot = struct {
    beat_count: usize,
    last_beat_ms: ?i64,
    healthy: bool,
    age_ms: ?i64,
    stale_after_ms: i64,
};

pub const Heartbeat = struct {
    pub const default_stale_after_ms: i64 = 2_000;

    beat_count: usize = 0,
    last_beat_ms: ?i64 = null,

    pub fn init() Heartbeat {
        return .{};
    }

    pub fn beat(self: *Heartbeat) void {
        self.beat_count += 1;
        self.last_beat_ms = std.time.milliTimestamp();
    }

    pub fn snapshot(self: *const Heartbeat) HeartbeatSnapshot {
        const now = std.time.milliTimestamp();
        const age_ms = if (self.last_beat_ms) |last| now - last else null;
        return .{
            .beat_count = self.beat_count,
            .last_beat_ms = self.last_beat_ms,
            .healthy = if (age_ms) |age| age <= default_stale_after_ms else false,
            .age_ms = age_ms,
            .stale_after_ms = default_stale_after_ms,
        };
    }
};

test "heartbeat records beats" {
    var heartbeat = Heartbeat.init();
    heartbeat.beat();
    const snapshot = heartbeat.snapshot();
    try std.testing.expectEqual(@as(usize, 1), snapshot.beat_count);
    try std.testing.expect(snapshot.healthy);
}

test "heartbeat becomes unhealthy when stale" {
    var heartbeat = Heartbeat.init();
    heartbeat.beat();
    heartbeat.last_beat_ms = std.time.milliTimestamp() - (Heartbeat.default_stale_after_ms + 100);
    const snapshot = heartbeat.snapshot();
    try std.testing.expect(!snapshot.healthy);
    try std.testing.expect(snapshot.age_ms.? > Heartbeat.default_stale_after_ms);
}
