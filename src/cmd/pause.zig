const std = @import("std");
const api = @import("zpotify");
const Context = @import("../Context.zig");

pub const description = "Toggle pause state";
pub const usage =
    \\Usage: zpotify pause
    \\
    \\Description: Toggle pause state
    \\
;

pub fn exec(ctx: *Context) !void {
    const playback_state = try api.player.getPlaybackState(ctx.client);

    if (playback_state.is_playing) {
        std.log.info("Pausing playback", .{});
        try api.player.pausePlayback(ctx.client);
    } else {
        std.log.info("Resuming playback", .{});
        try api.player.startPlayback(ctx.client, null, null);
    }
}
