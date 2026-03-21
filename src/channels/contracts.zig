pub const ChannelDefinition = struct {
    id: []const u8,
    transport: []const u8,
    description: []const u8,
};

test "channel contracts export stability" {
    _ = ChannelDefinition;
}
