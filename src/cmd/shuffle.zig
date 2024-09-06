const std = @import("std");
const api = @import("../api.zig");

pub const usage =
    \\Usage: {s} shuffle
    \\
    \\Description: Toggle shuffle mode
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

    const new_shuffle_state = !playback_state.value.shuffle_state;
    std.log.info("Setting shuffle to {s}", .{if (new_shuffle_state) "on" else "off"});
    try api.put(.shuffle, allocator, client, access_token, .{new_shuffle_state});
}
