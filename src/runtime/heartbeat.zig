const std = @import("std");

pub const HeartbeatSnapshot = struct {
    beat_count: usize,
    last_beat_ms: ?i64,
    healthy: bool,
    age_ms: ?i64,
};

pub const Heartbeat = struct {
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
        return .{
            .beat_count = self.beat_count,
            .last_beat_ms = self.last_beat_ms,
            .healthy = self.last_beat_ms != null,
            .age_ms = if (self.last_beat_ms) |last| now - last else null,
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
