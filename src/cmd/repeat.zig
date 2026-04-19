const std = @import("std");
const api = @import("zpotify");
const cmd = @import("../cmd.zig");
const help = cmd.help;

pub const description = "Get/Set repeat mode";
pub const usage =
    \\Usage: zpotify repeat [track|context|off]
    \\
    \\Description: Get/Set repeat mode
    \\
;

pub fn exec(ctx: *cmd.Context) !void {
    if (ctx.args.next()) |state_str| {
        if (std.meta.stringToEnum(api.RepeatState, state_str)) |state| {
            std.log.info("Setting repeat mode to {t}", .{state});
            try api.player.setRepeatMode(ctx.client, state);
        } else {
            std.log.err("Invalid repeat mode: {s}", .{state_str});
            try help.exec(ctx, "repeat");
            std.process.exit(1);
        }
    } else {
        const playback_state = try api.player.getPlaybackState(ctx.client);
        std.log.info("Repeat mode is currently set to {s}", .{playback_state.repeat_state});
    }
}
