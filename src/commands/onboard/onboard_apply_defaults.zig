const std = @import("std");
const framework = @import("framework");
const registry = @import("../../config/field_registry.zig");
const runtime_app = @import("../../runtime/app_context.zig");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "onboard.apply_defaults",
        .method = "onboard.apply_defaults",
        .description = "Apply safe onboarding defaults",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{
            .{ .key = "install_service", .required = false, .value_kind = .boolean },
        },
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    const app: *runtime_app.AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    const install_service = if (ctx.param("install_service")) |field| field.value.boolean else false;
    var trace = try framework.StepTrace.begin(ctx.allocator, app.framework_context.logger, "onboard", "apply_defaults", 1000);
    defer trace.deinit();

    const pairing_field = registry.ConfigFieldRegistry.find("gateway.require_pairing") orelse return error.ConfigFieldUnknown;
    const max_tool_rounds_field = registry.ConfigFieldRegistry.find("runtime.max_tool_rounds") orelse return error.ConfigFieldUnknown;
    const updates = [_]framework.ValidationField{
        .{ .key = "gateway.require_pairing", .value = .{ .boolean = true } },
        .{ .key = "runtime.max_tool_rounds", .value = .{ .integer = 4 } },
    };
    const write_fields = [_]framework.FieldDefinition{ pairing_field.field_definition, max_tool_rounds_field.field_definition };

    var pipeline = app.makeConfigPipeline(write_fields[0..], registry.ConfigFieldRegistry.configRules());
    var attempt = try pipeline.applyWrite(updates[0..], false);
    defer attempt.deinit();
    if (!attempt.report.isOk()) {
        trace.finish("ValidationFailed");
        return error.ValidationFailed;
    }

    app.effective_gateway_require_pairing = true;
    app.effective_runtime_max_tool_rounds = 4;

    const service_changed = if (install_service) app.service_manager.install() else false;
    trace.finish(null);
    return std.fmt.allocPrint(ctx.allocator, "{{\"applied\":{s},\"changedCount\":{d},\"requiresRestart\":{s},\"installService\":{s},\"serviceChanged\":{s},\"gatewayRequirePairing\":{s},\"runtimeMaxToolRounds\":{d}}}", .{
        if (attempt.applied()) "true" else "false",
        if (attempt.stats) |stats| stats.changed_count else 0,
        if (attempt.requiresRestart()) "true" else "false",
        if (install_service) "true" else "false",
        if (service_changed) "true" else "false",
        if (app.effective_gateway_require_pairing) "true" else "false",
        app.effective_runtime_max_tool_rounds,
    });
}
