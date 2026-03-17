const std = @import("std");
const framework = @import("framework");
const registry = @import("../config/field_registry.zig");
const runtime_app = @import("../runtime/app_context.zig");
const services_model = @import("../domain/services.zig");

pub const RemediationAction = enum {
    enable_pairing,
    generate_gateway_token,
    install_service,
    activate_tunnel,
    deactivate_tunnel,

    pub fn parse(raw: []const u8) anyerror!RemediationAction {
        return std.meta.stringToEnum(RemediationAction, raw) orelse error.UnknownRemediationAction;
    }
};

pub const RemediationPreview = struct {
    action: RemediationAction,
    would_change: bool,
    requires_restart: bool,
    summary: []const u8,
};

pub fn preview(services: *services_model.CommandServices, action: RemediationAction) RemediationPreview {
    const app: *runtime_app.AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    return switch (action) {
        .enable_pairing => .{
            .action = action,
            .would_change = !app.effective_gateway_require_pairing,
            .requires_restart = false,
            .summary = if (!app.effective_gateway_require_pairing) "would enable gateway pairing protection" else "gateway pairing protection already enabled",
        },
        .generate_gateway_token => .{
            .action = action,
            .would_change = services.secret_store.get("gateway:shared_token") == null,
            .requires_restart = false,
            .summary = if (services.secret_store.get("gateway:shared_token") == null) "would generate a shared gateway token" else "shared gateway token already configured",
        },
        .install_service => .{
            .action = action,
            .would_change = !app.service_manager.status().installed,
            .requires_restart = false,
            .summary = if (!app.service_manager.status().installed) "would install the service manager" else "service manager already installed",
        },
        .activate_tunnel => .{
            .action = action,
            .would_change = !services.tunnel_runtime.active,
            .requires_restart = false,
            .summary = if (!services.tunnel_runtime.active) "would activate remote tunnel with default mock endpoint" else "remote tunnel already active",
        },
        .deactivate_tunnel => .{
            .action = action,
            .would_change = services.tunnel_runtime.active,
            .requires_restart = false,
            .summary = if (services.tunnel_runtime.active) "would deactivate remote tunnel" else "remote tunnel already inactive",
        },
    };
}

pub fn apply(ctx: *const framework.CommandContext, services: *services_model.CommandServices, action: RemediationAction) anyerror![]const u8 {
    const app: *runtime_app.AppContext = @ptrCast(@alignCast(services.app_context_ptr.?));
    var trace = try framework.StepTrace.begin(ctx.allocator, app.framework_context.logger, "diagnostics/remediate", @tagName(action), 1000);
    defer trace.deinit();

    return switch (action) {
        .enable_pairing => blk: {
            const field = registry.ConfigFieldRegistry.find("gateway.require_pairing") orelse return error.ConfigFieldUnknown;
            const updates = [_]framework.ValidationField{.{ .key = "gateway.require_pairing", .value = .{ .boolean = true } }};
            const write_fields = [_]framework.FieldDefinition{field.field_definition};
            var pipeline = app.makeConfigPipeline(write_fields[0..], registry.ConfigFieldRegistry.configRules());
            var attempt = try pipeline.applyWrite(updates[0..], false);
            defer attempt.deinit();
            if (!attempt.report.isOk()) {
                trace.finish("ValidationFailed");
                return error.ValidationFailed;
            }
            app.effective_gateway_require_pairing = true;
            trace.finish(null);
            break :blk std.fmt.allocPrint(ctx.allocator, "{{\"action\":\"enable_pairing\",\"applied\":{s},\"changed\":{d},\"gatewayRequirePairing\":true}}", .{ if (attempt.applied()) "true" else "false", if (attempt.stats) |stats| stats.changed_count else 0 });
        },
        .generate_gateway_token => blk: {
            var bytes: [16]u8 = undefined;
            std.crypto.random.bytes(&bytes);
            var token_buf: [32]u8 = undefined;
            encodeHexLower(&token_buf, &bytes);
            try services.secret_store.put("gateway:shared_token", token_buf[0..]);
            trace.finish(null);
            break :blk std.fmt.allocPrint(ctx.allocator, "{{\"action\":\"generate_gateway_token\",\"applied\":true,\"token\":\"{s}\"}}", .{token_buf});
        },
        .install_service => blk: {
            const changed = app.service_manager.install();
            trace.finish(null);
            break :blk std.fmt.allocPrint(ctx.allocator, "{{\"action\":\"install_service\",\"applied\":true,\"changed\":{s},\"installed\":{s}}}", .{ if (changed) "true" else "false", if (app.service_manager.status().installed) "true" else "false" });
        },
        .activate_tunnel => blk: {
            services.tunnel_runtime.activate(.custom, "mock://tunnel/healthy") catch |err| {
                try services.tunnel_runtime.noteActivationFailure("mock://tunnel/healthy", err);
                trace.finish(@errorName(err));
                break :blk std.fmt.allocPrint(ctx.allocator, "{{\"action\":\"activate_tunnel\",\"applied\":false,\"errorCode\":\"{s}\"}}", .{@errorName(err)});
            };
            trace.finish(null);
            break :blk std.fmt.allocPrint(ctx.allocator, "{{\"action\":\"activate_tunnel\",\"applied\":true,\"active\":true,\"endpoint\":\"{s}\"}}", .{services.tunnel_runtime.endpoint});
        },
        .deactivate_tunnel => blk: {
            services.tunnel_runtime.deactivate();
            trace.finish(null);
            break :blk std.fmt.allocPrint(ctx.allocator, "{{\"action\":\"deactivate_tunnel\",\"applied\":true,\"active\":false}}", .{});
        },
    };
}

fn encodeHexLower(out: *[32]u8, bytes: *const [16]u8) void {
    const alphabet = "0123456789abcdef";
    for (bytes.*, 0..) |byte, index| {
        out[index * 2] = alphabet[byte >> 4];
        out[index * 2 + 1] = alphabet[byte & 0x0f];
    }
}
