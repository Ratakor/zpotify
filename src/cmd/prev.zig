const std = @import("std");
const api = @import("../api.zig");

pub const usage =
    \\Usage: {s} prev
    \\
    \\Description: Skip to previous track
    \\
;

pub fn exec(allocator: std.mem.Allocator, client: *std.http.Client, access_token: []const u8) !void {
    std.log.info("Skipping to previous track", .{});
    try api.post(.prev, allocator, client, access_token, .{});
}
