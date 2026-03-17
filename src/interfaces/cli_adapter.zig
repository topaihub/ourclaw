const std = @import("std");
const framework = @import("framework");
const runtime = @import("../runtime/app_context.zig");
const stream_sink = @import("stream_sink.zig");
const stream_projection = @import("stream_projection.zig");

pub const OwnedRequest = struct {
    request: framework.CommandRequest,
    params: []framework.ValidationField,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *OwnedRequest) void {
        if (self.params.len == 0) {
            return;
        }
        for (self.params) |field| {
            switch (field.value) {
                .string => |value| self.allocator.free(value),
                else => {},
            }
        }
        self.allocator.free(self.params);
    }
};

pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) anyerror!OwnedRequest {
    if (args.len == 0) return error.MissingCommand;

    if (std.mem.eql(u8, args[0], "app.meta")) {
        const params = try allocator.alloc(framework.ValidationField, 0);
        return .{
            .request = .{ .request_id = "cli_req_app_meta", .method = "app.meta", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "status") or std.mem.eql(u8, args[0], "status.all")) {
        const params = try allocator.alloc(framework.ValidationField, 0);
        return .{
            .request = .{ .request_id = "cli_req_status_all", .method = "status.all", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "agent.run")) {
        if (args.len < 3) return error.MissingAgentPrompt;
        var with_tool: ?[]const u8 = null;
        var with_tool_input: ?[]const u8 = null;
        var with_provider: ?[]const u8 = null;
        var with_prompt_profile: ?[]const u8 = null;
        var with_response_mode: ?[]const u8 = null;
        var with_max_tool_rounds: ?i64 = null;
        var with_allow_provider_tools: ?bool = null;
        var index: usize = 3;
        while (index < args.len) : (index += 1) {
            if (std.mem.eql(u8, args[index], "--provider")) {
                index += 1;
                if (index >= args.len) return error.MissingProviderId;
                with_provider = args[index];
                continue;
            }
            if (std.mem.eql(u8, args[index], "--tool")) {
                index += 1;
                if (index >= args.len) return error.MissingToolId;
                with_tool = args[index];
                continue;
            }
            if (std.mem.eql(u8, args[index], "--tool-input")) {
                index += 1;
                if (index >= args.len) return error.MissingToolInput;
                with_tool_input = args[index];
                continue;
            }
            if (std.mem.eql(u8, args[index], "--prompt-profile")) {
                index += 1;
                if (index >= args.len) return error.MissingPromptProfile;
                with_prompt_profile = args[index];
                continue;
            }
            if (std.mem.eql(u8, args[index], "--response-mode")) {
                index += 1;
                if (index >= args.len) return error.MissingResponseMode;
                with_response_mode = args[index];
                continue;
            }
            if (std.mem.eql(u8, args[index], "--max-tool-rounds")) {
                index += 1;
                if (index >= args.len) return error.MissingMaxToolRounds;
                with_max_tool_rounds = try std.fmt.parseInt(i64, args[index], 10);
                continue;
            }
            if (std.mem.eql(u8, args[index], "--no-provider-tools")) {
                with_allow_provider_tools = false;
                continue;
            }
        }

        const count: usize = 2 + @as(usize, if (with_provider != null) 1 else 0) + @as(usize, if (with_tool != null) 1 else 0) + @as(usize, if (with_tool_input != null) 1 else 0) + @as(usize, if (with_prompt_profile != null) 1 else 0) + @as(usize, if (with_response_mode != null) 1 else 0) + @as(usize, if (with_max_tool_rounds != null) 1 else 0) + @as(usize, if (with_allow_provider_tools != null) 1 else 0);
        const params = try allocator.alloc(framework.ValidationField, count);
        var param_index: usize = 0;
        params[param_index] = .{ .key = "session_id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        param_index += 1;
        params[param_index] = .{ .key = "prompt", .value = .{ .string = try allocator.dupe(u8, args[2]) } };
        param_index += 1;
        if (with_provider) |provider_id| {
            params[param_index] = .{ .key = "provider_id", .value = .{ .string = try allocator.dupe(u8, provider_id) } };
            param_index += 1;
        }
        if (with_tool) |tool_id| {
            params[param_index] = .{ .key = "tool_id", .value = .{ .string = try allocator.dupe(u8, tool_id) } };
            param_index += 1;
        }
        if (with_tool_input) |tool_input| {
            params[param_index] = .{ .key = "tool_input_json", .value = .{ .string = try allocator.dupe(u8, tool_input) } };
            param_index += 1;
        }
        if (with_prompt_profile) |prompt_profile| {
            params[param_index] = .{ .key = "prompt_profile", .value = .{ .string = try allocator.dupe(u8, prompt_profile) } };
            param_index += 1;
        }
        if (with_response_mode) |response_mode| {
            params[param_index] = .{ .key = "response_mode", .value = .{ .string = try allocator.dupe(u8, response_mode) } };
            param_index += 1;
        }
        if (with_max_tool_rounds) |max_tool_rounds| {
            params[param_index] = .{ .key = "max_tool_rounds", .value = .{ .integer = max_tool_rounds } };
            param_index += 1;
        }
        if (with_allow_provider_tools) |allow_provider_tools| {
            params[param_index] = .{ .key = "allow_provider_tools", .value = .{ .boolean = allow_provider_tools } };
        }

        return .{
            .request = .{ .request_id = "cli_req_agent_run", .method = "agent.run", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "agent.stream")) {
        if (args.len < 3) return error.MissingAgentPrompt;
        var with_tool: ?[]const u8 = null;
        var with_tool_input: ?[]const u8 = null;
        var with_provider: ?[]const u8 = null;
        var with_last_event_id: ?[]const u8 = null;
        var with_prompt_profile: ?[]const u8 = null;
        var with_response_mode: ?[]const u8 = null;
        var with_max_tool_rounds: ?i64 = null;
        var with_allow_provider_tools: ?bool = null;
        var with_limit: ?i64 = null;
        var index: usize = 3;
        while (index < args.len) : (index += 1) {
            if (std.mem.eql(u8, args[index], "--provider")) {
                index += 1;
                if (index >= args.len) return error.MissingProviderId;
                with_provider = args[index];
                continue;
            }
            if (std.mem.eql(u8, args[index], "--limit")) {
                index += 1;
                if (index >= args.len) return error.MissingLogLevel;
                with_limit = try std.fmt.parseInt(i64, args[index], 10);
                continue;
            }
            if (std.mem.eql(u8, args[index], "--last-event-id")) {
                index += 1;
                if (index >= args.len) return error.MissingLastEventId;
                with_last_event_id = args[index];
                continue;
            }
            if (std.mem.eql(u8, args[index], "--prompt-profile")) {
                index += 1;
                if (index >= args.len) return error.MissingPromptProfile;
                with_prompt_profile = args[index];
                continue;
            }
            if (std.mem.eql(u8, args[index], "--response-mode")) {
                index += 1;
                if (index >= args.len) return error.MissingResponseMode;
                with_response_mode = args[index];
                continue;
            }
            if (std.mem.eql(u8, args[index], "--max-tool-rounds")) {
                index += 1;
                if (index >= args.len) return error.MissingMaxToolRounds;
                with_max_tool_rounds = try std.fmt.parseInt(i64, args[index], 10);
                continue;
            }
            if (std.mem.eql(u8, args[index], "--no-provider-tools")) {
                with_allow_provider_tools = false;
                continue;
            }
            if (std.mem.eql(u8, args[index], "--tool")) {
                index += 1;
                if (index >= args.len) return error.MissingToolId;
                with_tool = args[index];
                continue;
            }
            if (std.mem.eql(u8, args[index], "--tool-input")) {
                index += 1;
                if (index >= args.len) return error.MissingToolInput;
                with_tool_input = args[index];
                continue;
            }
        }

        const count: usize = 2 + @as(usize, if (with_provider != null) 1 else 0) + @as(usize, if (with_tool != null) 1 else 0) + @as(usize, if (with_tool_input != null) 1 else 0) + @as(usize, if (with_limit != null) 1 else 0) + @as(usize, if (with_last_event_id != null) 1 else 0) + @as(usize, if (with_prompt_profile != null) 1 else 0) + @as(usize, if (with_response_mode != null) 1 else 0) + @as(usize, if (with_max_tool_rounds != null) 1 else 0) + @as(usize, if (with_allow_provider_tools != null) 1 else 0);
        const params = try allocator.alloc(framework.ValidationField, count);
        var param_index: usize = 0;
        params[param_index] = .{ .key = "session_id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        param_index += 1;
        params[param_index] = .{ .key = "prompt", .value = .{ .string = try allocator.dupe(u8, args[2]) } };
        param_index += 1;
        if (with_provider) |provider_id| {
            params[param_index] = .{ .key = "provider_id", .value = .{ .string = try allocator.dupe(u8, provider_id) } };
            param_index += 1;
        }
        if (with_tool) |tool_id| {
            params[param_index] = .{ .key = "tool_id", .value = .{ .string = try allocator.dupe(u8, tool_id) } };
            param_index += 1;
        }
        if (with_tool_input) |tool_input| {
            params[param_index] = .{ .key = "tool_input_json", .value = .{ .string = try allocator.dupe(u8, tool_input) } };
            param_index += 1;
        }
        if (with_limit) |limit| {
            params[param_index] = .{ .key = "limit", .value = .{ .integer = limit } };
            param_index += 1;
        }
        if (with_last_event_id) |last_event_id| {
            params[param_index] = .{ .key = "last_event_id", .value = .{ .string = try allocator.dupe(u8, last_event_id) } };
            param_index += 1;
        }
        if (with_prompt_profile) |prompt_profile| {
            params[param_index] = .{ .key = "prompt_profile", .value = .{ .string = try allocator.dupe(u8, prompt_profile) } };
            param_index += 1;
        }
        if (with_response_mode) |response_mode| {
            params[param_index] = .{ .key = "response_mode", .value = .{ .string = try allocator.dupe(u8, response_mode) } };
            param_index += 1;
        }
        if (with_max_tool_rounds) |max_tool_rounds| {
            params[param_index] = .{ .key = "max_tool_rounds", .value = .{ .integer = max_tool_rounds } };
            param_index += 1;
        }
        if (with_allow_provider_tools) |allow_provider_tools| {
            params[param_index] = .{ .key = "allow_provider_tools", .value = .{ .boolean = allow_provider_tools } };
        }

        return .{
            .request = .{ .request_id = "cli_req_agent_stream", .method = "agent.stream", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "config.get")) {
        if (args.len < 2) return error.MissingConfigPath;
        const params = try allocator.alloc(framework.ValidationField, 1);
        if (args.len == 2) {
            params[0] = .{ .key = "path", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        } else {
            const joined = try std.mem.join(allocator, ",", args[1..]);
            params[0] = .{ .key = "paths", .value = .{ .string = joined } };
        }
        return .{
            .request = .{ .request_id = "cli_req_config_get", .method = "config.get", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "config.set")) {
        if (args.len < 3) return error.MissingConfigValue;
        var with_confirm = false;
        var with_preview = false;
        var index: usize = 3;
        while (index < args.len) : (index += 1) {
            if (std.mem.eql(u8, args[index], "--confirm-risk")) with_confirm = true;
            if (std.mem.eql(u8, args[index], "--preview")) with_preview = true;
        }

        const count: usize = 2 + @as(usize, if (with_confirm) 1 else 0) + @as(usize, if (with_preview) 1 else 0);
        const params = try allocator.alloc(framework.ValidationField, count);
        params[0] = .{ .key = "path", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        params[1] = .{ .key = "value", .value = .{ .string = try allocator.dupe(u8, args[2]) } };
        var param_index: usize = 2;
        if (with_confirm) {
            params[param_index] = .{ .key = "confirm_risk", .value = .{ .boolean = true } };
            param_index += 1;
        }
        if (with_preview) {
            params[param_index] = .{ .key = "preview", .value = .{ .boolean = true } };
        }
        return .{
            .request = .{ .request_id = "cli_req_config_set", .method = "config.set", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "config.migrate_preview")) {
        if (args.len < 2) return error.MissingConfigJson;
        const params = try allocator.alloc(framework.ValidationField, 1);
        params[0] = .{ .key = "config_json", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        return .{
            .request = .{ .request_id = "cli_req_config_migrate_preview", .method = "config.migrate_preview", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "config.migrate_apply")) {
        if (args.len < 2) return error.MissingConfigJson;
        const count: usize = if (args.len >= 3 and std.mem.eql(u8, args[2], "--confirm-risk")) 2 else 1;
        const params = try allocator.alloc(framework.ValidationField, count);
        params[0] = .{ .key = "config_json", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        if (count == 2) {
            params[1] = .{ .key = "confirm_risk", .value = .{ .boolean = true } };
        }
        return .{
            .request = .{ .request_id = "cli_req_config_migrate_apply", .method = "config.migrate_apply", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "config.compat_import")) {
        if (args.len < 2) return error.MissingConfigJson;
        var list: std.ArrayListUnmanaged(framework.ValidationField) = .empty;
        defer list.deinit(allocator);
        try list.append(allocator, .{ .key = "source_json", .value = .{ .string = try allocator.dupe(u8, args[1]) } });
        var index: usize = 2;
        while (index < args.len) : (index += 1) {
            if (std.mem.eql(u8, args[index], "--source-kind")) {
                index += 1;
                if (index >= args.len) return error.MissingSourceKind;
                try list.append(allocator, .{ .key = "source_kind", .value = .{ .string = try allocator.dupe(u8, args[index]) } });
                continue;
            }
            if (std.mem.eql(u8, args[index], "--preview")) {
                try list.append(allocator, .{ .key = "preview", .value = .{ .boolean = true } });
                continue;
            }
            if (std.mem.eql(u8, args[index], "--confirm-risk")) {
                try list.append(allocator, .{ .key = "confirm_risk", .value = .{ .boolean = true } });
                continue;
            }
        }
        const params = try allocator.dupe(framework.ValidationField, list.items);
        return .{
            .request = .{ .request_id = "cli_req_config_compat_import", .method = "config.compat_import", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "logs.recent")) {
        var list: std.ArrayListUnmanaged(framework.ValidationField) = .empty;
        defer list.deinit(allocator);

        var index: usize = 1;
        while (index < args.len) : (index += 1) {
            const arg = args[index];
            if (std.mem.eql(u8, arg, "--level")) {
                index += 1;
                if (index >= args.len) return error.MissingLogLevel;
                try list.append(allocator, .{ .key = "level", .value = .{ .string = try allocator.dupe(u8, args[index]) } });
                continue;
            }
            if (std.mem.eql(u8, arg, "--subsystem")) {
                index += 1;
                if (index >= args.len) return error.MissingSubsystemFilter;
                try list.append(allocator, .{ .key = "subsystem", .value = .{ .string = try allocator.dupe(u8, args[index]) } });
                continue;
            }
            if (std.mem.eql(u8, arg, "--trace-id")) {
                index += 1;
                if (index >= args.len) return error.MissingTraceFilter;
                try list.append(allocator, .{ .key = "trace_id", .value = .{ .string = try allocator.dupe(u8, args[index]) } });
                continue;
            }

            try list.append(allocator, .{ .key = "limit", .value = .{ .integer = try std.fmt.parseInt(i64, arg, 10) } });
        }

        const params = try allocator.dupe(framework.ValidationField, list.items);
        return .{
            .request = .{ .request_id = "cli_req_logs_recent", .method = "logs.recent", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "task.get")) {
        if (args.len < 2) return error.MissingTaskId;
        const params = try allocator.alloc(framework.ValidationField, 1);
        params[0] = .{ .key = "task_id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        return .{
            .request = .{ .request_id = "cli_req_task_get", .method = "task.get", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "task.by_request")) {
        if (args.len < 2) return error.MissingRequestId;
        const params = try allocator.alloc(framework.ValidationField, 1);
        params[0] = .{ .key = "request_id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        return .{
            .request = .{ .request_id = "cli_req_task_by_request", .method = "task.by_request", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "diagnostics.summary")) {
        const params = try allocator.alloc(framework.ValidationField, 0);
        return .{
            .request = .{ .request_id = "cli_req_diagnostics_summary", .method = "diagnostics.summary", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "onboard") or std.mem.eql(u8, args[0], "onboard.summary")) {
        const params = try allocator.alloc(framework.ValidationField, 0);
        return .{
            .request = .{ .request_id = "cli_req_onboard_summary", .method = "onboard.summary", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "onboard.apply-defaults")) {
        var install_service = false;
        if (args.len >= 2 and std.mem.eql(u8, args[1], "--install-service")) install_service = true;
        const count: usize = if (install_service) 1 else 0;
        const params = try allocator.alloc(framework.ValidationField, count);
        if (install_service) {
            params[0] = .{ .key = "install_service", .value = .{ .boolean = true } };
        }
        return .{
            .request = .{ .request_id = "cli_req_onboard_apply_defaults", .method = "onboard.apply_defaults", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "diagnostics.doctor")) {
        const params = try allocator.alloc(framework.ValidationField, 0);
        return .{
            .request = .{ .request_id = "cli_req_diagnostics_doctor", .method = "diagnostics.doctor", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "device.pair.list")) {
        const params = try allocator.alloc(framework.ValidationField, 0);
        return .{
            .request = .{ .request_id = "cli_req_device_pair_list", .method = "device.pair.list", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "device.pair.approve")) {
        if (args.len < 2) return error.MissingPairingId;
        const params = try allocator.alloc(framework.ValidationField, 1);
        params[0] = .{ .key = "id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        return .{
            .request = .{ .request_id = "cli_req_device_pair_approve", .method = "device.pair.approve", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "device.pair.reject")) {
        if (args.len < 2) return error.MissingPairingId;
        const params = try allocator.alloc(framework.ValidationField, 1);
        params[0] = .{ .key = "id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        return .{
            .request = .{ .request_id = "cli_req_device_pair_reject", .method = "device.pair.reject", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "device.token.rotate") or std.mem.eql(u8, args[0], "device.token.revoke")) {
        if (args.len < 2) return error.MissingPairingId;
        const params = try allocator.alloc(framework.ValidationField, 1);
        params[0] = .{ .key = "id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        return .{
            .request = .{ .request_id = "cli_req_device_token", .method = args[0], .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "node.describe")) {
        if (args.len < 2) return error.MissingNodeId;
        const params = try allocator.alloc(framework.ValidationField, 1);
        params[0] = .{ .key = "id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        return .{
            .request = .{ .request_id = "cli_req_node_describe", .method = "node.describe", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "metrics.summary") or std.mem.eql(u8, args[0], "gateway.status") or std.mem.eql(u8, args[0], "gateway.auth.status") or std.mem.eql(u8, args[0], "gateway.token.generate") or std.mem.eql(u8, args[0], "gateway.access.link") or std.mem.eql(u8, args[0], "service.status") or std.mem.eql(u8, args[0], "skills.list") or std.mem.eql(u8, args[0], "cron.list") or std.mem.eql(u8, args[0], "heartbeat.status") or std.mem.eql(u8, args[0], "tunnel.status") or std.mem.eql(u8, args[0], "mcp.list") or std.mem.eql(u8, args[0], "hardware.list") or std.mem.eql(u8, args[0], "voice.status") or std.mem.eql(u8, args[0], "node.list") or std.mem.eql(u8, args[0], "devices.list")) {
        const params = try allocator.alloc(framework.ValidationField, 0);
        return .{
            .request = .{ .request_id = "cli_req_simple_query", .method = args[0], .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "gateway.start") or std.mem.eql(u8, args[0], "gateway.stop") or std.mem.eql(u8, args[0], "gateway.stream_subscribe") or std.mem.eql(u8, args[0], "service.install") or std.mem.eql(u8, args[0], "service.start") or std.mem.eql(u8, args[0], "service.stop") or std.mem.eql(u8, args[0], "service.restart") or std.mem.eql(u8, args[0], "cron.tick") or std.mem.eql(u8, args[0], "tunnel.deactivate")) {
        const params = try allocator.alloc(framework.ValidationField, 0);
        return .{
            .request = .{ .request_id = "cli_req_simple_admin", .method = args[0], .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "observer.recent")) {
        var with_limit: ?i64 = null;
        var with_execution_id: ?[]const u8 = null;
        var with_session_id: ?[]const u8 = null;
        var index: usize = 1;
        if (args.len >= 2 and !std.mem.startsWith(u8, args[1], "--")) {
            with_limit = try std.fmt.parseInt(i64, args[1], 10);
            index = 2;
        }
        while (index < args.len) : (index += 1) {
            if (std.mem.eql(u8, args[index], "--execution-id")) {
                index += 1;
                if (index >= args.len) return error.MissingExecutionId;
                with_execution_id = args[index];
                continue;
            }
            if (std.mem.eql(u8, args[index], "--session-id")) {
                index += 1;
                if (index >= args.len) return error.MissingSessionId;
                with_session_id = args[index];
                continue;
            }
        }

        const count: usize = @as(usize, if (with_limit != null) 1 else 0) + @as(usize, if (with_execution_id != null) 1 else 0) + @as(usize, if (with_session_id != null) 1 else 0);
        const params = try allocator.alloc(framework.ValidationField, count);
        var param_index: usize = 0;
        if (with_limit) |limit| {
            params[param_index] = .{ .key = "limit", .value = .{ .integer = limit } };
            param_index += 1;
        }
        if (with_execution_id) |execution_id| {
            params[param_index] = .{ .key = "execution_id", .value = .{ .string = try allocator.dupe(u8, execution_id) } };
            param_index += 1;
        }
        if (with_session_id) |session_id| {
            params[param_index] = .{ .key = "session_id", .value = .{ .string = try allocator.dupe(u8, session_id) } };
        }
        return .{
            .request = .{ .request_id = "cli_req_observer_recent", .method = "observer.recent", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "memory.summary")) {
        if (args.len < 2) return error.MissingSessionId;
        var with_max_items: ?i64 = if (args.len >= 3 and !std.mem.startsWith(u8, args[2], "--")) try std.fmt.parseInt(i64, args[2], 10) else null;
        var index: usize = if (with_max_items != null) 3 else 2;
        while (index < args.len) : (index += 1) {
            if (std.mem.eql(u8, args[index], "--max-items")) {
                index += 1;
                if (index >= args.len) return error.MissingMaxItems;
                with_max_items = try std.fmt.parseInt(i64, args[index], 10);
                continue;
            }
        }

        const count: usize = 1 + @as(usize, if (with_max_items != null) 1 else 0);
        const params = try allocator.alloc(framework.ValidationField, count);
        params[0] = .{ .key = "session_id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        if (with_max_items) |max_items| {
            params[1] = .{ .key = "max_items", .value = .{ .integer = max_items } };
        }
        return .{
            .request = .{ .request_id = "cli_req_memory_summary", .method = "memory.summary", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "memory.snapshot_export")) {
        const params = try allocator.alloc(framework.ValidationField, 0);
        return .{
            .request = .{ .request_id = "cli_req_memory_snapshot_export", .method = "memory.snapshot_export", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "session.get")) {
        if (args.len < 2) return error.MissingSessionId;
        var with_summary_items: ?i64 = if (args.len >= 3 and !std.mem.startsWith(u8, args[2], "--")) try std.fmt.parseInt(i64, args[2], 10) else null;
        var with_recent_turns_limit: ?i64 = null;
        var index: usize = if (with_summary_items != null) 3 else 2;
        while (index < args.len) : (index += 1) {
            if (std.mem.eql(u8, args[index], "--summary-items")) {
                index += 1;
                if (index >= args.len) return error.MissingSummaryItems;
                with_summary_items = try std.fmt.parseInt(i64, args[index], 10);
                continue;
            }
            if (std.mem.eql(u8, args[index], "--recent-turns-limit")) {
                index += 1;
                if (index >= args.len) return error.MissingRecentTurnsLimit;
                with_recent_turns_limit = try std.fmt.parseInt(i64, args[index], 10);
                continue;
            }
        }

        const count: usize = 1 + @as(usize, if (with_summary_items != null) 1 else 0) + @as(usize, if (with_recent_turns_limit != null) 1 else 0);
        const params = try allocator.alloc(framework.ValidationField, count);
        params[0] = .{ .key = "session_id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        var param_index: usize = 1;
        if (with_summary_items) |summary_items| {
            params[param_index] = .{ .key = "summary_items", .value = .{ .integer = summary_items } };
            param_index += 1;
        }
        if (with_recent_turns_limit) |recent_turns_limit| {
            params[param_index] = .{ .key = "recent_turns_limit", .value = .{ .integer = recent_turns_limit } };
        }
        return .{
            .request = .{ .request_id = "cli_req_session_get", .method = "session.get", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "session.compact")) {
        if (args.len < 2) return error.MissingSessionId;
        const count: usize = if (args.len >= 3) 2 else 1;
        const params = try allocator.alloc(framework.ValidationField, count);
        params[0] = .{ .key = "session_id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        if (args.len >= 3) {
            params[1] = .{ .key = "keep_last", .value = .{ .integer = try std.fmt.parseInt(i64, args[2], 10) } };
        }
        return .{
            .request = .{ .request_id = "cli_req_session_compact", .method = "session.compact", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "memory.retrieve")) {
        if (args.len < 3) return error.MissingQuery;
        const count: usize = if (args.len >= 4) 3 else 2;
        const params = try allocator.alloc(framework.ValidationField, count);
        params[0] = .{ .key = "session_id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        params[1] = .{ .key = "query", .value = .{ .string = try allocator.dupe(u8, args[2]) } };
        if (args.len >= 4) {
            params[2] = .{ .key = "limit", .value = .{ .integer = try std.fmt.parseInt(i64, args[3], 10) } };
        }
        return .{
            .request = .{ .request_id = "cli_req_memory_retrieve", .method = "memory.retrieve", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "memory.migrate_preview")) {
        if (args.len < 2) return error.MissingSnapshotJson;
        const params = try allocator.alloc(framework.ValidationField, 1);
        params[0] = .{ .key = "snapshot_json", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        return .{
            .request = .{ .request_id = "cli_req_memory_migrate_preview", .method = "memory.migrate_preview", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "memory.migrate_apply")) {
        if (args.len < 2) return error.MissingSnapshotJson;
        const params = try allocator.alloc(framework.ValidationField, 1);
        params[0] = .{ .key = "snapshot_json", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        return .{
            .request = .{ .request_id = "cli_req_memory_migrate_apply", .method = "memory.migrate_apply", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "events.subscribe")) {
        var with_topic_prefix: ?[]const u8 = null;
        var with_after_seq: ?i64 = null;
        var index: usize = 1;
        if (args.len >= 2 and !std.mem.startsWith(u8, args[1], "--")) {
            with_topic_prefix = args[1];
            index = 2;
        }
        while (index < args.len) : (index += 1) {
            if (std.mem.eql(u8, args[index], "--after-seq")) {
                index += 1;
                if (index >= args.len) return error.MissingAfterSeq;
                with_after_seq = try std.fmt.parseInt(i64, args[index], 10);
                continue;
            }
        }

        const count: usize = @as(usize, if (with_topic_prefix != null) 1 else 0) + @as(usize, if (with_after_seq != null) 1 else 0);
        const params = try allocator.alloc(framework.ValidationField, count);
        var param_index: usize = 0;
        if (with_topic_prefix) |topic_prefix| {
            params[param_index] = .{ .key = "topic_prefix", .value = .{ .string = try allocator.dupe(u8, topic_prefix) } };
            param_index += 1;
        }
        if (with_after_seq) |after_seq| {
            params[param_index] = .{ .key = "after_seq", .value = .{ .integer = after_seq } };
        }
        return .{
            .request = .{ .request_id = "cli_req_events_subscribe", .method = "events.subscribe", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "skills.install")) {
        if (args.len < 2) return error.MissingSkillId;
        const params = try allocator.alloc(framework.ValidationField, 1);
        params[0] = .{ .key = "skill_id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        return .{
            .request = .{ .request_id = "cli_req_skills_install", .method = "skills.install", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "skills.run")) {
        if (args.len < 2) return error.MissingSkillId;
        const params = try allocator.alloc(framework.ValidationField, 1);
        params[0] = .{ .key = "skill_id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        return .{
            .request = .{ .request_id = "cli_req_skills_run", .method = "skills.run", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "cron.register")) {
        if (args.len < 4) return error.MissingCommand;
        const params = try allocator.alloc(framework.ValidationField, 3);
        params[0] = .{ .key = "id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        params[1] = .{ .key = "schedule", .value = .{ .string = try allocator.dupe(u8, args[2]) } };
        params[2] = .{ .key = "command", .value = .{ .string = try allocator.dupe(u8, args[3]) } };
        return .{
            .request = .{ .request_id = "cli_req_cron_register", .method = "cron.register", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "tunnel.activate")) {
        if (args.len < 3) return error.MissingCommand;
        const params = try allocator.alloc(framework.ValidationField, 2);
        params[0] = .{ .key = "kind", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        params[1] = .{ .key = "endpoint", .value = .{ .string = try allocator.dupe(u8, args[2]) } };
        return .{
            .request = .{ .request_id = "cli_req_tunnel_activate", .method = "tunnel.activate", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "mcp.register")) {
        if (args.len < 3) return error.MissingCommand;
        const params = try allocator.alloc(framework.ValidationField, 2);
        params[0] = .{ .key = "id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        params[1] = .{ .key = "transport", .value = .{ .string = try allocator.dupe(u8, args[2]) } };
        return .{
            .request = .{ .request_id = "cli_req_mcp_register", .method = "mcp.register", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "hardware.register") or std.mem.eql(u8, args[0], "peripheral.register")) {
        if (args.len < 3) return error.MissingCommand;
        const params = try allocator.alloc(framework.ValidationField, 2);
        params[0] = .{ .key = "id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        params[1] = .{ .key = if (std.mem.eql(u8, args[0], "hardware.register")) "label" else "kind", .value = .{ .string = try allocator.dupe(u8, args[2]) } };
        return .{
            .request = .{ .request_id = "cli_req_registry_register", .method = args[0], .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "voice.attach")) {
        if (args.len < 2) return error.MissingCommand;
        const params = try allocator.alloc(framework.ValidationField, 1);
        params[0] = .{ .key = "peripheral_id", .value = .{ .string = try allocator.dupe(u8, args[1]) } };
        return .{
            .request = .{ .request_id = "cli_req_voice_attach", .method = "voice.attach", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "voice.detach")) {
        return .{
            .request = .{ .request_id = "cli_req_voice_detach", .method = "voice.detach", .params = &.{}, .source = .cli, .authority = .admin },
            .params = &.{},
            .allocator = allocator,
        };
    }

    if (std.mem.eql(u8, args[0], "events.poll")) {
        if (args.len < 2) return error.MissingSubscriptionId;
        const with_limit: ?i64 = if (args.len >= 3 and !std.mem.startsWith(u8, args[2], "--")) try std.fmt.parseInt(i64, args[2], 10) else null;
        var with_execution_id: ?[]const u8 = null;
        var with_session_id: ?[]const u8 = null;
        var index: usize = if (with_limit != null) 3 else 2;
        while (index < args.len) : (index += 1) {
            if (std.mem.eql(u8, args[index], "--execution-id")) {
                index += 1;
                if (index >= args.len) return error.MissingExecutionId;
                with_execution_id = args[index];
                continue;
            }
            if (std.mem.eql(u8, args[index], "--session-id")) {
                index += 1;
                if (index >= args.len) return error.MissingSessionId;
                with_session_id = args[index];
                continue;
            }
        }

        const count: usize = 1 + @as(usize, if (with_limit != null) 1 else 0) + @as(usize, if (with_execution_id != null) 1 else 0) + @as(usize, if (with_session_id != null) 1 else 0);
        const params = try allocator.alloc(framework.ValidationField, count);
        params[0] = .{ .key = "subscription_id", .value = .{ .integer = try std.fmt.parseInt(i64, args[1], 10) } };
        var param_index: usize = 1;
        if (with_limit) |limit| {
            params[param_index] = .{ .key = "limit", .value = .{ .integer = limit } };
            param_index += 1;
        }
        if (with_execution_id) |execution_id| {
            params[param_index] = .{ .key = "execution_id", .value = .{ .string = try allocator.dupe(u8, execution_id) } };
            param_index += 1;
        }
        if (with_session_id) |session_id| {
            params[param_index] = .{ .key = "session_id", .value = .{ .string = try allocator.dupe(u8, session_id) } };
        }
        return .{
            .request = .{ .request_id = "cli_req_events_poll", .method = "events.poll", .params = params, .source = .cli, .authority = .admin },
            .params = params,
            .allocator = allocator,
        };
    }

    return error.UnknownCliCommand;
}

pub fn dispatchAndRenderJson(allocator: std.mem.Allocator, app: *runtime.AppContext, args: []const []const u8) anyerror![]u8 {
    var owned = try parseArgs(allocator, args);
    defer owned.deinit();

    try app.channel_registry.recordCliRequest(owned.request.method, extractStringParam(owned.params, "session_id"));

    var dispatcher = app.makeDispatcher();
    const envelope = try dispatcher.dispatch(owned.request, false);
    return renderProtocolEnvelopeJson(allocator, envelope);
}

pub fn shouldStreamLive(args: []const []const u8) bool {
    if (args.len == 0 or !std.mem.eql(u8, args[0], "agent.stream")) return false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--live")) return true;
    }
    return false;
}

pub fn streamLive(allocator: std.mem.Allocator, app: *runtime.AppContext, args: []const []const u8, sink: stream_sink.ByteSink) anyerror!void {
    var owned = try parseArgs(allocator, args);
    defer owned.deinit();
    if (!std.mem.eql(u8, owned.request.method, "agent.stream")) return error.CliLiveStreamUnsupported;

    try app.channel_registry.recordCliLiveStream(extractStringParam(owned.params, "session_id"));

    const options = try parseLiveOptions(args);
    try stream_projection.writeBridgeAgentStream(allocator, app, .{
        .request_id = owned.request.request_id,
        .params = owned.params,
        .authority = owned.request.authority,
        .policy = .{
            .max_event_bytes = options.max_event_bytes,
            .max_total_bytes = options.max_total_bytes,
            .cancel_after_events = options.cancel_after_events,
            .text_delta_coalesce_event_limit = options.text_delta_coalesce_event_limit,
            .text_delta_coalesce_byte_limit = options.text_delta_coalesce_byte_limit,
            .text_delta_throttle_window_ms = options.text_delta_throttle_window_ms,
        },
    }, sink);
}

fn extractStringParam(params: []const framework.ValidationField, key: []const u8) ?[]const u8 {
    for (params) |field| {
        if (std.mem.eql(u8, field.key, key)) {
            return switch (field.value) {
                .string => |value| value,
                else => null,
            };
        }
    }
    return null;
}

pub fn streamLiveToStdout(allocator: std.mem.Allocator, app: *runtime.AppContext, args: []const []const u8) anyerror!void {
    var stdout_file = std.fs.File.stdout();
    try streamLive(allocator, app, args, stream_sink.fileSink(&stdout_file));
}

const LiveOptions = struct {
    cancel_after_events: usize = 0,
    max_total_bytes: usize = 512 * 1024,
    max_event_bytes: usize = 64 * 1024,
    text_delta_coalesce_event_limit: usize = 4,
    text_delta_coalesce_byte_limit: usize = 128,
    text_delta_throttle_window_ms: u64 = 120,
};

fn parseLiveOptions(args: []const []const u8) anyerror!LiveOptions {
    var options = LiveOptions{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--cancel-after")) {
            index += 1;
            if (index >= args.len) return error.MissingCancelAfter;
            options.cancel_after_events = try std.fmt.parseInt(usize, args[index], 10);
            continue;
        }
        if (std.mem.eql(u8, args[index], "--max-bytes")) {
            index += 1;
            if (index >= args.len) return error.MissingMaxBytes;
            options.max_total_bytes = try std.fmt.parseInt(usize, args[index], 10);
            continue;
        }
        if (std.mem.eql(u8, args[index], "--max-event-bytes")) {
            index += 1;
            if (index >= args.len) return error.MissingMaxEventBytes;
            options.max_event_bytes = try std.fmt.parseInt(usize, args[index], 10);
            continue;
        }
        if (std.mem.eql(u8, args[index], "--text-delta-coalesce-events")) {
            index += 1;
            if (index >= args.len) return error.MissingTextDeltaCoalesceEvents;
            options.text_delta_coalesce_event_limit = try std.fmt.parseInt(usize, args[index], 10);
            continue;
        }
        if (std.mem.eql(u8, args[index], "--text-delta-coalesce-bytes")) {
            index += 1;
            if (index >= args.len) return error.MissingTextDeltaCoalesceBytes;
            options.text_delta_coalesce_byte_limit = try std.fmt.parseInt(usize, args[index], 10);
            continue;
        }
        if (std.mem.eql(u8, args[index], "--text-delta-throttle-ms")) {
            index += 1;
            if (index >= args.len) return error.MissingTextDeltaThrottleMs;
            options.text_delta_throttle_window_ms = try std.fmt.parseInt(u64, args[index], 10);
            continue;
        }
    }
    return options;
}

fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
    if (needle.len == 0) return 0;
    var count: usize = 0;
    var offset: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, offset, needle)) |index| {
        count += 1;
        offset = index + needle.len;
    }
    return count;
}

pub fn renderEnvelopeJson(allocator: std.mem.Allocator, envelope: framework.CommandEnvelope) anyerror![]u8 {
    if (envelope.ok) {
        return switch (envelope.result.?) {
            .success_json => |json| blk: {
                const owned = try allocator.dupe(u8, json);
                allocator.free(json);
                break :blk owned;
            },
            .task_accepted => |accepted| std.fmt.allocPrint(
                allocator,
                "{{\"accepted\":true,\"taskId\":\"{s}\",\"state\":\"{s}\"}}",
                .{ accepted.task_id, accepted.state },
            ),
        };
    }

    return std.fmt.allocPrint(
        allocator,
        "{{\"ok\":false,\"error\":{{\"code\":\"{s}\",\"message\":\"{s}\"}}}}",
        .{ envelope.app_error.?.code, envelope.app_error.?.message },
    );
}

pub fn renderProtocolEnvelopeJson(allocator: std.mem.Allocator, envelope: framework.CommandEnvelope) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeByte('{');
    try writer.writeAll("\"ok\":");
    try writer.writeAll(if (envelope.ok) "true" else "false");

    if (envelope.ok) {
        try writer.writeAll(",\"result\":");
        switch (envelope.result.?) {
            .success_json => |json| {
                try writer.writeAll(json);
                allocator.free(json);
            },
            .task_accepted => |accepted| {
                try writer.print("{{\"accepted\":true,\"taskId\":\"{s}\",\"state\":\"{s}\"}}", .{ accepted.task_id, accepted.state });
            },
        }
    } else {
        try writer.writeAll(",\"error\":{");
        try appendProtocolStringField(writer, "code", envelope.app_error.?.code, true);
        try appendProtocolStringField(writer, "message", envelope.app_error.?.message, false);
        try writer.writeByte('}');
    }

    try writer.writeAll(",\"meta\":{");
    try appendOptionalStringField(writer, "requestId", envelope.meta.request_id, true);
    try appendOptionalStringField(writer, "traceId", envelope.meta.trace_id, false);
    try appendOptionalStringField(writer, "taskId", envelope.meta.task_id, false);
    try writer.writeByte('}');
    try writer.writeByte('}');
    return allocator.dupe(u8, buf.items);
}

fn appendOptionalStringField(writer: anytype, key: []const u8, value: ?[]const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try appendProtocolKey(writer, key);
    if (value) |actual| {
        try appendProtocolString(writer, actual);
    } else {
        try writer.writeAll("null");
    }
}

fn appendProtocolStringField(writer: anytype, key: []const u8, value: []const u8, first: bool) anyerror!void {
    if (!first) try writer.writeByte(',');
    try appendProtocolKey(writer, key);
    try appendProtocolString(writer, value);
}

fn appendProtocolKey(writer: anytype, key: []const u8) anyerror!void {
    try writer.writeByte('"');
    try writer.writeAll(key);
    try writer.writeAll("\":");
}

fn appendProtocolString(writer: anytype, value: []const u8) anyerror!void {
    try writer.writeByte('"');
    for (value) |ch| {
        switch (ch) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(ch),
        }
    }
    try writer.writeByte('"');
}

test "cli adapter dispatches app meta" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    const json = try dispatchAndRenderJson(std.testing.allocator, app, &.{"app.meta"});
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ok\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"result\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"meta\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"appName\":\"ourclaw\"") != null);
}

test "cli adapter streams live agent events as ndjson" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_cli_stream",
        .label = "Mock OpenAI CLI Stream",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    var sink = stream_sink.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();

    try streamLive(std.testing.allocator, app, &.{
        "agent.stream",
        "sess_cli_live",
        "CALL_TOOL:echo",
        "--provider",
        "mock_openai_cli_stream",
        "--live",
    }, sink.asByteSink());

    const output = try sink.toOwnedSlice();
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"event\":\"meta\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"event\":\"tool.result\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"event\":\"done\"") != null);
}

test "cli live stream exposes cancellation semantics" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_cli_cancel",
        .label = "Mock OpenAI CLI Cancel",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    var sink = stream_sink.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();

    try streamLive(std.testing.allocator, app, &.{
        "agent.stream",
        "sess_cli_cancel",
        "CALL_TOOL:echo",
        "--provider",
        "mock_openai_cli_cancel",
        "--live",
        "--cancel-after",
        "1",
    }, sink.asByteSink());

    const output = try sink.toOwnedSlice();
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"event\":\"meta\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "StreamCancelled") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"event\":\"done\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"ok\":false") != null);
}

test "cli live stream exposes backpressure semantics" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_cli_backpressure",
        .label = "Mock OpenAI CLI Backpressure",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    var sink = stream_sink.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();

    try streamLive(std.testing.allocator, app, &.{
        "agent.stream",
        "sess_cli_backpressure",
        "CALL_TOOL:echo",
        "--provider",
        "mock_openai_cli_backpressure",
        "--live",
        "--max-bytes",
        "32",
    }, sink.asByteSink());

    const output = try sink.toOwnedSlice();
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "StreamBackpressureExceeded") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"event\":\"done\"") != null);
}

test "cli live stream exposes text delta throttle overrides" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_cli_text_delta_throttle",
        .label = "Mock OpenAI CLI Text Delta Throttle",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    var sink = stream_sink.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();

    try streamLive(std.testing.allocator, app, &.{
        "agent.stream",
        "sess_cli_text_delta_throttle",
        "CALL_TOOL:echo",
        "--provider",
        "mock_openai_cli_text_delta_throttle",
        "--live",
        "--text-delta-coalesce-events",
        "64",
        "--text-delta-coalesce-bytes",
        "4096",
        "--text-delta-throttle-ms",
        "0",
    }, sink.asByteSink());

    const output = try sink.toOwnedSlice();
    defer std.testing.allocator.free(output);
    const delta_count = countOccurrences(output, "\"event\":\"text.delta\"");
    try std.testing.expect(delta_count >= 4);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"event\":\"done\"") != null);
}

test "cli live stream supports replay from last event id" {
    var app = try runtime.AppContext.init(std.testing.allocator, .{});
    defer app.destroy();

    try app.provider_registry.register(.{
        .id = "mock_openai_cli_resume",
        .label = "Mock OpenAI CLI Resume",
        .endpoint = "mock://openai/chat",
        .default_model = "gpt-4o-mini",
        .api_key_secret_ref = "openai:api_key",
        .supports_streaming = true,
        .supports_tools = true,
        .health_json = "{}",
    });

    var seeded = try app.agent_runtime.runStream(.{
        .session_id = "sess_cli_resume",
        .prompt = "CALL_TOOL:echo",
        .provider_id = "mock_openai_cli_resume",
        .authority = .admin,
    });
    defer seeded.deinit(std.testing.allocator);

    var sink = stream_sink.ArrayListSink.init(std.testing.allocator);
    defer sink.deinit();

    try streamLive(std.testing.allocator, app, &.{
        "agent.stream",
        "sess_cli_resume",
        "ignored on replay",
        "--provider",
        "mock_openai_cli_resume",
        "--last-event-id",
        "1",
        "--live",
    }, sink.asByteSink());

    const output = try sink.toOwnedSlice();
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"resumeMode\":\"replay_only\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"terminalReason\":\"reconnect_replay_completed\"") != null);
}

test "cli adapter parses agent strategy flags" {
    var owned_run = try parseArgs(std.testing.allocator, &.{
        "agent.run",
        "sess_cli_agent_flags",
        "hello",
        "--provider",
        "mock_openai",
        "--prompt-profile",
        "concise_operator",
        "--response-mode",
        "terse",
        "--max-tool-rounds",
        "2",
        "--no-provider-tools",
    });
    defer owned_run.deinit();
    try std.testing.expect(extractStringParam(owned_run.params, "prompt_profile") != null);
    try std.testing.expect(extractStringParam(owned_run.params, "response_mode") != null);
    try std.testing.expect(extractStringParam(owned_run.params, "provider_id") != null);

    var saw_max_tool_rounds = false;
    var saw_allow_provider_tools = false;
    for (owned_run.params) |field| {
        if (std.mem.eql(u8, field.key, "max_tool_rounds")) {
            saw_max_tool_rounds = true;
            try std.testing.expectEqual(@as(i64, 2), field.value.integer);
        }
        if (std.mem.eql(u8, field.key, "allow_provider_tools")) {
            saw_allow_provider_tools = true;
            try std.testing.expectEqual(false, field.value.boolean);
        }
    }
    try std.testing.expect(saw_max_tool_rounds);
    try std.testing.expect(saw_allow_provider_tools);

    var owned_stream = try parseArgs(std.testing.allocator, &.{
        "agent.stream",
        "sess_cli_stream_flags",
        "hello",
        "--provider",
        "mock_openai",
        "--prompt-profile",
        "concise_operator",
        "--response-mode",
        "terse",
        "--max-tool-rounds",
        "3",
        "--no-provider-tools",
    });
    defer owned_stream.deinit();

    var saw_stream_max_tool_rounds = false;
    var saw_stream_allow_provider_tools = false;
    for (owned_stream.params) |field| {
        if (std.mem.eql(u8, field.key, "max_tool_rounds")) {
            saw_stream_max_tool_rounds = true;
            try std.testing.expectEqual(@as(i64, 3), field.value.integer);
        }
        if (std.mem.eql(u8, field.key, "allow_provider_tools")) {
            saw_stream_allow_provider_tools = true;
            try std.testing.expectEqual(false, field.value.boolean);
        }
    }
    try std.testing.expect(saw_stream_max_tool_rounds);
    try std.testing.expect(saw_stream_allow_provider_tools);
}

test "cli adapter parses session and memory optional flags" {
    var owned_session = try parseArgs(std.testing.allocator, &.{
        "session.get",
        "sess_cli_session_get",
        "--summary-items",
        "7",
        "--recent-turns-limit",
        "4",
    });
    defer owned_session.deinit();

    var saw_summary_items = false;
    var saw_recent_turns_limit = false;
    for (owned_session.params) |field| {
        if (std.mem.eql(u8, field.key, "summary_items")) {
            saw_summary_items = true;
            try std.testing.expectEqual(@as(i64, 7), field.value.integer);
        }
        if (std.mem.eql(u8, field.key, "recent_turns_limit")) {
            saw_recent_turns_limit = true;
            try std.testing.expectEqual(@as(i64, 4), field.value.integer);
        }
    }
    try std.testing.expect(saw_summary_items);
    try std.testing.expect(saw_recent_turns_limit);

    var owned_memory = try parseArgs(std.testing.allocator, &.{
        "memory.summary",
        "sess_cli_memory_summary",
        "--max-items",
        "6",
    });
    defer owned_memory.deinit();

    var saw_max_items = false;
    for (owned_memory.params) |field| {
        if (std.mem.eql(u8, field.key, "max_items")) {
            saw_max_items = true;
            try std.testing.expectEqual(@as(i64, 6), field.value.integer);
        }
    }
    try std.testing.expect(saw_max_items);
}

test "cli adapter parses events and observer optional flags" {
    var owned_subscribe = try parseArgs(std.testing.allocator, &.{
        "events.subscribe",
        "stream.output",
        "--after-seq",
        "5",
    });
    defer owned_subscribe.deinit();

    var saw_after_seq = false;
    for (owned_subscribe.params) |field| {
        if (std.mem.eql(u8, field.key, "after_seq")) {
            saw_after_seq = true;
            try std.testing.expectEqual(@as(i64, 5), field.value.integer);
        }
    }
    try std.testing.expect(saw_after_seq);

    var owned_poll = try parseArgs(std.testing.allocator, &.{
        "events.poll",
        "7",
        "--execution-id",
        "exec_01",
        "--session-id",
        "sess_01",
    });
    defer owned_poll.deinit();
    try std.testing.expect(extractStringParam(owned_poll.params, "execution_id") != null);
    try std.testing.expect(extractStringParam(owned_poll.params, "session_id") != null);

    var owned_recent = try parseArgs(std.testing.allocator, &.{
        "observer.recent",
        "--execution-id",
        "exec_02",
        "--session-id",
        "sess_02",
    });
    defer owned_recent.deinit();
    try std.testing.expect(extractStringParam(owned_recent.params, "execution_id") != null);
    try std.testing.expect(extractStringParam(owned_recent.params, "session_id") != null);
}
