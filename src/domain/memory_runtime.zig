const std = @import("std");

pub const MemoryEntry = struct {
    session_id: []u8,
    kind: []u8,
    content_json: []u8,
    ts_unix_ms: i64,
    embedding: EmbeddingVector,

    pub fn deinit(self: *MemoryEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.session_id);
        allocator.free(self.kind);
        allocator.free(self.content_json);
    }
};

pub const EmbeddingVector = [8]f32;

pub const MigrationPreview = struct {
    from_version: u32,
    to_version: u32,
    changed: bool,
};

pub const MemoryRecall = struct {
    session_id: []u8,
    summary_text: []u8,
    entry_count: usize,

    pub fn deinit(self: *MemoryRecall, allocator: std.mem.Allocator) void {
        allocator.free(self.session_id);
        allocator.free(self.summary_text);
    }
};

pub const MemoryHit = struct {
    kind: []u8,
    content_json: []u8,
    score: usize,

    pub fn deinit(self: *MemoryHit, allocator: std.mem.Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.content_json);
    }
};

pub const SessionSummary = struct {
    session_id: []u8,
    summary_text: []u8,
    source_count: usize,

    pub fn deinit(self: *SessionSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.session_id);
        allocator.free(self.summary_text);
    }
};

pub const MemoryRuntime = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(MemoryEntry) = .empty,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.entries.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn appendUserPrompt(self: *Self, session_id: []const u8, prompt: []const u8) anyerror!void {
        const payload = try std.fmt.allocPrint(self.allocator, "{{\"text\":\"{s}\"}}", .{prompt});
        defer self.allocator.free(payload);
        try self.appendEntry(session_id, "user_prompt", payload);
    }

    pub fn appendToolResult(self: *Self, session_id: []const u8, tool_id: []const u8, result_json: []const u8) anyerror!void {
        const payload = try std.fmt.allocPrint(self.allocator, "{{\"toolId\":\"{s}\",\"result\":{s}}}", .{ tool_id, result_json });
        defer self.allocator.free(payload);
        try self.appendEntry(session_id, "tool_result", payload);
    }

    pub fn appendAssistantResponse(self: *Self, session_id: []const u8, response_text: []const u8) anyerror!void {
        const payload = try std.fmt.allocPrint(self.allocator, "{{\"text\":\"{s}\"}}", .{response_text});
        defer self.allocator.free(payload);
        try self.appendEntry(session_id, "assistant_response", payload);
    }

    pub fn recallForTurn(self: *Self, allocator: std.mem.Allocator, session_id: []const u8, max_items: usize) anyerror!MemoryRecall {
        var selected: std.ArrayListUnmanaged(*const MemoryEntry) = .empty;
        defer selected.deinit(allocator);

        var index = self.entries.items.len;
        while (index > 0 and selected.items.len < max_items) {
            index -= 1;
            const entry = &self.entries.items[index];
            if (std.mem.eql(u8, entry.session_id, session_id)) {
                try selected.append(allocator, entry);
            }
        }

        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(allocator);
        const writer = buf.writer(allocator);
        for (selected.items, 0..) |_, list_index| {
            const rev_index = selected.items.len - 1 - list_index;
            const ordered = selected.items[rev_index];
            if (list_index > 0) try writer.writeAll("\n");
            try writer.print("[{s}] {s}", .{ ordered.kind, ordered.content_json });
        }

        return .{
            .session_id = try allocator.dupe(u8, session_id),
            .summary_text = try allocator.dupe(u8, buf.items),
            .entry_count = selected.items.len,
        };
    }

    pub fn count(self: *const Self) usize {
        return self.entries.items.len;
    }

    pub fn countBySession(self: *const Self, session_id: []const u8) usize {
        var total: usize = 0;
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.session_id, session_id)) total += 1;
        }
        return total;
    }

    pub fn summarizeSession(self: *Self, allocator: std.mem.Allocator, session_id: []const u8, max_items: usize) anyerror!SessionSummary {
        var recall = try self.recallForTurn(allocator, session_id, max_items);
        defer recall.deinit(allocator);

        return .{
            .session_id = try allocator.dupe(u8, session_id),
            .summary_text = try std.fmt.allocPrint(allocator, "session {s}: {s}", .{ session_id, recall.summary_text }),
            .source_count = recall.entry_count,
        };
    }

    pub fn retrieve(self: *Self, allocator: std.mem.Allocator, session_id: []const u8, query: []const u8, max_items: usize) anyerror![]MemoryHit {
        var hits: std.ArrayListUnmanaged(MemoryHit) = .empty;
        defer hits.deinit(allocator);

        for (self.entries.items) |entry| {
            if (!std.mem.eql(u8, entry.session_id, session_id)) continue;
            const score = scoreEntry(entry, query);
            if (score == 0) continue;

            try hits.append(allocator, .{
                .kind = try allocator.dupe(u8, entry.kind),
                .content_json = try allocator.dupe(u8, entry.content_json),
                .score = score,
            });
        }

        std.mem.sort(MemoryHit, hits.items, {}, lessThanHit);

        const item_count = @min(max_items, hits.items.len);
        const result = try allocator.alloc(MemoryHit, item_count);
        errdefer allocator.free(result);

        for (hits.items[0..item_count], 0..) |hit, index| {
            result[index] = hit;
        }
        if (hits.items.len > item_count) {
            for (hits.items[item_count..]) |*hit| hit.deinit(allocator);
        }

        return result;
    }

    pub fn compactSession(self: *Self, allocator: std.mem.Allocator, session_id: []const u8, keep_last: usize) anyerror!SessionSummary {
        var summary = try self.summarizeSession(allocator, session_id, 8);
        errdefer summary.deinit(allocator);

        var kept: usize = 0;
        var index = self.entries.items.len;
        while (index > 0) {
            index -= 1;
            const entry = &self.entries.items[index];
            if (!std.mem.eql(u8, entry.session_id, session_id)) continue;

            kept += 1;
            if (kept > keep_last) {
                var removed = self.entries.orderedRemove(index);
                removed.deinit(self.allocator);
            }
        }

        try self.appendEntry(session_id, "session_summary", summary.summary_text);
        return summary;
    }

    fn appendEntry(self: *Self, session_id: []const u8, kind: []const u8, content_json: []const u8) anyerror!void {
        const content_copy = try self.allocator.dupe(u8, content_json);
        errdefer self.allocator.free(content_copy);
        try self.entries.append(self.allocator, .{
            .session_id = try self.allocator.dupe(u8, session_id),
            .kind = try self.allocator.dupe(u8, kind),
            .content_json = content_copy,
            .ts_unix_ms = std.time.milliTimestamp(),
            .embedding = embedText(content_json),
        });
    }

    pub fn exportSnapshotJson(self: *Self, allocator: std.mem.Allocator) anyerror![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(allocator);
        const writer = buf.writer(allocator);
        try writer.writeAll("{\"version\":2,\"entries\":[");
        for (self.entries.items, 0..) |entry, index| {
            if (index > 0) try writer.writeByte(',');
            try writer.print("{{\"sessionId\":\"{s}\",\"kind\":\"{s}\",\"content\":{s}}}", .{ entry.session_id, entry.kind, entry.content_json });
        }
        try writer.writeAll("]}");
        return allocator.dupe(u8, buf.items);
    }

    pub fn previewMigration(self: *Self, snapshot_json: []const u8) MigrationPreview {
        _ = self;
        if (std.mem.indexOf(u8, snapshot_json, "\"version\":2") != null) {
            return .{ .from_version = 2, .to_version = 2, .changed = false };
        }
        return .{ .from_version = 1, .to_version = 2, .changed = true };
    }

    pub fn migrateSnapshotJson(self: *Self, allocator: std.mem.Allocator, snapshot_json: []const u8) anyerror![]u8 {
        _ = self;
        if (std.mem.indexOf(u8, snapshot_json, "\"version\":2") != null) {
            return allocator.dupe(u8, snapshot_json);
        }
        if (std.mem.indexOf(u8, snapshot_json, "\"version\":1") != null) {
            return replaceVersionOne(allocator, snapshot_json);
        }
        return std.fmt.allocPrint(allocator, "{{\"version\":2,\"legacy\":{s}}}", .{snapshot_json});
    }
};

fn scoreEntry(entry: MemoryEntry, query: []const u8) usize {
    const query_embedding = embedText(query);
    const dot = dotProduct(entry.embedding, query_embedding);
    return @intFromFloat(if (dot <= 0) 0 else dot * 100.0);
}

fn embedText(text: []const u8) EmbeddingVector {
    var vector: EmbeddingVector = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
    for (text) |ch| {
        const bucket = ch % vector.len;
        vector[bucket] += 1;
    }
    return normalize(vector);
}

fn normalize(vector: EmbeddingVector) EmbeddingVector {
    var sum: f32 = 0;
    for (vector) |value| sum += value * value;
    if (sum == 0) return vector;
    const norm = std.math.sqrt(sum);
    var result = vector;
    for (&result) |*value| value.* /= norm;
    return result;
}

fn dotProduct(a: EmbeddingVector, b: EmbeddingVector) f32 {
    var sum: f32 = 0;
    for (a, b) |left, right| sum += left * right;
    return sum;
}

fn replaceVersionOne(allocator: std.mem.Allocator, snapshot_json: []const u8) anyerror![]u8 {
    const needle = "\"version\":1";
    const replacement = "\"version\":2";
    const index = std.mem.indexOf(u8, snapshot_json, needle) orelse return allocator.dupe(u8, snapshot_json);

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, snapshot_json[0..index]);
    try buf.appendSlice(allocator, replacement);
    try buf.appendSlice(allocator, snapshot_json[index + needle.len ..]);
    return allocator.dupe(u8, buf.items);
}

fn containsAsciiIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or haystack.len < needle.len) return false;
    var start: usize = 0;
    while (start + needle.len <= haystack.len) : (start += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[start .. start + needle.len], needle)) return true;
    }
    return false;
}

fn lessThanHit(_: void, a: MemoryHit, b: MemoryHit) bool {
    return a.score > b.score;
}

test "memory runtime appends and recalls entries" {
    var runtime = MemoryRuntime.init(std.testing.allocator);
    defer runtime.deinit();

    try runtime.appendUserPrompt("sess_01", "hello");
    try runtime.appendAssistantResponse("sess_01", "hi");

    var recall = try runtime.recallForTurn(std.testing.allocator, "sess_01", 10);
    defer recall.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), recall.entry_count);
    try std.testing.expect(std.mem.indexOf(u8, recall.summary_text, "assistant_response") != null);
}

test "memory runtime retrieves and compacts session entries" {
    var runtime = MemoryRuntime.init(std.testing.allocator);
    defer runtime.deinit();

    try runtime.appendUserPrompt("sess_02", "provider health check");
    try runtime.appendToolResult("sess_02", "http_request", "{\"status\":200}");
    try runtime.appendAssistantResponse("sess_02", "provider health is green");

    const hits = try runtime.retrieve(std.testing.allocator, "sess_02", "provider health", 2);
    defer {
        for (hits) |*hit| hit.deinit(std.testing.allocator);
        std.testing.allocator.free(hits);
    }

    try std.testing.expect(hits.len >= 1);
    try std.testing.expect(hits[0].score >= 1);

    var summary = try runtime.compactSession(std.testing.allocator, "sess_02", 1);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expect(runtime.countBySession("sess_02") >= 2);
    try std.testing.expect(std.mem.indexOf(u8, summary.summary_text, "session sess_02") != null);
}

test "memory runtime exports and migrates snapshot" {
    var runtime = MemoryRuntime.init(std.testing.allocator);
    defer runtime.deinit();
    try runtime.appendUserPrompt("sess_03", "hello migration");

    const snapshot = try runtime.exportSnapshotJson(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "\"version\":2") != null);

    const preview = runtime.previewMigration("{\"version\":1,\"entries\":[]}");
    try std.testing.expect(preview.changed);

    const migrated = try runtime.migrateSnapshotJson(std.testing.allocator, "{\"version\":1,\"entries\":[]}");
    defer std.testing.allocator.free(migrated);
    try std.testing.expect(std.mem.indexOf(u8, migrated, "\"version\":2") != null);
}
