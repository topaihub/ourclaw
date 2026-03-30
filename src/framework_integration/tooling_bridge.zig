const std = @import("std");
const framework = @import("framework");

pub const ToolingBridge = struct {
    allocator: std.mem.Allocator,
    effects_runtime: framework.EffectsRuntime,
    registry: framework.ToolRegistry,
    tooling_runtime: *framework.ToolingRuntime,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, app_context: *framework.AppContext) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .effects_runtime = framework.EffectsRuntime.init(.{}),
            .registry = framework.ToolRegistry.init(allocator),
            .tooling_runtime = undefined,
        };
        errdefer self.registry.deinit();

        try self.registry.register(framework.defineTool(framework.RepoHealthCheckTool));

        self.tooling_runtime = try framework.ToolingRuntime.init(.{
            .allocator = allocator,
            .app_context = app_context,
            .effects = &self.effects_runtime,
            .registry = &self.registry,
        });
        errdefer self.tooling_runtime.deinit();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.tooling_runtime.deinit();
        self.registry.deinit();
        self.allocator.destroy(self);
    }

    pub fn runRepoHealth(
        self: *Self,
        allocator: std.mem.Allocator,
        request: framework.RequestContext,
        params: []const framework.ValidationField,
    ) ![]u8 {
        var result = try self.tooling_runtime.tool_runner.run(.{
            .tool_id = framework.RepoHealthCheckTool.tool_id,
            .request = request,
            .params = params,
        });
        defer result.deinit(self.allocator);

        return try allocator.dupe(u8, result.output_json);
    }
};

test "tooling bridge runs repo health tool through framework runtime" {
    var app_context = try framework.AppContext.init(std.testing.allocator, .{
        .console_log_enabled = false,
    });
    defer app_context.deinit();

    const bridge = try ToolingBridge.init(std.testing.allocator, &app_context);
    defer bridge.deinit();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const root_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root_path);

    const git_path = try std.fs.path.join(std.testing.allocator, &.{ root_path, ".git" });
    defer std.testing.allocator.free(git_path);
    try bridge.effects_runtime.file_system.makePath(git_path);

    const src_path = try std.fs.path.join(std.testing.allocator, &.{ root_path, "src" });
    defer std.testing.allocator.free(src_path);
    try bridge.effects_runtime.file_system.makePath(src_path);

    const build_path = try std.fs.path.join(std.testing.allocator, &.{ root_path, "build.zig" });
    defer std.testing.allocator.free(build_path);
    try bridge.effects_runtime.file_system.writeFile(build_path, "pub fn build(_: *std.Build) void {}");

    const params = [_]framework.ValidationField{
        .{ .key = "path", .value = .{ .string = root_path } },
    };

    const output = try bridge.runRepoHealth(
        std.testing.allocator,
        .{
            .request_id = "ourclaw_bridge_repo_health_01",
            .source = .@"test",
            .authority = .operator,
        },
        params[0..],
    );
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "\"status\":\"healthy\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"has_src_dir\":true") != null);
}
