const std = @import("std");
const api = @import("../api.zig");

pub const usage =
    \\Usage: {s} shuffle
    \\
    \\Description: Toggle shuffle mode
    \\
;

pub fn exec(client: *api.Client) !void {
    const playback_state = api.getPlaybackState(client) catch |err| switch (err) {
        error.NotPlaying => std.process.exit(1),
        else => return err,
    };
    defer playback_state.deinit();

    const new_state = !playback_state.value.shuffle_state;
    std.log.info("Setting shuffle to {s}", .{if (new_state) "on" else "off"});
    try api.toggleShuffle(client, new_state);
}
