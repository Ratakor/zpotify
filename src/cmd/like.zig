const std = @import("std");
const api = @import("zpotify");
const cmd = @import("../cmd.zig");

pub const description = "Add the current track to your liked songs";
pub const usage =
    \\Usage: zpotify like
    \\
    \\Description: Add the current track to your liked songs
    \\
;

pub fn exec(ctx: *cmd.Context) !void {
    const playback_state = try api.player.getPlaybackState(ctx.client);

    if (playback_state.item) |track| {
        std.log.info("Adding '{s}' from '{s}' by {s} to your liked songs", .{
            track.name,
            track.album.name,
            track.artists[0].name,
        });
        try api.tracks.saveTracks(ctx.client, track.id);
    } else {
        std.log.warn("No track is currently playing", .{});
        std.process.exit(1);
    }
}
