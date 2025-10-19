const std = @import("std");
const api = @import("zpotify").api;

pub const description = "Toggle pause state";
pub const usage =
    \\Usage: zpotify pause
    \\
    \\Description: Toggle pause state
    \\
;

pub fn exec(client: *api.Client) !void {
    const playback_state = try api.player.getPlaybackState(client);

    if (playback_state.is_playing) {
        std.log.info("Pausing playback", .{});
        try api.player.pausePlayback(client);
    } else {
        std.log.info("Resuming playback", .{});
        try api.player.startPlayback(client, null, null);
    }
}
