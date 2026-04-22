const std = @import("std");
const api = @import("zpotify");
const cmd = @import("../cmd.zig");

pub const description = "Skip to next track";
pub const usage =
    \\Usage: zpotify next
    \\
    \\Description: Skip to next track
    \\
;

pub fn exec(ctx: *cmd.Context) !void {
    std.log.info("Skipping to next track", .{});
    try api.player.skipToNext(ctx.client);
}
