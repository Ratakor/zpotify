const std = @import("std");
const api = @import("zpotify");
const cmd = @import("../cmd.zig");
const help = cmd.help;

pub const description = "Get/Set volume";
pub const usage =
    \\Usage: zpotify volume [[+/-]0-100]
    \\
    \\Description: Get/Set volume
    \\             Prepend +/- to relatively increase/decrease the volume
    \\
;

pub fn exec(ctx: *cmd.Context) !void {
    const playback_state = try api.player.getPlaybackState(ctx.client);

    var volume = blk: {
        if (playback_state.device) |device| {
            if (device.supports_volume) {
                break :blk device.volume_percent.?;
            } else {
                std.log.err("Volume control is not supported for this device", .{});
                std.process.exit(1);
            }
        } else {
            std.log.warn("No active device", .{});
            std.process.exit(1);
        }
    };

    if (ctx.args.next()) |buf| {
        if (buf[0] == '+') {
            volume += parseVolume(ctx, buf[1..]);
            if (volume > 100) {
                volume = 100;
            }
        } else if (buf[0] == '-') {
            volume -|= parseVolume(ctx, buf[1..]);
        } else {
            volume = parseVolume(ctx, buf);
        }
        std.log.info("Setting volume to {d}%", .{volume});
        try api.player.setVolume(ctx.client, volume);
    } else {
        std.log.info("Volume for {s} is set to {d}%", .{
            playback_state.device.?.name,
            volume,
        });
    }
}

fn parseVolume(ctx: *cmd.Context, buf: []const u8) u64 {
    const volume = std.fmt.parseUnsigned(u64, buf, 10) catch |err| {
        std.log.err("Invalid volume: {}", .{err});
        help.exec(ctx, "volume") catch {};
        std.process.exit(1);
    };
    if (volume > 100) {
        std.log.err("Volume must be between -100 and 100 inclusive", .{});
        help.exec(ctx, "volume") catch {};
        std.process.exit(1);
    }
    return volume;
}
