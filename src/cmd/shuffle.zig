const std = @import("std");
const api = @import("zpotify");
const help = @import("../cmd.zig").help;

pub const description = "Toggle shuffle mode or force it to a specific state";
pub const usage =
    \\Usage: zpotify shuffle [on|off]
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
                try help.exec("shuffle");
                std.process.exit(1);
            }
        } else {
            const playback_state = try api.player.getPlaybackState(client);
            break :blk !playback_state.shuffle_state;
        }
    };
    if (state) {
        std.log.info("Enabling shuffle", .{});
    } else {
        std.log.info("Disabling shuffle", .{});
    }
    try api.player.toggleShuffle(client, state);
}
