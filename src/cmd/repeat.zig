const std = @import("std");
const api = @import("zpotify");
const help = @import("../cmd.zig").help;

pub const description = "Get/Set repeat mode";
pub const usage =
    \\Usage: zpotify repeat [track|context|off]
    \\
    \\Description: Get/Set repeat mode
    \\
;

pub fn exec(client: *api.Client, arg: ?[]const u8) !void {
    if (arg) |state_str| {
        if (std.meta.stringToEnum(api.RepeatState, state_str)) |state| {
            std.log.info("Setting repeat mode to {t}", .{state});
            try api.player.setRepeatMode(client, state);
        } else {
            std.log.err("Invalid repeat mode: {s}", .{state_str});
            try help.exec("repeat");
            std.process.exit(1);
        }
    } else {
        const playback_state = try api.player.getPlaybackState(client);
        std.log.info("Repeat mode is currently set to {s}", .{playback_state.repeat_state});
    }
}
