const std = @import("std");
const api = @import("../api.zig");

pub const usage =
    \\Usage: {s} pause
    \\
    \\Description: Toggle pause state
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

    if (playback_state.value.is_playing) {
        std.log.info("Pausing playback", .{});
        try api.put(.pause, allocator, client, access_token, .{});
    } else {
        std.log.info("Resuming playback", .{});
        try api.put(.play, allocator, client, access_token, .{@as(?[]const u8, null)});
    }
}
