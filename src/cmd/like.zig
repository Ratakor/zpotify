const std = @import("std");
const api = @import("../api.zig");

pub const usage =
    \\Usage: {s} like
    \\
    \\Description: Add the current track to your liked songs
    \\
;

pub fn exec(allocator: std.mem.Allocator, client: *std.http.Client, access_token: []const u8) !void {
    const playback_state = api.get(
        .playback_state,
        allocator,
        client,
        access_token,
    ) catch |err| switch (err) {
        error.NotPlaying => return,
        else => return err,
    };
    defer playback_state.deinit();

    if (playback_state.value.item) |track| {
        std.log.info("Adding '{s}' to your liked songs", .{track.name});
        try api.put(.like, allocator, client, access_token, .{track.id});
    } else {
        std.log.err("No track is currently playing", .{});
        std.process.exit(1);
    }
}
