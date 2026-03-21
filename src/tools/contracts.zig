const std = @import("std");
const framework = @import("framework");

pub const ToolExecutionContext = struct {
    cancel_requested: ?*const std.atomic.Value(bool) = null,

    pub fn isCancelled(self: ToolExecutionContext) bool {
        return if (self.cancel_requested) |signal| signal.load(.acquire) else false;
    }
};

pub const ToolHandler = *const fn (ctx: ToolExecutionContext, allocator: std.mem.Allocator, input_json: []const u8) anyerror![]u8;

pub const ToolRiskLevel = enum {
    low,
    medium,
    high,

    pub fn asText(self: ToolRiskLevel) []const u8 {
        return switch (self) {
            .low => "low",
            .medium => "medium",
            .high => "high",
        };
    }
};

pub const ToolDefinition = struct {
    id: []const u8,
    description: []const u8,
    required_authority: framework.Authority = .public,
    risk_level: ToolRiskLevel = .low,
    parameters_json: []const u8 = "{}",
    required_fields: []const []const u8 = &.{},
    handler: ToolHandler,
};

pub const ToolErrorInfo = struct {
    code: []const u8,
    message: []const u8,
};

pub const ToolInvokePolicy = struct {
    confirm_risk: bool = false,
    cancel_requested: ?*const std.atomic.Value(bool) = null,
};

test "tool contracts export stability" {
    _ = ToolExecutionContext;
    _ = ToolHandler;
    _ = ToolRiskLevel;
    _ = ToolDefinition;
    _ = ToolErrorInfo;
    _ = ToolInvokePolicy;
}
