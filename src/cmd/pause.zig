const std = @import("std");
const api = @import("../api.zig");

pub const usage =
    \\Usage: {s} pause
    \\
    \\Description: Toggle pause state
    \\
;

pub fn exec(client: *api.Client) !void {
    const playback_state = api.getPlaybackState(client) catch |err| switch (err) {
        error.NotPlaying => std.process.exit(1),
        else => return err,
    };
    defer playback_state.deinit();

    if (playback_state.value.is_playing) {
        std.log.info("Pausing playback", .{});
        try api.pausePlayback(client);
    } else {
        std.log.info("Resuming playback", .{});
        api.startPlayback(client, null, null) catch |err| switch (err) {
            error.NotFound => std.process.exit(1),
            else => return err,
        };
    }
}
