const std = @import("std");
const contracts = @import("contracts.zig");
const registry = @import("registry.zig");

pub const file_read = @import("file_read.zig");
pub const shell = @import("shell.zig");
pub const http_request = @import("http_request.zig");

pub const MODULE_NAME = "tools";

pub const ToolExecutionContext = contracts.ToolExecutionContext;
pub const ToolHandler = contracts.ToolHandler;
pub const ToolRiskLevel = contracts.ToolRiskLevel;
pub const ToolDefinition = contracts.ToolDefinition;
pub const ToolErrorInfo = contracts.ToolErrorInfo;
pub const ToolInvokePolicy = contracts.ToolInvokePolicy;
pub const ToolRegistry = registry.ToolRegistry;

test "tool root keeps contract and registry exports stable" {
    _ = ToolExecutionContext;
    _ = ToolHandler;
    _ = ToolRiskLevel;
    _ = ToolDefinition;
    _ = ToolErrorInfo;
    _ = ToolInvokePolicy;
    _ = ToolRegistry;
    try std.testing.expectEqualStrings("tools", MODULE_NAME);
}
