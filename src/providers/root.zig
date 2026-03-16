const std = @import("std");
const framework = @import("framework");
const security = @import("../security/policy.zig");
const openai_compatible = @import("openai_compatible.zig");

pub const MODULE_NAME = "providers";

pub const ProviderRole = enum {
    system,
    user,
    assistant,
    tool,

    pub fn asText(self: ProviderRole) []const u8 {
        return switch (self) {
            .system => "system",
            .user => "user",
            .assistant => "assistant",
            .tool => "tool",
        };
    }
};

pub const ProviderMessage = struct {
    role: ProviderRole,
    content: []const u8,
};

pub const ProviderRequest = struct {
    provider_id: []const u8,
    model: ?[]const u8 = null,
    messages: []const ProviderMessage,
    enable_tools: bool = false,
    timeout_secs: u32 = 60,
    retry_budget: u8 = 0,
    remaining_attempt_budget: ?*usize = null,
    cancel_requested: ?*const std.atomic.Value(bool) = null,
};

pub const ProviderErrorInfo = struct {
    code: []const u8,
    message: []const u8,
    retriable: bool,
};

pub const EmbeddingDimensions: usize = 8;

pub const EmbeddingStrategy = enum {
    provider_proxy_v1,
};

pub const EmbeddingVector = [EmbeddingDimensions]f32;

pub const EmbeddingRequest = struct {
    provider_id: []const u8,
    model: ?[]const u8 = null,
    input: []const u8,
};

pub const EmbeddingResponse = struct {
    provider_id: []u8,
    model: []u8,
    strategy: EmbeddingStrategy,
    vector: EmbeddingVector,

    pub fn deinit(self: *EmbeddingResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.provider_id);
        allocator.free(self.model);
    }
};

pub const EmbeddingProvider = struct {
    ptr: *const anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        supports_embeddings: *const fn (ptr: *const anyopaque, provider_id: []const u8) anyerror!bool,
        embed_text: *const fn (ptr: *const anyopaque, allocator: std.mem.Allocator, request: EmbeddingRequest) anyerror!EmbeddingResponse,
    };

    pub fn supportsEmbeddings(self: EmbeddingProvider, provider_id: []const u8) anyerror!bool {
        return self.vtable.supports_embeddings(self.ptr, provider_id);
    }

    pub fn embedText(self: EmbeddingProvider, allocator: std.mem.Allocator, request: EmbeddingRequest) anyerror!EmbeddingResponse {
        return self.vtable.embed_text(self.ptr, allocator, request);
    }
};

pub const ProviderModelInfo = struct {
    id: []const u8,
    label: []const u8,
    supports_streaming: bool,
    supports_tools: bool,
};

pub const ProviderHealth = struct {
    provider_id: []u8,
    healthy: bool,
    supports_streaming: bool,
    endpoint: []u8,
    message: []u8,

    pub fn deinit(self: *ProviderHealth, allocator: std.mem.Allocator) void {
        allocator.free(self.provider_id);
        allocator.free(self.endpoint);
        allocator.free(self.message);
    }
};

pub const ProviderStreamChunk = struct {
    kind: Kind,
    text: ?[]u8 = null,
    tool_name: ?[]u8 = null,
    tool_input_json: ?[]u8 = null,
    finish_reason: ?[]u8 = null,
    prompt_tokens: ?u32 = null,
    completion_tokens: ?u32 = null,

    pub const Kind = enum {
        text_delta,
        tool_call,
        done,
    };

    pub fn deinit(self: *ProviderStreamChunk, allocator: std.mem.Allocator) void {
        if (self.text) |value| allocator.free(value);
        if (self.tool_name) |value| allocator.free(value);
        if (self.tool_input_json) |value| allocator.free(value);
        if (self.finish_reason) |value| allocator.free(value);
    }
};

pub const ProviderResponse = struct {
    provider_id: []u8,
    model: []u8,
    text: []u8,
    tool_name: ?[]u8 = null,
    tool_input_json: ?[]u8 = null,
    finish_reason: ?[]u8 = null,
    prompt_tokens: ?u32 = null,
    completion_tokens: ?u32 = null,
    raw_json: ?[]u8 = null,

    pub fn deinit(self: *ProviderResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.provider_id);
        allocator.free(self.model);
        allocator.free(self.text);
        if (self.tool_name) |value| allocator.free(value);
        if (self.tool_input_json) |value| allocator.free(value);
        if (self.finish_reason) |value| allocator.free(value);
        if (self.raw_json) |value| allocator.free(value);
    }
};

pub const ProviderDefinition = struct {
    id: []const u8,
    label: []const u8,
    required_authority: framework.Authority = .operator,
    endpoint: []const u8 = "",
    default_model: []const u8 = "gpt-4o-mini",
    default_embedding_model: []const u8 = "text-embedding-3-small",
    api_key_secret_ref: []const u8 = "openai:api_key",
    supports_streaming: bool = false,
    supports_tools: bool = false,
    supports_embeddings: bool = false,
    models: []const []const u8 = &.{},
    health_json: []const u8,
};

pub const ProviderRegistry = struct {
    allocator: std.mem.Allocator,
    definitions: std.ArrayListUnmanaged(ProviderDefinition) = .empty,
    secret_store: ?*security.MemorySecretStore = null,
    refresh_count: usize = 0,
    last_refresh_reason: ?[]u8 = null,

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
                return openai_compatible.chatStream(allocator, definition, request, api_key) catch |err| {
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

test "provider registry registers builtin providers" {
    var registry = ProviderRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try registry.registerBuiltins();
    try std.testing.expectEqual(@as(usize, 2), registry.count());
    try std.testing.expect(registry.find("openai") != null);
}

test "provider registry can execute openai-compatible request with mock endpoint" {
    var registry = ProviderRegistry.init(std.testing.allocator);
    defer registry.deinit();
    var secrets = security.MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    registry.setSecretStore(&secrets);
    try registry.register(.{
        .id = "mock_openai",
        .label = "Mock OpenAI",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    });

    var response = try registry.chatOnce(std.testing.allocator, .{
        .provider_id = "mock_openai",
        .messages = &.{.{ .role = .user, .content = "hello" }},
    });
    defer response.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("mock openai response", response.text);
}

test "provider registry exposes health models and streaming" {
    var registry = ProviderRegistry.init(std.testing.allocator);
    defer registry.deinit();
    var secrets = security.MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    registry.setSecretStore(&secrets);
    try registry.register(.{
        .id = "mock_openai_stream",
        .label = "Mock OpenAI Stream",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .models = &.{ "gpt-4o-mini", "gpt-4o" },
        .health_json = "{}",
    });

    var health = try registry.health(std.testing.allocator, "mock_openai_stream");
    defer health.deinit(std.testing.allocator);
    try std.testing.expect(health.healthy);
    try std.testing.expect(health.supports_streaming);

    const models = try registry.listModels(std.testing.allocator, "mock_openai_stream");
    defer {
        for (models) |model| {
            std.testing.allocator.free(model.id);
            std.testing.allocator.free(model.label);
        }
        std.testing.allocator.free(models);
    }
    try std.testing.expect(models.len >= 1);

    const chunks = try registry.chatStream(std.testing.allocator, .{
        .provider_id = "mock_openai_stream",
        .messages = &.{.{ .role = .user, .content = "hello" }},
    });
    defer {
        for (chunks) |*chunk| chunk.deinit(std.testing.allocator);
        std.testing.allocator.free(chunks);
    }
    try std.testing.expect(chunks.len >= 2);
}

test "provider registry exposes embedding requests" {
    var registry = ProviderRegistry.init(std.testing.allocator);
    defer registry.deinit();
    var secrets = security.MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    registry.setSecretStore(&secrets);
    try registry.register(.{
        .id = "mock_openai_embedding",
        .label = "Mock OpenAI Embedding",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .default_embedding_model = "text-embedding-3-small",
        .api_key_secret_ref = "openai:api_key",
        .supports_embeddings = true,
        .health_json = "{}",
    });

    const embedding_provider = registry.asEmbeddingProvider();
    try std.testing.expect(try embedding_provider.supportsEmbeddings("mock_openai_embedding"));

    var embedding = try embedding_provider.embedText(std.testing.allocator, .{
        .provider_id = "mock_openai_embedding",
        .input = "gateway status ready",
    });
    defer embedding.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("mock_openai_embedding", embedding.provider_id);
    try std.testing.expectEqualStrings("text-embedding-3-small", embedding.model);
    try std.testing.expectEqual(EmbeddingStrategy.provider_proxy_v1, embedding.strategy);
}

test "provider registry retries transient provider failures" {
    var registry = ProviderRegistry.init(std.testing.allocator);
    defer registry.deinit();
    var secrets = security.MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    registry.setSecretStore(&secrets);
    try registry.register(.{
        .id = "mock_openai_retry_once",
        .label = "Mock OpenAI Retry Once",
        .endpoint = "mock://openai/chat_retry_once",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    });

    var response = try registry.chatOnce(std.testing.allocator, .{
        .provider_id = "mock_openai_retry_once",
        .messages = &.{.{ .role = .user, .content = "hello" }},
        .retry_budget = 1,
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("mock openai response", response.text);
}

test "provider registry surfaces retry exhaustion for streaming" {
    var registry = ProviderRegistry.init(std.testing.allocator);
    defer registry.deinit();
    var secrets = security.MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    registry.setSecretStore(&secrets);
    try registry.register(.{
        .id = "mock_openai_stream_retry_exhausted",
        .label = "Mock OpenAI Stream Retry Exhausted",
        .endpoint = "mock://openai/chat_stream_retry_exhausted",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    });

    try std.testing.expectError(error.ProviderRetryExhausted, registry.chatStream(std.testing.allocator, .{
        .provider_id = "mock_openai_stream_retry_exhausted",
        .messages = &.{.{ .role = .user, .content = "hello" }},
        .retry_budget = 1,
    }));
}

test "provider registry maps timeout as retriable provider error" {
    const mapped = ProviderRegistry.mapError(error.ProviderTimeout);
    try std.testing.expectEqualStrings("PROVIDER_TIMEOUT", mapped.code);
    try std.testing.expect(mapped.retriable);
}

test "provider registry maps retry exhaustion as terminal provider error" {
    const mapped = ProviderRegistry.mapError(error.ProviderRetryExhausted);
    try std.testing.expectEqualStrings("PROVIDER_RETRY_EXHAUSTED", mapped.code);
    try std.testing.expect(!mapped.retriable);
}

test "provider registry surfaces attempt budget exhaustion" {
    var registry = ProviderRegistry.init(std.testing.allocator);
    defer registry.deinit();
    var secrets = security.MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    registry.setSecretStore(&secrets);
    try registry.register(.{
        .id = "mock_openai_attempt_budget",
        .label = "Mock OpenAI Attempt Budget",
        .endpoint = "mock://openai/chat_retry_once",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    });

    var remaining_attempt_budget: usize = 0;
    try std.testing.expectError(error.ProviderAttemptBudgetExceeded, registry.chatStream(std.testing.allocator, .{
        .provider_id = "mock_openai_attempt_budget",
        .messages = &.{.{ .role = .user, .content = "hello" }},
        .retry_budget = 1,
        .remaining_attempt_budget = &remaining_attempt_budget,
    }));
}
