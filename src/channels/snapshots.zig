pub const CliChannelSnapshot = struct {
    request_count: usize,
    live_stream_count: usize,
    last_method: ?[]const u8,
    last_route_group: []const u8,
    health_state: []const u8,
    last_session_id: ?[]const u8,
};

pub const EdgeChannelSnapshot = struct {
    request_count: usize,
    stream_count: usize,
    last_target: ?[]const u8,
    last_route_group: []const u8,
    health_state: []const u8,
    last_session_id: ?[]const u8,
};

test "channel snapshot exports stable" {
    _ = CliChannelSnapshot;
    _ = EdgeChannelSnapshot;
}
