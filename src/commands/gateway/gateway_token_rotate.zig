const std = @import("std");
const framework = @import("framework");
const services_model = @import("../../domain/services.zig");

pub fn definition(command_services: *services_model.CommandServices) framework.CommandDefinition {
    return .{
        .id = "gateway.token.rotate",
        .method = "gateway.token.rotate",
        .description = "Rotate the shared gateway token",
        .authority = .operator,
        .user_data = @ptrCast(command_services),
        .params = &.{},
        .handler = handle,
    };
}

fn handle(ctx: *const framework.CommandContext) anyerror![]const u8 {
    const services = services_model.CommandServices.fromCommandContext(ctx);
    var bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&bytes);
    var token_buf: [32]u8 = undefined;
    encodeHexLower(&token_buf, &bytes);
    try services.secret_store.put("gateway:shared_token", token_buf[0..]);
    return std.fmt.allocPrint(ctx.allocator, "{{\"rotated\":true,\"token\":\"{s}\"}}", .{token_buf});
}

fn encodeHexLower(out: *[32]u8, bytes: *const [16]u8) void {
    const alphabet = "0123456789abcdef";
    for (bytes.*, 0..) |byte, index| {
        out[index * 2] = alphabet[byte >> 4];
        out[index * 2 + 1] = alphabet[byte & 0x0f];
    }
}
