const std = @import("std");
const contracts = @import("contracts.zig");
const registry = @import("registry.zig");
const security = @import("../security/policy.zig");
const status = @import("status.zig");

pub const MODULE_NAME = "providers";

pub const ProviderRole = contracts.ProviderRole;
pub const ProviderMessage = contracts.ProviderMessage;
pub const ProviderRequest = contracts.ProviderRequest;
pub const ProviderErrorInfo = contracts.ProviderErrorInfo;
pub const EmbeddingDimensions = contracts.EmbeddingDimensions;
pub const EmbeddingStrategy = contracts.EmbeddingStrategy;
pub const EmbeddingVector = contracts.EmbeddingVector;
pub const EmbeddingRequest = contracts.EmbeddingRequest;
pub const EmbeddingResponse = contracts.EmbeddingResponse;
pub const EmbeddingProvider = contracts.EmbeddingProvider;
pub const ProviderStreamChunk = contracts.ProviderStreamChunk;
pub const ProviderResponse = contracts.ProviderResponse;
pub const ProviderDefinition = contracts.ProviderDefinition;
pub const ProviderModelInfo = status.ProviderModelInfo;
pub const ProviderHealth = status.ProviderHealth;
pub const ProviderRegistry = registry.ProviderRegistry;

test "provider registry registers builtin providers" {
    var registry_instance = ProviderRegistry.init(std.testing.allocator);
    defer registry_instance.deinit();
    try registry_instance.registerBuiltins();
    try std.testing.expectEqual(@as(usize, 2), registry_instance.count());
    try std.testing.expect(registry_instance.find("openai") != null);
}

test "provider registry can execute openai-compatible request with mock endpoint" {
    var registry_instance = ProviderRegistry.init(std.testing.allocator);
    defer registry_instance.deinit();
    var secrets = security.MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    registry_instance.setSecretStore(&secrets);
    try registry_instance.register(.{
        .id = "mock_openai",
        .label = "Mock OpenAI",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    });

    var response = try registry_instance.chatOnce(std.testing.allocator, .{
        .provider_id = "mock_openai",
        .messages = &.{.{ .role = .user, .content = "hello" }},
    });
    defer response.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("mock openai response", response.text);
}

test "provider registry exposes health models and streaming" {
    var registry_instance = ProviderRegistry.init(std.testing.allocator);
    defer registry_instance.deinit();
    var secrets = security.MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    registry_instance.setSecretStore(&secrets);
    try registry_instance.register(.{
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

    var health = try registry_instance.health(std.testing.allocator, "mock_openai_stream");
    defer health.deinit(std.testing.allocator);
    try std.testing.expect(health.healthy);
    try std.testing.expect(health.supports_streaming);

    const models = try registry_instance.listModels(std.testing.allocator, "mock_openai_stream");
    defer {
        for (models) |model| {
            std.testing.allocator.free(model.id);
            std.testing.allocator.free(model.label);
        }
        std.testing.allocator.free(models);
    }
    try std.testing.expect(models.len >= 1);

    const chunks = try registry_instance.chatStream(std.testing.allocator, .{
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
    var registry_instance = ProviderRegistry.init(std.testing.allocator);
    defer registry_instance.deinit();
    var secrets = security.MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    registry_instance.setSecretStore(&secrets);
    try registry_instance.register(.{
        .id = "mock_openai_embedding",
        .label = "Mock OpenAI Embedding",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .default_embedding_model = "text-embedding-3-small",
        .api_key_secret_ref = "openai:api_key",
        .supports_embeddings = true,
        .health_json = "{}",
    });

    const embedding_provider = registry_instance.asEmbeddingProvider();
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
    var registry_instance = ProviderRegistry.init(std.testing.allocator);
    defer registry_instance.deinit();
    var secrets = security.MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    registry_instance.setSecretStore(&secrets);
    try registry_instance.register(.{
        .id = "mock_openai_retry_once",
        .label = "Mock OpenAI Retry Once",
        .endpoint = "mock://openai/chat_retry_once",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    });

    var response = try registry_instance.chatOnce(std.testing.allocator, .{
        .provider_id = "mock_openai_retry_once",
        .messages = &.{.{ .role = .user, .content = "hello" }},
        .retry_budget = 1,
    });
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("mock openai response", response.text);
}

test "provider registry surfaces retry exhaustion for streaming" {
    var registry_instance = ProviderRegistry.init(std.testing.allocator);
    defer registry_instance.deinit();
    var secrets = security.MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    registry_instance.setSecretStore(&secrets);
    try registry_instance.register(.{
        .id = "mock_openai_stream_retry_exhausted",
        .label = "Mock OpenAI Stream Retry Exhausted",
        .endpoint = "mock://openai/chat_stream_retry_exhausted",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    });

    try std.testing.expectError(error.ProviderRetryExhausted, registry_instance.chatStream(std.testing.allocator, .{
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

test "provider root keeps contract and status exports stable" {
    _ = ProviderRole;
    _ = ProviderMessage;
    _ = ProviderRequest;
    _ = ProviderResponse;
    _ = ProviderStreamChunk;
    _ = ProviderHealth;
    _ = ProviderModelInfo;
    _ = ProviderDefinition;
    _ = ProviderRegistry;
    _ = EmbeddingRequest;
    _ = EmbeddingResponse;
    _ = EmbeddingProvider;
}

test "provider registry surfaces attempt budget exhaustion" {
    var registry_instance = ProviderRegistry.init(std.testing.allocator);
    defer registry_instance.deinit();
    var secrets = security.MemorySecretStore.init(std.testing.allocator);
    defer secrets.deinit();
    try secrets.put("openai:api_key", "test-key");
    registry_instance.setSecretStore(&secrets);
    try registry_instance.register(.{
        .id = "mock_openai_attempt_budget",
        .label = "Mock OpenAI Attempt Budget",
        .endpoint = "mock://openai/chat_retry_once",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .health_json = "{}",
    });

    var remaining_attempt_budget: usize = 0;
    try std.testing.expectError(error.ProviderAttemptBudgetExceeded, registry_instance.chatStream(std.testing.allocator, .{
        .provider_id = "mock_openai_attempt_budget",
        .messages = &.{.{ .role = .user, .content = "hello" }},
        .retry_budget = 1,
        .remaining_attempt_budget = &remaining_attempt_budget,
    }));
}
