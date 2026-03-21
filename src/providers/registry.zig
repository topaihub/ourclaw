const std = @import("std");
const framework = @import("framework");
const contracts = @import("contracts.zig");
const security = @import("../security/policy.zig");
const openai_compatible = @import("openai_compatible.zig");
const status = @import("status.zig");

pub const ProviderErrorInfo = contracts.ProviderErrorInfo;
pub const ProviderRequest = contracts.ProviderRequest;
pub const ProviderResponse = contracts.ProviderResponse;
pub const ProviderStreamChunk = contracts.ProviderStreamChunk;
pub const EmbeddingRequest = contracts.EmbeddingRequest;
pub const EmbeddingResponse = contracts.EmbeddingResponse;
pub const EmbeddingProvider = contracts.EmbeddingProvider;
pub const ProviderDefinition = contracts.ProviderDefinition;
pub const ProviderHealth = status.ProviderHealth;
pub const ProviderModelInfo = status.ProviderModelInfo;

pub const ProviderRegistry = struct {
    allocator: std.mem.Allocator,
    definitions: std.ArrayListUnmanaged(ProviderDefinition) = .empty,
    secret_store: ?*security.MemorySecretStore = null,
    refresh_count: usize = 0,
    last_refresh_reason: ?[]u8 = null,
    logger: ?*framework.Logger = null,

    const Self = @This();

    const embedding_provider_vtable = EmbeddingProvider.VTable{
        .supports_embeddings = supportsEmbeddingsErased,
        .embed_text = embedTextErased,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        if (self.last_refresh_reason) |reason| self.allocator.free(reason);
        self.definitions.deinit(self.allocator);
    }

    pub fn setLogger(self: *Self, logger: *framework.Logger) void {
        self.logger = logger;
    }

    pub fn markConfigRefresh(self: *Self, reason: []const u8) anyerror!void {
        if (self.last_refresh_reason) |previous| self.allocator.free(previous);
        self.last_refresh_reason = try self.allocator.dupe(u8, reason);
        self.refresh_count += 1;
    }

    pub fn asEmbeddingProvider(self: *const Self) EmbeddingProvider {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &embedding_provider_vtable,
        };
    }

    pub fn register(self: *Self, definition: ProviderDefinition) anyerror!void {
        if (self.find(definition.id) != null) return error.DuplicateProvider;
        try self.definitions.append(self.allocator, definition);
    }

    pub fn registerBuiltins(self: *Self) anyerror!void {
        try self.register(.{
            .id = "openai",
            .label = "OpenAI",
            .endpoint = "https://api.openai.com/v1/chat/completions",
            .default_model = "gpt-4o-mini",
            .default_embedding_model = "text-embedding-3-small",
            .api_key_secret_ref = "openai:api_key",
            .supports_streaming = true,
            .supports_tools = true,
            .supports_embeddings = true,
            .models = &.{ "gpt-4o-mini", "gpt-4.1-mini", "gpt-4o" },
            .health_json = "{\"provider\":\"openai\",\"healthy\":true}",
        });
        try self.register(.{
            .id = "anthropic",
            .label = "Anthropic",
            .endpoint = "https://api.anthropic.com/v1/messages",
            .default_model = "claude-3-5-sonnet-latest",
            .api_key_secret_ref = "anthropic:api_key",
            .supports_streaming = false,
            .supports_tools = false,
            .models = &.{"claude-3-5-sonnet-latest"},
            .health_json = "{\"provider\":\"anthropic\",\"healthy\":true}",
        });
    }

    pub fn setSecretStore(self: *Self, secret_store: *security.MemorySecretStore) void {
        self.secret_store = secret_store;
    }

    pub fn healthJson(self: *const Self, allocator: std.mem.Allocator, id: []const u8) anyerror![]u8 {
        const definition = self.find(id) orelse return error.ProviderNotFound;
        return allocator.dupe(u8, definition.health_json);
    }

    pub fn supportsTools(self: *const Self, id: []const u8) anyerror!bool {
        const definition = self.find(id) orelse return error.ProviderNotFound;
        return definition.supports_tools;
    }

    pub fn supportsEmbeddings(self: *const Self, id: []const u8) anyerror!bool {
        const definition = self.find(id) orelse return error.ProviderNotFound;
        return definition.supports_embeddings;
    }

    pub fn health(self: *const Self, allocator: std.mem.Allocator, id: []const u8) anyerror!ProviderHealth {
        const definition = self.find(id) orelse return error.ProviderNotFound;
        return .{
            .provider_id = try allocator.dupe(u8, definition.id),
            .healthy = self.secret_store != null and self.secret_store.?.get(definition.api_key_secret_ref) != null,
            .supports_streaming = definition.supports_streaming,
            .endpoint = try allocator.dupe(u8, definition.endpoint),
            .message = try allocator.dupe(u8, if (self.secret_store != null and self.secret_store.?.get(definition.api_key_secret_ref) != null) "ready" else "missing_api_key"),
        };
    }

    pub fn listModels(self: *const Self, allocator: std.mem.Allocator, id: []const u8) anyerror![]ProviderModelInfo {
        const definition = self.find(id) orelse return error.ProviderNotFound;
        const model_ids = if (definition.models.len > 0) definition.models else &.{definition.default_model};
        const models = try allocator.alloc(ProviderModelInfo, model_ids.len);
        errdefer allocator.free(models);

        for (model_ids, 0..) |model_id, index| {
            models[index] = .{
                .id = try allocator.dupe(u8, model_id),
                .label = try allocator.dupe(u8, model_id),
                .supports_streaming = definition.supports_streaming,
                .supports_tools = definition.supports_tools,
            };
        }

        return models;
    }

    pub fn chatOnce(self: *const Self, allocator: std.mem.Allocator, request: ProviderRequest) anyerror!ProviderResponse {
        if (request.cancel_requested) |signal| {
            if (signal.load(.acquire)) return error.StreamCancelled;
        }
        const definition = self.find(request.provider_id) orelse return error.ProviderNotFound;
        const secret_store = self.secret_store orelse return error.SecretStoreUnavailable;
        const api_key = secret_store.get(definition.api_key_secret_ref) orelse return error.ProviderApiKeyMissing;

        var attempt: u8 = 0;
        const max_attempts: u8 = request.retry_budget + 1;
        while (attempt < max_attempts) : (attempt += 1) {
            if (request.cancel_requested) |signal| {
                if (signal.load(.acquire)) return error.StreamCancelled;
            }
            if (request.remaining_attempt_budget) |budget| {
                if (budget.* == 0) return error.ProviderAttemptBudgetExceeded;
                budget.* -= 1;
            }
            if (std.mem.eql(u8, definition.id, "openai") or std.mem.startsWith(u8, definition.endpoint, "mock://openai")) {
                return openai_compatible.chatOnce(allocator, definition, request, api_key) catch |err| {
                    const mapped = mapError(err);
                    if (!mapped.retriable) return err;
                    if (attempt + 1 >= max_attempts) {
                        if (request.retry_budget > 0 and err == error.ProviderTemporaryUnavailable) return error.ProviderRetryExhausted;
                        return err;
                    }
                    continue;
                };
            }
        }

        return error.ProviderNotImplemented;
    }

    pub fn chatStream(self: *const Self, allocator: std.mem.Allocator, request: ProviderRequest) anyerror![]ProviderStreamChunk {
        const params_summary = try std.fmt.allocPrint(
            allocator,
            "{{\"providerId\":\"{s}\",\"model\":\"{s}\",\"messageCount\":{d},\"enableTools\":{s}}}",
            .{ request.provider_id, request.model orelse "default", request.messages.len, if (request.enable_tools) "true" else "false" },
        );
        defer allocator.free(params_summary);

        var method_trace: ?framework.observability.MethodTrace = null;
        var summary_trace: ?framework.observability.SummaryTrace = null;
        if (self.logger) |logger| {
            const method_name = try std.fmt.allocPrint(allocator, "Provider.{s}.chatStream", .{request.provider_id});
            defer allocator.free(method_name);
            method_trace = try framework.observability.MethodTrace.begin(allocator, logger, method_name, params_summary, 3000);
            summary_trace = try framework.observability.SummaryTrace.begin(allocator, logger, method_name, 3000);
        }
        defer {
            if (method_trace) |*trace| trace.deinit();
            if (summary_trace) |*trace| trace.deinit();
        }

        if (request.cancel_requested) |signal| {
            if (signal.load(.acquire)) {
                if (method_trace) |*trace| trace.finishError("StreamCancelled", "STREAM_CANCELLED", false);
                if (summary_trace) |*trace| trace.finishError(.business);
                return error.StreamCancelled;
            }
        }
        const definition = self.find(request.provider_id) orelse {
            if (method_trace) |*trace| trace.finishError("ProviderNotFound", "PROVIDER_NOT_FOUND", false);
            if (summary_trace) |*trace| trace.finishError(.business);
            return error.ProviderNotFound;
        };
        const secret_store = self.secret_store orelse {
            if (method_trace) |*trace| trace.finishError("SecretStoreUnavailable", "SECRET_STORE_UNAVAILABLE", false);
            if (summary_trace) |*trace| trace.finishError(.system);
            return error.SecretStoreUnavailable;
        };
        const api_key = secret_store.get(definition.api_key_secret_ref) orelse {
            if (method_trace) |*trace| trace.finishError("ProviderApiKeyMissing", "PROVIDER_API_KEY_MISSING", false);
            if (summary_trace) |*trace| trace.finishError(.business);
            return error.ProviderApiKeyMissing;
        };

        var attempt: u8 = 0;
        const max_attempts: u8 = request.retry_budget + 1;
        while (attempt < max_attempts) : (attempt += 1) {
            if (request.cancel_requested) |signal| {
                if (signal.load(.acquire)) {
                    if (method_trace) |*trace| trace.finishError("StreamCancelled", "STREAM_CANCELLED", false);
                    if (summary_trace) |*trace| trace.finishError(.business);
                    return error.StreamCancelled;
                }
            }
            if (request.remaining_attempt_budget) |budget| {
                if (budget.* == 0) {
                    if (method_trace) |*trace| trace.finishError("ProviderAttemptBudgetExceeded", "PROVIDER_ATTEMPT_BUDGET_EXCEEDED", false);
                    if (summary_trace) |*trace| trace.finishError(.business);
                    return error.ProviderAttemptBudgetExceeded;
                }
                budget.* -= 1;
            }
            if (std.mem.eql(u8, definition.id, "openai") or std.mem.startsWith(u8, definition.endpoint, "mock://openai")) {
                const chunks = openai_compatible.chatStream(allocator, definition, request, api_key) catch |err| {
                    const mapped = mapError(err);
                    if (!mapped.retriable) {
                        if (method_trace) |*trace| trace.finishError(@errorName(err), mapped.code, false);
                        if (summary_trace) |*trace| trace.finishError(.system);
                        return err;
                    }
                    if (attempt + 1 >= max_attempts) {
                        if (request.retry_budget > 0 and err == error.ProviderTemporaryUnavailable) {
                            if (method_trace) |*trace| trace.finishError("ProviderRetryExhausted", "PROVIDER_RETRY_EXHAUSTED", false);
                            if (summary_trace) |*trace| trace.finishError(.system);
                            return error.ProviderRetryExhausted;
                        }
                        if (method_trace) |*trace| trace.finishError(@errorName(err), mapped.code, false);
                        if (summary_trace) |*trace| trace.finishError(.system);
                        return err;
                    }
                    continue;
                };
                const result_summary = try std.fmt.allocPrint(allocator, "{{\"chunkCount\":{d}}}", .{chunks.len});
                defer allocator.free(result_summary);
                if (method_trace) |*trace| trace.finishSuccess(result_summary, false);
                if (summary_trace) |*trace| trace.finishSuccess();
                return chunks;
            }
        }

        if (method_trace) |*trace| trace.finishError("ProviderNotImplemented", "PROVIDER_NOT_IMPLEMENTED", false);
        if (summary_trace) |*trace| trace.finishError(.system);
        return error.ProviderNotImplemented;
    }

    pub fn embedText(self: *const Self, allocator: std.mem.Allocator, request: EmbeddingRequest) anyerror!EmbeddingResponse {
        const definition = self.find(request.provider_id) orelse return error.ProviderNotFound;
        if (!definition.supports_embeddings) return error.ProviderEmbeddingsUnsupported;

        const secret_store = self.secret_store orelse return error.SecretStoreUnavailable;
        const api_key = secret_store.get(definition.api_key_secret_ref) orelse return error.ProviderApiKeyMissing;

        if (std.mem.eql(u8, definition.id, "openai") or std.mem.startsWith(u8, definition.endpoint, "mock://openai")) {
            return openai_compatible.embedText(allocator, definition, request, api_key);
        }

        return error.ProviderEmbeddingNotImplemented;
    }

    pub fn find(self: *const Self, id: []const u8) ?ProviderDefinition {
        for (self.definitions.items) |definition| {
            if (std.mem.eql(u8, definition.id, id)) return definition;
        }
        return null;
    }

    pub fn count(self: *const Self) usize {
        return self.definitions.items.len;
    }

    pub fn mapError(err: anyerror) ProviderErrorInfo {
        return switch (err) {
            error.ProviderNotFound => .{ .code = "PROVIDER_NOT_FOUND", .message = "provider is not registered", .retriable = false },
            error.SecretStoreUnavailable => .{ .code = "PROVIDER_SECRET_STORE_UNAVAILABLE", .message = "provider secret store is unavailable", .retriable = false },
            error.ProviderApiKeyMissing => .{ .code = "PROVIDER_API_KEY_MISSING", .message = "provider api key is missing", .retriable = false },
            error.ProviderMalformedResponse => .{ .code = "PROVIDER_MALFORMED_RESPONSE", .message = "provider returned malformed response", .retriable = true },
            error.ProviderTimeout => .{ .code = "PROVIDER_TIMEOUT", .message = "provider request timed out", .retriable = true },
            error.ProviderTemporaryUnavailable => .{ .code = "PROVIDER_TEMPORARY_UNAVAILABLE", .message = "provider is temporarily unavailable", .retriable = true },
            error.ProviderHttpFailed => .{ .code = "PROVIDER_HTTP_FAILED", .message = "provider request failed", .retriable = true },
            error.ProviderAttemptBudgetExceeded => .{ .code = "PROVIDER_ATTEMPT_BUDGET_EXCEEDED", .message = "provider attempt budget has been exhausted", .retriable = false },
            error.ProviderRetryExhausted => .{ .code = "PROVIDER_RETRY_EXHAUSTED", .message = "provider retry budget exhausted", .retriable = false },
            else => .{ .code = "PROVIDER_EXECUTION_FAILED", .message = "provider execution failed", .retriable = false },
        };
    }

    fn supportsEmbeddingsErased(ptr: *const anyopaque, provider_id: []const u8) anyerror!bool {
        const self: *const Self = @ptrCast(@alignCast(ptr));
        return self.supportsEmbeddings(provider_id);
    }

    fn embedTextErased(ptr: *const anyopaque, allocator: std.mem.Allocator, request: EmbeddingRequest) anyerror!EmbeddingResponse {
        const self: *const Self = @ptrCast(@alignCast(ptr));
        return self.embedText(allocator, request);
    }
};
