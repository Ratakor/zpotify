const std = @import("std");
const api = @import("../api.zig");

pub const usage =
    \\Usage: {s} next
    \\
    \\Description: Skip to next track
    \\
;

pub fn exec(client: *api.Client) !void {
    std.log.info("Skipping to next track", .{});
    try api.skipToNext(client);
}
