const std = @import("std");
const api = @import("../api.zig");

pub const usage =
    \\Usage: {s} next
    \\
    \\Description: Skip to next track
    \\
;

pub fn exec(allocator: std.mem.Allocator, client: *std.http.Client, access_token: []const u8) !void {
    std.log.info("Skipping to next track", .{});
    try api.post(.next, allocator, client, access_token, .{});
}
