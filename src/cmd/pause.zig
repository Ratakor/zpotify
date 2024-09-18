const std = @import("std");
const api = @import("../api.zig");

pub const usage =
    \\Usage: {s} pause
    \\
    \\Description: Toggle pause state
    \\
;

pub fn exec(client: *api.Client) !void {
    const playback_state = try api.getPlaybackState(client);

    if (playback_state.is_playing) {
        std.log.info("Pausing playback", .{});
        try api.pausePlayback(client);
    } else {
        std.log.info("Resuming playback", .{});
        try api.startPlayback(client, null, null);
    }
}
