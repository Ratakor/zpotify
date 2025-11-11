const std = @import("std");
const api = @import("zpotify");

pub const description = "Skip to previous track";
pub const usage =
    \\Usage: zpotify prev
    \\
    \\Description: Skip to previous track
    \\
;

pub fn exec(client: *api.Client) !void {
    std.log.info("Skipping to previous track", .{});
    try api.player.skipToPrevious(client);
}
