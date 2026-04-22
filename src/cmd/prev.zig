const std = @import("std");
const api = @import("zpotify");
const cmd = @import("../cmd.zig");

pub const description = "Skip to previous track";
pub const usage =
    \\Usage: zpotify prev
    \\
    \\Description: Skip to previous track
    \\
;

pub fn exec(ctx: *cmd.Context) !void {
    std.log.info("Skipping to previous track", .{});
    try api.player.skipToPrevious(ctx.client);
}
