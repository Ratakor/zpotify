const std = @import("std");
const api = @import("zpotify");

pub const description = "Skip to next track";
pub const usage =
    \\Usage: zpotify next
    \\
    \\Description: Skip to next track
    \\
;

pub fn exec(client: *api.Client) !void {
    std.log.info("Skipping to next track", .{});
    try api.player.skipToNext(client);
}
