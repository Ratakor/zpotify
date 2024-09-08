const std = @import("std");
const api = @import("../api.zig");

pub const usage =
    \\Usage: {s} like
    \\
    \\Description: Add the current track to your liked songs
    \\
;

pub fn exec(client: *api.Client) !void {
    const playback_state = api.getPlaybackState(client) catch |err| switch (err) {
        error.NotPlaying => return,
        else => return err,
    };
    defer playback_state.deinit();

    if (playback_state.value.item) |track| {
        std.log.info("Adding '{s}' to your liked songs", .{track.name});
        try api.saveTracks(client, track.id);
    } else {
        std.log.warn("No track is currently playing", .{});
        return;
    }
}
