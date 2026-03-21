const std = @import("std");
const framework = @import("framework");

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
