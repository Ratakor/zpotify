const std = @import("std");
const api = @import("../api.zig");
const help = @import("../cmd.zig").help;

pub const usage =
    \\Usage: {s} shuffle [on|off]
    \\
    \\Description: Toggle shuffle mode or force it to a specific state
    \\
;

pub fn exec(client: *api.Client, arg: ?[]const u8) !void {
    const state = blk: {
        if (arg) |state| {
            if (std.mem.eql(u8, state, "on")) {
                break :blk true;
            } else if (std.mem.eql(u8, state, "off")) {
                break :blk false;
            } else {
                std.log.err("Invalid state: {s}", .{state});
                help.exec("shuffle");
                std.process.exit(1);
            }
        } else {
            const playback_state = api.getPlaybackState(client) catch |err| switch (err) {
                error.NotPlaying => std.process.exit(1),
                else => return err,
            };
            defer playback_state.deinit();
            break :blk !playback_state.value.shuffle_state;
        }
    };
    if (state) {
        std.log.info("Enabling shuffle", .{});
    } else {
        std.log.info("Disabling shuffle", .{});
    }
    try api.toggleShuffle(client, state);
}
