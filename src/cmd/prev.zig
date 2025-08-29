const std = @import("std");
const api = @import("../api.zig");

pub const usage =
    \\Usage: zpotify prev
    \\
    \\Description: Skip to previous track
    \\
;

pub fn exec(client: *api.Client) !void {
    std.log.info("Skipping to previous track", .{});
    try api.skipToPrevious(client);
}
