const std = @import("std");
const api = @import("zpotify").api;

pub const description = "Add the current track to your liked songs";
pub const usage =
    \\Usage: zpotify like
    \\
    \\Description: Add the current track to your liked songs
    \\
;

pub fn exec(client: *api.Client) !void {
    const playback_state = try api.getPlaybackState(client);

    if (playback_state.item) |track| {
        std.log.info("Adding '{s}' from '{s}' by {s} to your liked songs", .{
            track.name,
            track.album.name,
            track.artists[0].name,
        });
        try api.saveTracks(client, track.id);
    } else {
        std.log.warn("No track is currently playing", .{});
        std.process.exit(1);
    }
}
