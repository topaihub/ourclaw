const framework = @import("framework");
const domain = @import("../../domain/root.zig");
const services_model = domain.services;

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "diagnostics.repo_health",
        .method = "diagnostics.repo_health",
        .description = "Run framework-backed repository health checks",
        .authority = .operator,
        .params = framework.RepoHealthCheckTool.tool_params,
        .user_data = @ptrCast(command_services),
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    return services.framework_tooling.runRepoHealth(
        ctx.allocator,
        ctx.request,
        ctx.validated_params,
    );
}
