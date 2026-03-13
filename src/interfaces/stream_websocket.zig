const std = @import("std");
const sink_model = @import("stream_sink.zig");

pub const ByteSink = sink_model.ByteSink;

pub const ClientFrame = struct {
    fin: bool,
    opcode: u8,
    payload: []u8,

    pub fn deinit(self: *ClientFrame, allocator: std.mem.Allocator) void {
        allocator.free(self.payload);
    }
};

pub fn computeAcceptKey(key_b64: []const u8) [28]u8 {
    var sha1 = std.crypto.hash.Sha1.init(.{});
    sha1.update(key_b64);
    sha1.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");

    var digest: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
    sha1.final(&digest);

    var accept_key: [28]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(&accept_key, &digest);
    return accept_key;
}

pub fn writeTextFrame(sink: ByteSink, payload: []const u8) anyerror!void {
    var header: [10]u8 = undefined;
    const header_len = buildServerFrameHeader(&header, 0x1, payload.len);
    try sink.writeAll(header[0..header_len]);
    try sink.writeAll(payload);
    try sink.flush();
}

pub fn writeCloseFrame(sink: ByteSink) anyerror!void {
    const frame = [_]u8{ 0x88, 0x00 };
    try sink.writeAll(frame[0..]);
    try sink.flush();
}

pub fn writeCloseFrameWithReason(sink: ByteSink, close_code: u16, close_reason: []const u8) anyerror!void {
    if (close_reason.len > 123) return error.CloseReasonTooLong;

    var header: [10]u8 = undefined;
    const payload_len = 2 + close_reason.len;
    const header_len = buildServerFrameHeader(&header, 0x8, payload_len);
    var code_bytes = [2]u8{
        @intCast((close_code >> 8) & 0xFF),
        @intCast(close_code & 0xFF),
    };

    try sink.writeAll(header[0..header_len]);
    try sink.writeAll(&code_bytes);
    try sink.writeAll(close_reason);
    try sink.flush();
}

pub const ClosePayload = struct {
    close_code: ?u16,
    close_reason: ?[]const u8,
};

pub fn parseClosePayload(payload: []const u8) anyerror!ClosePayload {
    if (payload.len == 0) {
        return .{ .close_code = null, .close_reason = null };
    }
    if (payload.len == 1) return error.InvalidClosePayload;

    const close_code = (@as(u16, payload[0]) << 8) | payload[1];
    const close_reason = if (payload.len > 2) payload[2..] else null;
    return .{
        .close_code = close_code,
        .close_reason = close_reason,
    };
}

pub fn buildClientFrame(buf: []u8, opcode: u8, payload: []const u8, mask_key: [4]u8) anyerror!usize {
    var stream = std.io.fixedBufferStream(buf);
    const writer = stream.writer();

    try writer.writeByte(0x80 | opcode);
    if (payload.len <= 125) {
        try writer.writeByte(0x80 | @as(u8, @intCast(payload.len)));
    } else if (payload.len <= 65535) {
        try writer.writeByte(0x80 | 126);
        try writer.writeByte(@intCast((payload.len >> 8) & 0xFF));
        try writer.writeByte(@intCast(payload.len & 0xFF));
    } else {
        try writer.writeByte(0x80 | 127);
        const payload_len: u64 = @intCast(payload.len);
        try writer.writeByte(@intCast((payload_len >> 56) & 0xFF));
        try writer.writeByte(@intCast((payload_len >> 48) & 0xFF));
        try writer.writeByte(@intCast((payload_len >> 40) & 0xFF));
        try writer.writeByte(@intCast((payload_len >> 32) & 0xFF));
        try writer.writeByte(@intCast((payload_len >> 24) & 0xFF));
        try writer.writeByte(@intCast((payload_len >> 16) & 0xFF));
        try writer.writeByte(@intCast((payload_len >> 8) & 0xFF));
        try writer.writeByte(@intCast(payload_len & 0xFF));
    }

    try writer.writeAll(&mask_key);
    for (payload, 0..) |byte, index| {
        try writer.writeByte(byte ^ mask_key[index % 4]);
    }

    return stream.pos;
}

pub fn parseClientFrame(allocator: std.mem.Allocator, bytes: []const u8) anyerror!ClientFrame {
    if (bytes.len < 2) return error.InsufficientData;

    const fin = (bytes[0] & 0x80) != 0;
    const opcode = bytes[0] & 0x0F;
    const masked = (bytes[1] & 0x80) != 0;
    if (!masked) return error.UnmaskedClientFrame;

    var payload_len: usize = bytes[1] & 0x7F;
    var offset: usize = 2;
    if (payload_len == 126) {
        if (bytes.len < 4) return error.InsufficientData;
        payload_len = (@as(usize, bytes[2]) << 8) | bytes[3];
        offset = 4;
    } else if (payload_len == 127) {
        if (bytes.len < 10) return error.InsufficientData;
        payload_len = 0;
        for (bytes[2..10]) |byte| {
            payload_len = (payload_len << 8) | byte;
        }
        offset = 10;
    }

    if (payload_len > 64 * 1024) return error.FrameTooLarge;
    if (bytes.len < offset + 4 + payload_len) return error.InsufficientData;

    const mask_key = [4]u8{ bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3] };
    offset += 4;

    const payload = try allocator.dupe(u8, bytes[offset .. offset + payload_len]);
    errdefer allocator.free(payload);
    applyMask(payload, mask_key);

    return .{
        .fin = fin,
        .opcode = opcode,
        .payload = payload,
    };
}

pub fn readClientFrame(allocator: std.mem.Allocator, stream: *std.net.Stream) anyerror!ClientFrame {
    var header: [2]u8 = undefined;
    try readExact(stream, &header);

    const masked = (header[1] & 0x80) != 0;
    if (!masked) return error.UnmaskedClientFrame;

    var payload_len: usize = header[1] & 0x7F;
    var ext_len: usize = 0;
    var ext: [8]u8 = [_]u8{0} ** 8;
    if (payload_len == 126) {
        ext_len = 2;
    } else if (payload_len == 127) {
        ext_len = 8;
    }
    if (ext_len > 0) {
        try readExact(stream, ext[0..ext_len]);
        payload_len = 0;
        for (ext[0..ext_len]) |byte| {
            payload_len = (payload_len << 8) | byte;
        }
    }
    if (payload_len > 64 * 1024) return error.FrameTooLarge;

    var mask_key: [4]u8 = undefined;
    try readExact(stream, &mask_key);

    const payload = try allocator.alloc(u8, payload_len);
    errdefer allocator.free(payload);
    try readExact(stream, payload);
    applyMask(payload, mask_key);

    return .{
        .fin = (header[0] & 0x80) != 0,
        .opcode = header[0] & 0x0F,
        .payload = payload,
    };
}

pub const ParsedServerFrame = struct {
    fin: bool,
    opcode: u8,
    payload_len: usize,
    header_len: usize,
};

pub fn parseServerFrame(bytes: []const u8) anyerror!ParsedServerFrame {
    if (bytes.len < 2) return error.InsufficientData;
    const fin = (bytes[0] & 0x80) != 0;
    const opcode = bytes[0] & 0x0F;
    if ((bytes[1] & 0x80) != 0) return error.UnexpectedMaskedServerFrame;

    var payload_len: usize = bytes[1] & 0x7F;
    var header_len: usize = 2;
    if (payload_len == 126) {
        if (bytes.len < 4) return error.InsufficientData;
        payload_len = (@as(usize, bytes[2]) << 8) | bytes[3];
        header_len = 4;
    } else if (payload_len == 127) {
        if (bytes.len < 10) return error.InsufficientData;
        payload_len = 0;
        for (bytes[2..10]) |b| {
            payload_len = (payload_len << 8) | b;
        }
        header_len = 10;
    }

    if (bytes.len < header_len + payload_len) return error.InsufficientData;
    return .{
        .fin = fin,
        .opcode = opcode,
        .payload_len = payload_len,
        .header_len = header_len,
    };
}

fn buildServerFrameHeader(header: *[10]u8, opcode: u8, payload_len: usize) usize {
    header[0] = 0x80 | opcode;
    if (payload_len <= 125) {
        header[1] = @intCast(payload_len);
        return 2;
    }
    if (payload_len <= 65535) {
        header[1] = 126;
        header[2] = @intCast((payload_len >> 8) & 0xFF);
        header[3] = @intCast(payload_len & 0xFF);
        return 4;
    }

    header[1] = 127;
    const value: u64 = @intCast(payload_len);
    header[2] = @intCast((value >> 56) & 0xFF);
    header[3] = @intCast((value >> 48) & 0xFF);
    header[4] = @intCast((value >> 40) & 0xFF);
    header[5] = @intCast((value >> 32) & 0xFF);
    header[6] = @intCast((value >> 24) & 0xFF);
    header[7] = @intCast((value >> 16) & 0xFF);
    header[8] = @intCast((value >> 8) & 0xFF);
    header[9] = @intCast(value & 0xFF);
    return 10;
}

pub fn applyMask(payload: []u8, mask_key: [4]u8) void {
    for (payload, 0..) |*byte, index| {
        byte.* ^= mask_key[index % 4];
    }
}

fn readExact(stream: *std.net.Stream, buf: []u8) anyerror!void {
    var offset: usize = 0;
    while (offset < buf.len) {
        const read_count = try stream.read(buf[offset..]);
        if (read_count == 0) return error.EndOfStream;
        offset += read_count;
    }
}

test "stream websocket computes accept key" {
    const accept = computeAcceptKey("dGhlIHNhbXBsZSBub25jZQ==");
    try std.testing.expectEqualStrings("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", &accept);
}

test "stream websocket writes text frame" {
    var sink = sink_model.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();

    try writeTextFrame(sink.asByteSink(), "hello");

    const bytes = try sink.toOwnedSlice();
    defer std.testing.allocator.free(bytes);

    const frame = try parseServerFrame(bytes);
    try std.testing.expect(frame.fin);
    try std.testing.expectEqual(@as(u8, 0x1), frame.opcode);
    try std.testing.expectEqual(@as(usize, 5), frame.payload_len);
    try std.testing.expectEqualStrings("hello", bytes[frame.header_len .. frame.header_len + frame.payload_len]);
}

test "stream websocket parses masked client text frame" {
    var bytes: [64]u8 = undefined;
    const len = try buildClientFrame(&bytes, 0x1, "cancel", .{ 0x01, 0x02, 0x03, 0x04 });

    var frame = try parseClientFrame(std.testing.allocator, bytes[0..len]);
    defer frame.deinit(std.testing.allocator);

    try std.testing.expect(frame.fin);
    try std.testing.expectEqual(@as(u8, 0x1), frame.opcode);
    try std.testing.expectEqualStrings("cancel", frame.payload);
}

test "stream websocket parses masked client close frame" {
    var bytes: [32]u8 = undefined;
    const len = try buildClientFrame(&bytes, 0x8, &.{}, .{ 0xAA, 0xBB, 0xCC, 0xDD });

    var frame = try parseClientFrame(std.testing.allocator, bytes[0..len]);
    defer frame.deinit(std.testing.allocator);

    try std.testing.expect(frame.fin);
    try std.testing.expectEqual(@as(u8, 0x8), frame.opcode);
    try std.testing.expectEqual(@as(usize, 0), frame.payload.len);
}

test "stream websocket writes close frame with code and reason" {
    var sink = sink_model.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();

    try writeCloseFrameWithReason(sink.asByteSink(), 1000, "completed");

    const bytes = try sink.toOwnedSlice();
    defer std.testing.allocator.free(bytes);

    const frame = try parseServerFrame(bytes);
    try std.testing.expect(frame.fin);
    try std.testing.expectEqual(@as(u8, 0x8), frame.opcode);
    try std.testing.expectEqual(@as(usize, 11), frame.payload_len);
    const payload = bytes[frame.header_len .. frame.header_len + frame.payload_len];
    try std.testing.expectEqual(@as(u16, 1000), (@as(u16, payload[0]) << 8) | payload[1]);
    try std.testing.expectEqualStrings("completed", payload[2..]);
}

test "stream websocket parses close payload with code and reason" {
    const parsed = try parseClosePayload(&[_]u8{ 0x03, 0xE9, 'b', 'y', 'e' });
    try std.testing.expectEqual(@as(?u16, 1001), parsed.close_code);
    try std.testing.expect(parsed.close_reason != null);
    try std.testing.expectEqualStrings("bye", parsed.close_reason.?);
}
