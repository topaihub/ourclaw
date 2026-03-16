const std = @import("std");
const providers = @import("../providers/root.zig");
const security = @import("../security/policy.zig");

pub const MemoryEntry = struct {
    session_id: []u8,
    kind: []u8,
    content_json: []u8,
    ts_unix_ms: i64,
    embedding: EmbeddingVector,
    embedding_strategy: EmbeddingStrategy,
    embedding_provider: ?[]u8,
    embedding_model: ?[]u8,

    pub fn deinit(self: *MemoryEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.session_id);
        allocator.free(self.kind);
        allocator.free(self.content_json);
        if (self.embedding_provider) |value| allocator.free(value);
        if (self.embedding_model) |value| allocator.free(value);
    }
};

pub const EMBEDDING_DIMENSIONS: usize = providers.EmbeddingDimensions;

pub const EmbeddingStrategy = enum {
    local_bow_v1,
    provider_proxy_v1,
};

pub const RankingReason = enum {
    hybrid_match,
    keyword_overlap,
    embedding_similarity,
};

pub const EmbeddingDescriptor = struct {
    strategy: EmbeddingStrategy = .local_bow_v1,
    dimensions: usize = EMBEDDING_DIMENSIONS,
    provider_id: ?[]const u8 = null,
    model: ?[]const u8 = null,
};

pub const EmbeddingVector = providers.EmbeddingVector;

pub const MigrationPreview = struct {
    from_version: u32,
    to_version: u32,
    changed: bool,
};

pub const SnapshotImportResult = struct {
    imported_count: usize,
    rejected_count: usize,
    source_version: u32,
    resulting_count: usize,
};

pub const CompactionResult = struct {
    summary: SessionSummary,
    removed_count: usize,
    kept_count: usize,
    result_entry_count: usize,

    pub fn deinit(self: *CompactionResult, allocator: std.mem.Allocator) void {
        self.summary.deinit(allocator);
    }
};

pub const MemoryRecall = struct {
    session_id: []u8,
    compacted_summary_text: ?[]u8 = null,
    summary_text: []u8,
    entry_count: usize,

    pub fn deinit(self: *MemoryRecall, allocator: std.mem.Allocator) void {
        allocator.free(self.session_id);
        if (self.compacted_summary_text) |value| allocator.free(value);
        allocator.free(self.summary_text);
    }
};

pub const MemoryHit = struct {
    kind: []u8,
    content_json: []u8,
    score: usize,
    rank: usize,
    ts_unix_ms: i64,
    embedding_strategy: EmbeddingStrategy,
    embedding_provider: ?[]u8,
    embedding_model: ?[]u8,
    ranking_reason: RankingReason,
    embedding_score: usize,
    keyword_overlap: usize,
    kind_weight: usize,

    pub fn deinit(self: *MemoryHit, allocator: std.mem.Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.content_json);
        if (self.embedding_provider) |value| allocator.free(value);
        if (self.embedding_model) |value| allocator.free(value);
    }
};

pub const EmbeddingRuntimeConfig = struct {
    strategy: EmbeddingStrategy = .local_bow_v1,
    provider_id: ?[]u8 = null,
    model: ?[]u8 = null,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        if (self.provider_id) |value| allocator.free(value);
        if (self.model) |value| allocator.free(value);
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

const ImportedStringField = union(enum) {
    absent,
    clear,
    set: []const u8,
};

pub const MemoryRuntime = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(MemoryEntry) = .empty,
    embedding_config: EmbeddingRuntimeConfig = .{},
    embedding_provider: ?providers.EmbeddingProvider = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.entries.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.entries.deinit(self.allocator);
        self.embedding_config.deinit(self.allocator);
    }

    pub fn appendUserPrompt(self: *Self, session_id: []const u8, prompt: []const u8) anyerror!void {
        const payload = try buildTextPayload(self.allocator, prompt);
        defer self.allocator.free(payload);
        try self.appendEntry(session_id, "user_prompt", payload);
    }

    pub fn appendToolResult(self: *Self, session_id: []const u8, tool_id: []const u8, result_json: []const u8) anyerror!void {
        const tool_id_json = try jsonString(self.allocator, tool_id);
        defer self.allocator.free(tool_id_json);
        const payload = try std.fmt.allocPrint(self.allocator, "{{\"toolId\":{s},\"result\":{s}}}", .{ tool_id_json, result_json });
        defer self.allocator.free(payload);
        try self.appendEntry(session_id, "tool_result", payload);
    }

    pub fn appendAssistantResponse(self: *Self, session_id: []const u8, response_text: []const u8) anyerror!void {
        const payload = try buildTextPayload(self.allocator, response_text);
        defer self.allocator.free(payload);
        try self.appendEntry(session_id, "assistant_response", payload);
    }

    pub fn recallForTurn(self: *Self, allocator: std.mem.Allocator, session_id: []const u8, max_items: usize) anyerror!MemoryRecall {
        var selected: std.ArrayListUnmanaged(*const MemoryEntry) = .empty;
        defer selected.deinit(allocator);

        var compacted_summary_text: ?[]u8 = null;
        errdefer if (compacted_summary_text) |value| allocator.free(value);

        var index = self.entries.items.len;
        while (index > 0) {
            index -= 1;
            const entry = &self.entries.items[index];
            if (!std.mem.eql(u8, entry.session_id, session_id)) continue;

            if (std.mem.eql(u8, entry.kind, "session_summary")) {
                if (compacted_summary_text == null) {
                    compacted_summary_text = try extractSummaryText(allocator, entry.content_json);
                }
                continue;
            }

            if (selected.items.len < max_items) {
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
            .compacted_summary_text = compacted_summary_text,
            .summary_text = try allocator.dupe(u8, buf.items),
            .entry_count = selected.items.len + if (compacted_summary_text != null) @as(usize, 1) else 0,
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

    pub fn embeddingDescriptor(self: *const Self) EmbeddingDescriptor {
        return .{
            .strategy = self.embedding_config.strategy,
            .dimensions = EMBEDDING_DIMENSIONS,
            .provider_id = self.embedding_config.provider_id,
            .model = self.embedding_config.model,
        };
    }

    pub fn setEmbeddingProvider(self: *Self, provider_id: ?[]const u8) anyerror!void {
        try replaceOptionalOwnedString(self.allocator, &self.embedding_config.provider_id, provider_id);
    }

    pub fn setEmbeddingModel(self: *Self, model: ?[]const u8) anyerror!void {
        try replaceOptionalOwnedString(self.allocator, &self.embedding_config.model, model);
    }

    pub fn bindProviderRegistry(self: *Self, provider_registry: *providers.ProviderRegistry) void {
        self.bindEmbeddingProvider(provider_registry.asEmbeddingProvider());
    }

    pub fn bindEmbeddingProvider(self: *Self, embedding_provider: providers.EmbeddingProvider) void {
        self.embedding_provider = embedding_provider;
    }

    pub fn summarizeSession(self: *Self, allocator: std.mem.Allocator, session_id: []const u8, max_items: usize) anyerror!SessionSummary {
        var recall = try self.recallForTurn(allocator, session_id, max_items);
        defer recall.deinit(allocator);

        const summary_text = if (recall.compacted_summary_text) |compacted_summary|
            if (std.mem.trim(u8, recall.summary_text, " \r\n\t").len > 0)
                try std.fmt.allocPrint(allocator, "session {s}: {s}\nrecent recall: {s}", .{ session_id, compacted_summary, recall.summary_text })
            else
                try std.fmt.allocPrint(allocator, "session {s}: {s}", .{ session_id, compacted_summary })
        else
            try std.fmt.allocPrint(allocator, "session {s}: {s}", .{ session_id, recall.summary_text });
        errdefer allocator.free(summary_text);

        return .{
            .session_id = try allocator.dupe(u8, session_id),
            .summary_text = summary_text,
            .source_count = recall.entry_count,
        };
    }

    pub fn retrieve(self: *Self, allocator: std.mem.Allocator, session_id: []const u8, query: []const u8, max_items: usize) anyerror![]MemoryHit {
        var hits: std.ArrayListUnmanaged(MemoryHit) = .empty;
        defer hits.deinit(allocator);

        const query_embedding = try embedQuery(self, query);

        for (self.entries.items) |entry| {
            if (!std.mem.eql(u8, entry.session_id, session_id)) continue;
            const breakdown = scoreEntry(entry, query, query_embedding);
            if (!breakdown.has_match) continue;

            try hits.append(allocator, .{
                .kind = try allocator.dupe(u8, entry.kind),
                .content_json = try allocator.dupe(u8, entry.content_json),
                .score = breakdown.final_score,
                .rank = 0,
                .ts_unix_ms = entry.ts_unix_ms,
                .embedding_strategy = entry.embedding_strategy,
                .embedding_provider = if (entry.embedding_provider) |value| try allocator.dupe(u8, value) else null,
                .embedding_model = if (entry.embedding_model) |value| try allocator.dupe(u8, value) else null,
                .ranking_reason = breakdown.reason,
                .embedding_score = breakdown.embedding_score,
                .keyword_overlap = breakdown.keyword_overlap,
                .kind_weight = breakdown.kind_weight,
            });
        }

        std.mem.sort(MemoryHit, hits.items, {}, lessThanHit);
        for (hits.items, 0..) |*hit, index| {
            hit.rank = index + 1;
        }

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

    pub fn compactSession(self: *Self, allocator: std.mem.Allocator, session_id: []const u8, keep_last: usize) anyerror!CompactionResult {
        var summary = try self.summarizeSession(allocator, session_id, 8);
        errdefer summary.deinit(allocator);

        var kept: usize = 0;
        var removed_count: usize = 0;
        var index = self.entries.items.len;
        while (index > 0) {
            index -= 1;
            const entry = &self.entries.items[index];
            if (!std.mem.eql(u8, entry.session_id, session_id)) continue;

            kept += 1;
            if (kept > keep_last) {
                var removed = self.entries.orderedRemove(index);
                removed.deinit(self.allocator);
                removed_count += 1;
            }
        }

        const payload = try buildSummaryPayload(self.allocator, summary.summary_text, summary.source_count);
        defer self.allocator.free(payload);
        try self.appendEntry(session_id, "session_summary", payload);
        return .{
            .summary = summary,
            .removed_count = removed_count,
            .kept_count = @min(keep_last, kept),
            .result_entry_count = self.countBySession(session_id),
        };
    }

    fn appendEntry(self: *Self, session_id: []const u8, kind: []const u8, content_json: []const u8) anyerror!void {
        const content_copy = try self.allocator.dupe(u8, content_json);
        errdefer self.allocator.free(content_copy);
        var embedding = try buildEmbedding(self, content_json);
        errdefer embedding.deinit(self.allocator);
        try self.entries.append(self.allocator, .{
            .session_id = try self.allocator.dupe(u8, session_id),
            .kind = try self.allocator.dupe(u8, kind),
            .content_json = content_copy,
            .ts_unix_ms = std.time.milliTimestamp(),
            .embedding = embedding.vector,
            .embedding_strategy = embedding.strategy,
            .embedding_provider = embedding.provider_id,
            .embedding_model = embedding.model,
        });
    }

    pub fn exportSnapshotJson(self: *Self, allocator: std.mem.Allocator) anyerror![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        defer buf.deinit(allocator);
        const writer = buf.writer(allocator);
        try writer.writeAll("{\"version\":2,\"entries\":[");
        for (self.entries.items, 0..) |entry, index| {
            if (index > 0) try writer.writeByte(',');
            try writer.writeByte('{');
            try writeJsonStringTo(writer, "sessionId");
            try writer.writeByte(':');
            try writeJsonStringTo(writer, entry.session_id);
            try writer.writeByte(',');
            try writeJsonStringTo(writer, "kind");
            try writer.writeByte(':');
            try writeJsonStringTo(writer, entry.kind);
            try writer.writeByte(',');
            try writeJsonStringTo(writer, "content");
            try writer.writeByte(':');
            try writer.writeAll(entry.content_json);
            try writer.writeByte(',');
            try writeJsonStringTo(writer, "tsUnixMs");
            try writer.writeByte(':');
            try writer.print("{d}", .{entry.ts_unix_ms});
            try writer.writeByte(',');
            try writeJsonStringTo(writer, "embeddingProvider");
            try writer.writeByte(':');
            if (entry.embedding_provider) |value| {
                try writeJsonStringTo(writer, value);
            } else {
                try writer.writeAll("null");
            }
            try writer.writeByte(',');
            try writeJsonStringTo(writer, "embeddingModel");
            try writer.writeByte(':');
            if (entry.embedding_model) |value| {
                try writeJsonStringTo(writer, value);
            } else {
                try writer.writeAll("null");
            }
            try writer.writeByte('}');
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

    pub fn importSnapshotJson(self: *Self, allocator: std.mem.Allocator, snapshot_json: []const u8) anyerror!SnapshotImportResult {
        const migrated = try self.migrateSnapshotJson(allocator, snapshot_json);
        defer allocator.free(migrated);

        const source_version: u32 = if (std.mem.indexOf(u8, snapshot_json, "\"version\":2") != null) 2 else 1;
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, migrated, .{});
        defer parsed.deinit();
        var imported_count: usize = 0;
        var rejected_count: usize = 0;

        if (parsed.value != .object) {
            return .{
                .imported_count = 0,
                .rejected_count = 1,
                .source_version = source_version,
                .resulting_count = self.count(),
            };
        }

        const entries_value = parsed.value.object.get("entries") orelse {
            return .{
                .imported_count = 0,
                .rejected_count = 1,
                .source_version = source_version,
                .resulting_count = self.count(),
            };
        };
        if (entries_value != .array) {
            return .{
                .imported_count = 0,
                .rejected_count = 1,
                .source_version = source_version,
                .resulting_count = self.count(),
            };
        }

        for (entries_value.array.items) |entry_value| {
            if (entry_value != .object) {
                rejected_count += 1;
                continue;
            }

            const session_id_value = entry_value.object.get("sessionId") orelse {
                rejected_count += 1;
                continue;
            };
            const kind_value = entry_value.object.get("kind") orelse {
                rejected_count += 1;
                continue;
            };
            const content_value = entry_value.object.get("content") orelse {
                rejected_count += 1;
                continue;
            };

            if (session_id_value != .string or kind_value != .string) {
                rejected_count += 1;
                continue;
            }

            const content = try stringifyJsonValue(allocator, content_value);
            defer allocator.free(content);

            const ts_unix_ms = if (entry_value.object.get("tsUnixMs")) |value| blk: {
                switch (value) {
                    .integer => break :blk @as(i64, @intCast(value.integer)),
                    else => {
                        rejected_count += 1;
                        continue;
                    },
                }
            } else null;

            const embedding_provider = parseImportedStringField(entry_value.object.get("embeddingProvider")) catch {
                rejected_count += 1;
                continue;
            };
            const embedding_model = parseImportedStringField(entry_value.object.get("embeddingModel")) catch {
                rejected_count += 1;
                continue;
            };

            try self.appendEntry(session_id_value.string, kind_value.string, content);
            if (self.entries.items.len > 0) {
                const imported_entry = &self.entries.items[self.entries.items.len - 1];
                if (ts_unix_ms) |value| imported_entry.ts_unix_ms = value;
                try applyImportedStringField(self.allocator, &imported_entry.embedding_provider, embedding_provider);
                try applyImportedStringField(self.allocator, &imported_entry.embedding_model, embedding_model);
            }
            imported_count += 1;
        }

        return .{
            .imported_count = imported_count,
            .rejected_count = rejected_count,
            .source_version = source_version,
            .resulting_count = self.count(),
        };
    }
};

fn parseImportedStringField(value: ?std.json.Value) anyerror!ImportedStringField {
    if (value == null) return .absent;
    return switch (value.?) {
        .null => .clear,
        .string => |text| ImportedStringField{ .set = text },
        else => error.InvalidSnapshotField,
    };
}

fn applyImportedStringField(allocator: std.mem.Allocator, target: *?[]u8, field: ImportedStringField) anyerror!void {
    switch (field) {
        .absent => {},
        .clear => {
            if (target.*) |owned| allocator.free(owned);
            target.* = null;
        },
        .set => |value| {
            if (target.*) |owned| allocator.free(owned);
            target.* = try allocator.dupe(u8, value);
        },
    }
}

const EmbeddingBuildResult = struct {
    vector: EmbeddingVector,
    strategy: EmbeddingStrategy,
    provider_id: ?[]u8,
    model: ?[]u8,

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        if (self.provider_id) |value| allocator.free(value);
        if (self.model) |value| allocator.free(value);
    }
};

const RankingBreakdown = struct {
    has_match: bool,
    final_score: usize,
    embedding_score: usize,
    keyword_overlap: usize,
    kind_weight: usize,
    reason: RankingReason,
};

fn scoreEntry(entry: MemoryEntry, query: []const u8, query_embedding: EmbeddingVector) RankingBreakdown {
    const dot = dotProduct(entry.embedding, query_embedding);
    const embedding_score: usize = @intFromFloat(if (dot <= 0) 0 else dot * 100.0);
    const keyword_overlap = countKeywordOverlap(entry.content_json, query);
    const weight = kindWeight(entry.kind);
    const has_match = keyword_overlap > 0 or embedding_score >= 8;
    if (!has_match) {
        return .{
            .has_match = false,
            .final_score = 0,
            .embedding_score = embedding_score,
            .keyword_overlap = keyword_overlap,
            .kind_weight = weight,
            .reason = .embedding_similarity,
        };
    }

    return .{
        .has_match = true,
        .final_score = embedding_score + (keyword_overlap * 100) + weight,
        .embedding_score = embedding_score,
        .keyword_overlap = keyword_overlap,
        .kind_weight = weight,
        .reason = rankingReason(keyword_overlap, embedding_score),
    };
}

fn embedText(text: []const u8) EmbeddingVector {
    var vector: EmbeddingVector = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
    for (text) |ch| {
        const bucket = ch % vector.len;
        vector[bucket] += 1;
    }
    return normalize(vector);
}

fn providerStrategyToMemory(strategy: providers.EmbeddingStrategy) EmbeddingStrategy {
    return switch (strategy) {
        .provider_proxy_v1 => .provider_proxy_v1,
    };
}

fn duplicateOptional(allocator: std.mem.Allocator, value: ?[]const u8) anyerror!?[]u8 {
    return if (value) |actual| try allocator.dupe(u8, actual) else null;
}

fn configuredModelOrDefault(self: *const MemoryRuntime) ?[]const u8 {
    return if (self.embedding_config.model) |value| value else null;
}

fn buildEmbedding(self: *MemoryRuntime, text: []const u8) anyerror!EmbeddingBuildResult {
    if (self.embedding_config.provider_id) |provider_id| {
        if (!std.mem.eql(u8, provider_id, "local")) {
            if (self.embedding_provider) |embedding_provider| {
                if ((embedding_provider.supportsEmbeddings(provider_id) catch false)) {
                    const response = embedding_provider.embedText(self.allocator, .{
                        .provider_id = provider_id,
                        .model = configuredModelOrDefault(self),
                        .input = text,
                    }) catch {
                        return .{
                            .vector = embedText(text),
                            .strategy = .local_bow_v1,
                            .provider_id = try duplicateOptional(self.allocator, self.embedding_config.provider_id),
                            .model = try duplicateOptional(self.allocator, self.embedding_config.model),
                        };
                    };
                    return .{
                        .vector = response.vector,
                        .strategy = providerStrategyToMemory(response.strategy),
                        .provider_id = response.provider_id,
                        .model = response.model,
                    };
                }
            }
        }
    }

    return .{
        .vector = embedText(text),
        .strategy = .local_bow_v1,
        .provider_id = try duplicateOptional(self.allocator, self.embedding_config.provider_id),
        .model = try duplicateOptional(self.allocator, self.embedding_config.model),
    };
}

fn embedQuery(self: *MemoryRuntime, query: []const u8) anyerror!EmbeddingVector {
    var embedding = try buildEmbedding(self, query);
    defer embedding.deinit(self.allocator);
    return embedding.vector;
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

fn rankingReason(keyword_overlap: usize, embedding_score: usize) RankingReason {
    if (keyword_overlap > 0 and embedding_score > 0) return .hybrid_match;
    if (keyword_overlap > 0) return .keyword_overlap;
    return .embedding_similarity;
}

fn kindWeight(kind: []const u8) usize {
    if (std.mem.eql(u8, kind, "assistant_response")) return 24;
    if (std.mem.eql(u8, kind, "tool_result")) return 18;
    if (std.mem.eql(u8, kind, "session_summary")) return 14;
    if (std.mem.eql(u8, kind, "user_prompt")) return 10;
    return 6;
}

fn countKeywordOverlap(haystack: []const u8, query: []const u8) usize {
    var total: usize = 0;
    var iter = std.mem.tokenizeAny(u8, query, " \t\r\n,.:;!?()[]{}\"'");
    while (iter.next()) |token| {
        if (token.len == 0) continue;
        if (containsAsciiIgnoreCase(haystack, token)) total += 1;
    }
    return total;
}

fn buildTextPayload(allocator: std.mem.Allocator, text: []const u8) anyerror![]u8 {
    const text_json = try jsonString(allocator, text);
    defer allocator.free(text_json);
    return std.fmt.allocPrint(allocator, "{{\"text\":{s}}}", .{text_json});
}

fn buildSummaryPayload(allocator: std.mem.Allocator, text: []const u8, source_count: usize) anyerror![]u8 {
    const text_json = try jsonString(allocator, text);
    defer allocator.free(text_json);
    return std.fmt.allocPrint(allocator, "{{\"text\":{s},\"sourceCount\":{d}}}", .{ text_json, source_count });
}

fn extractSummaryText(allocator: std.mem.Allocator, payload_json: []const u8) anyerror![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload_json, .{});
    defer parsed.deinit();

    if (parsed.value == .object) {
        if (parsed.value.object.get("text")) |value| {
            if (value == .string) return allocator.dupe(u8, value.string);
        }
    }

    return allocator.dupe(u8, payload_json);
}

fn jsonString(allocator: std.mem.Allocator, value: []const u8) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);
    try writer.writeByte('"');
    for (value) |ch| {
        switch (ch) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (ch < 32) {
                    try writer.print("\\u00{x:0>2}", .{ch});
                } else {
                    try writer.writeByte(ch);
                }
            },
        }
    }
    try writer.writeByte('"');
    return allocator.dupe(u8, buf.items);
}

fn stringifyJsonValue(allocator: std.mem.Allocator, value: std.json.Value) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    try writeJsonValue(buf.writer(allocator), value);
    return allocator.dupe(u8, buf.items);
}

fn writeJsonValue(writer: anytype, value: std.json.Value) anyerror!void {
    switch (value) {
        .null => try writer.writeAll("null"),
        .bool => |inner| try writer.writeAll(if (inner) "true" else "false"),
        .integer => |inner| try writer.print("{d}", .{inner}),
        .float => |inner| try writer.print("{d}", .{inner}),
        .number_string => |inner| try writer.writeAll(inner),
        .string => |inner| try writeJsonStringTo(writer, inner),
        .array => |inner| {
            try writer.writeByte('[');
            for (inner.items, 0..) |item, index| {
                if (index > 0) try writer.writeByte(',');
                try writeJsonValue(writer, item);
            }
            try writer.writeByte(']');
        },
        .object => |inner| {
            try writer.writeByte('{');
            var it = inner.iterator();
            var index: usize = 0;
            while (it.next()) |entry| {
                if (index > 0) try writer.writeByte(',');
                try writeJsonStringTo(writer, entry.key_ptr.*);
                try writer.writeByte(':');
                try writeJsonValue(writer, entry.value_ptr.*);
                index += 1;
            }
            try writer.writeByte('}');
        },
    }
}

fn writeJsonStringTo(writer: anytype, value: []const u8) anyerror!void {
    try writer.writeByte('"');
    for (value) |ch| {
        switch (ch) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (ch < 32) {
                    try writer.print("\\u00{x:0>2}", .{ch});
                } else {
                    try writer.writeByte(ch);
                }
            },
        }
    }
    try writer.writeByte('"');
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

fn replaceOptionalOwnedString(allocator: std.mem.Allocator, target: *?[]u8, next: ?[]const u8) anyerror!void {
    if (target.*) |previous| allocator.free(previous);
    target.* = if (next) |value| try allocator.dupe(u8, value) else null;
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
    if (a.score != b.score) return a.score > b.score;
    if (a.keyword_overlap != b.keyword_overlap) return a.keyword_overlap > b.keyword_overlap;
    return a.ts_unix_ms > b.ts_unix_ms;
}

test "memory runtime appends and recalls entries" {
    var runtime = MemoryRuntime.init(std.testing.allocator);
    defer runtime.deinit();

    try runtime.appendUserPrompt("sess_01", "hello");
    try runtime.appendAssistantResponse("sess_01", "hi");

    var recall = try runtime.recallForTurn(std.testing.allocator, "sess_01", 10);
    defer recall.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), recall.entry_count);
    try std.testing.expect(recall.compacted_summary_text == null);
    try std.testing.expect(std.mem.indexOf(u8, recall.summary_text, "assistant_response") != null);
}

test "memory runtime retrieves and compacts session entries" {
    var runtime = MemoryRuntime.init(std.testing.allocator);
    defer runtime.deinit();

    try runtime.setEmbeddingProvider("local");
    try runtime.setEmbeddingModel("local-bow-v1");

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
    try std.testing.expectEqual(@as(usize, 1), hits[0].rank);
    try std.testing.expect(hits[0].keyword_overlap >= 1);
    try std.testing.expectEqual(EmbeddingStrategy.local_bow_v1, hits[0].embedding_strategy);
    try std.testing.expectEqualStrings("local", hits[0].embedding_provider.?);
    try std.testing.expectEqualStrings("local-bow-v1", hits[0].embedding_model.?);

    var result = try runtime.compactSession(std.testing.allocator, "sess_02", 1);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(runtime.countBySession("sess_02") >= 2);
    try std.testing.expect(std.mem.indexOf(u8, result.summary.summary_text, "session sess_02") != null);
    try std.testing.expectEqual(@as(usize, 2), result.removed_count);
    try std.testing.expectEqual(@as(usize, 1), result.kept_count);
}

test "memory runtime exports and migrates snapshot" {
    var runtime = MemoryRuntime.init(std.testing.allocator);
    defer runtime.deinit();
    try runtime.setEmbeddingProvider("local");
    try runtime.setEmbeddingModel("local-bow-v1");
    try runtime.appendUserPrompt("sess_03", "hello migration");
    runtime.entries.items[0].ts_unix_ms = 123456789;

    const snapshot = try runtime.exportSnapshotJson(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "\"version\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "\"tsUnixMs\":123456789") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "\"embeddingProvider\":\"local\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "\"embeddingModel\":\"local-bow-v1\"") != null);

    const preview = runtime.previewMigration("{\"version\":1,\"entries\":[]}");
    try std.testing.expect(preview.changed);

    const migrated = try runtime.migrateSnapshotJson(std.testing.allocator, "{\"version\":1,\"entries\":[]}");
    defer std.testing.allocator.free(migrated);
    try std.testing.expect(std.mem.indexOf(u8, migrated, "\"version\":2") != null);
}

test "memory runtime imports migrated snapshot" {
    var runtime = MemoryRuntime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try runtime.importSnapshotJson(std.testing.allocator, "{\"version\":2,\"entries\":[{\"sessionId\":\"sess_import\",\"kind\":\"user_prompt\",\"content\":{\"text\":\"hello\"}}]}");
    try std.testing.expectEqual(@as(usize, 1), result.imported_count);
    try std.testing.expectEqual(@as(usize, 0), result.rejected_count);
    try std.testing.expectEqual(@as(usize, 1), runtime.countBySession("sess_import"));

    var summary = try runtime.summarizeSession(std.testing.allocator, "sess_import", 8);
    defer summary.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, summary.summary_text, "sess_import") != null);

    const hits = try runtime.retrieve(std.testing.allocator, "sess_import", "hello", 4);
    defer {
        for (hits) |*hit| hit.deinit(std.testing.allocator);
        std.testing.allocator.free(hits);
    }
    try std.testing.expect(hits.len >= 1);
}

test "memory runtime import preserves explicit null richer metadata" {
    var runtime = MemoryRuntime.init(std.testing.allocator);
    defer runtime.deinit();
    try runtime.setEmbeddingProvider("local");
    try runtime.setEmbeddingModel("local-bow-v1");

    const result = try runtime.importSnapshotJson(std.testing.allocator, "{\"version\":2,\"entries\":[{\"sessionId\":\"sess_null_meta\",\"kind\":\"user_prompt\",\"content\":{\"text\":\"hello\"},\"tsUnixMs\":999001,\"embeddingProvider\":null,\"embeddingModel\":null}]}");
    try std.testing.expectEqual(@as(usize, 1), result.imported_count);
    try std.testing.expectEqual(@as(usize, 0), result.rejected_count);

    const snapshot = try runtime.exportSnapshotJson(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "\"tsUnixMs\":999001") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "\"embeddingProvider\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "\"embeddingModel\":null") != null);
}

test "memory runtime snapshot roundtrip preserves summary and retrieval" {
    var source = MemoryRuntime.init(std.testing.allocator);
    defer source.deinit();
    try source.setEmbeddingProvider("local");
    try source.setEmbeddingModel("local-bow-v1");
    try source.appendUserPrompt("sess_roundtrip", "hello \"roundtrip\" memory");
    try source.appendToolResult("sess_roundtrip", "http_request", "{\"status\":200,\"body\":{\"nested\":true}}");
    try source.appendAssistantResponse("sess_roundtrip", "roundtrip memory is ready");
    var compaction = try source.compactSession(std.testing.allocator, "sess_roundtrip", 3);
    defer compaction.deinit(std.testing.allocator);

    const snapshot = try source.exportSnapshotJson(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);

    var imported = MemoryRuntime.init(std.testing.allocator);
    defer imported.deinit();
    try imported.setEmbeddingProvider("local");
    try imported.setEmbeddingModel("local-bow-v1");

    const result = try imported.importSnapshotJson(std.testing.allocator, snapshot);
    try std.testing.expectEqual(@as(usize, 4), result.imported_count);
    try std.testing.expectEqual(@as(u32, 2), result.source_version);

    var summary = try imported.summarizeSession(std.testing.allocator, "sess_roundtrip", 8);
    defer summary.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, summary.summary_text, "sess_roundtrip") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary.summary_text, "roundtrip memory") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary.summary_text, "recent recall:") != null);

    const hits = try imported.retrieve(std.testing.allocator, "sess_roundtrip", "roundtrip", 4);
    defer {
        for (hits) |*hit| hit.deinit(std.testing.allocator);
        std.testing.allocator.free(hits);
    }
    try std.testing.expect(hits.len >= 1);
    try std.testing.expect(hits[0].keyword_overlap >= 1);

    const nested_hits = try imported.retrieve(std.testing.allocator, "sess_roundtrip", "nested", 4);
    defer {
        for (nested_hits) |*hit| hit.deinit(std.testing.allocator);
        std.testing.allocator.free(nested_hits);
    }
    try std.testing.expect(nested_hits.len >= 1);
    try std.testing.expect(std.mem.indexOf(u8, nested_hits[0].content_json, "nested") != null);
}

test "memory runtime snapshot roundtrip preserves richer metadata" {
    var source = MemoryRuntime.init(std.testing.allocator);
    defer source.deinit();
    try source.setEmbeddingProvider("local");
    try source.setEmbeddingModel("local-bow-v1");
    try source.appendUserPrompt("sess_meta_roundtrip", "hello metadata");
    source.entries.items[0].ts_unix_ms = 444444;

    const snapshot = try source.exportSnapshotJson(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "\"tsUnixMs\":444444") != null);

    var imported = MemoryRuntime.init(std.testing.allocator);
    defer imported.deinit();
    const result = try imported.importSnapshotJson(std.testing.allocator, snapshot);
    try std.testing.expectEqual(@as(usize, 1), result.imported_count);

    const imported_snapshot = try imported.exportSnapshotJson(std.testing.allocator);
    defer std.testing.allocator.free(imported_snapshot);
    try std.testing.expect(std.mem.indexOf(u8, imported_snapshot, "\"tsUnixMs\":444444") != null);
    try std.testing.expect(std.mem.indexOf(u8, imported_snapshot, "\"embeddingProvider\":\"local\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, imported_snapshot, "\"embeddingModel\":\"local-bow-v1\"") != null);

    const hits = try imported.retrieve(std.testing.allocator, "sess_meta_roundtrip", "metadata", 2);
    defer {
        for (hits) |*hit| hit.deinit(std.testing.allocator);
        std.testing.allocator.free(hits);
    }
    try std.testing.expect(hits.len >= 1);
    try std.testing.expectEqual(@as(i64, 444444), hits[0].ts_unix_ms);
    try std.testing.expectEqualStrings("local", hits[0].embedding_provider.?);
    try std.testing.expectEqualStrings("local-bow-v1", hits[0].embedding_model.?);
}

test "memory runtime retrieval ranking exposes rich metadata" {
    var runtime = MemoryRuntime.init(std.testing.allocator);
    defer runtime.deinit();

    var registry = providers.ProviderRegistry.init(std.testing.allocator);
    defer registry.deinit();
    var secrets = security.MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    registry.setSecretStore(&secrets);
    try registry.register(.{
        .id = "openai",
        .label = "OpenAI",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .default_embedding_model = "text-embedding-3-small",
        .api_key_secret_ref = "openai:api_key",
        .supports_embeddings = true,
        .health_json = "{}",
    });
    runtime.bindProviderRegistry(&registry);

    try runtime.setEmbeddingProvider("openai");
    try runtime.setEmbeddingModel("text-embedding-3-small");

    try runtime.appendUserPrompt("sess_rank", "deploy gateway status");
    try runtime.appendAssistantResponse("sess_rank", "gateway deploy status is green");
    try runtime.appendToolResult("sess_rank", "http_request", "{\"status\":200,\"service\":\"gateway\"}");

    const hits = try runtime.retrieve(std.testing.allocator, "sess_rank", "gateway status", 3);
    defer {
        for (hits) |*hit| hit.deinit(std.testing.allocator);
        std.testing.allocator.free(hits);
    }

    try std.testing.expectEqual(@as(usize, 3), hits.len);
    try std.testing.expectEqual(@as(usize, 1), hits[0].rank);
    try std.testing.expect(hits[0].score >= hits[1].score);
    try std.testing.expect(hits[0].embedding_score > 0);
    try std.testing.expect(hits[0].keyword_overlap >= 1);
    try std.testing.expect(hits[0].kind_weight >= hits[1].kind_weight);
    try std.testing.expectEqual(EmbeddingStrategy.provider_proxy_v1, hits[0].embedding_strategy);
    try std.testing.expectEqualStrings("openai", hits[0].embedding_provider.?);
    try std.testing.expectEqualStrings("text-embedding-3-small", hits[0].embedding_model.?);
    try std.testing.expect(hits[0].ranking_reason == .hybrid_match or hits[0].ranking_reason == .keyword_overlap);
}

test "memory runtime recall separates compacted summary from recent entries" {
    var runtime = MemoryRuntime.init(std.testing.allocator);
    defer runtime.deinit();

    try runtime.appendUserPrompt("sess_summary_first", "older prompt");
    try runtime.appendAssistantResponse("sess_summary_first", "older response");
    var compaction = try runtime.compactSession(std.testing.allocator, "sess_summary_first", 1);
    defer compaction.deinit(std.testing.allocator);
    try runtime.appendAssistantResponse("sess_summary_first", "recent response");

    var recall = try runtime.recallForTurn(std.testing.allocator, "sess_summary_first", 4);
    defer recall.deinit(std.testing.allocator);

    try std.testing.expect(recall.compacted_summary_text != null);
    try std.testing.expect(std.mem.indexOf(u8, recall.compacted_summary_text.?, "session sess_summary_first") != null);
    try std.testing.expect(std.mem.indexOf(u8, recall.summary_text, "recent response") != null);
    try std.testing.expect(std.mem.indexOf(u8, recall.summary_text, "session_summary") == null);
}
