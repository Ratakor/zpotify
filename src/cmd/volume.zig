const std = @import("std");
const api = @import("../api.zig");
const help = @import("../cmd.zig").help;

pub const description = "Get/Set volume";
pub const usage =
    \\Usage: zpotify volume [[+/-]0-100]
    \\
    \\Description: Get/Set volume, prepend +/- to relatively increase/decrease the volume
    \\
;

pub fn exec(client: *api.Client, arg: ?[]const u8) !void {
    const playback_state = try api.getPlaybackState(client);

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

    if (arg) |buf| {
        if (buf[0] == '+') {
            volume += parseVolume(buf[1..]);
            if (volume > 100) {
                volume = 100;
            }
        } else if (buf[0] == '-') {
            volume -|= parseVolume(buf[1..]);
        } else {
            volume = parseVolume(buf);
        }
        std.log.info("Setting volume to {d}%", .{volume});
        try api.setVolume(client, volume);
    } else {
        std.log.info("Volume for {s} is set to {d}%", .{
            playback_state.device.?.name,
            volume,
        });
    }
}

fn parseVolume(buf: []const u8) u64 {
    const volume = std.fmt.parseUnsigned(u64, buf, 10) catch |err| {
        std.log.err("Invalid volume: {}", .{err});
        help.exec("volume") catch {};
        std.process.exit(1);
    };
    if (volume > 100) {
        std.log.err("Volume must be between -100 and 100 inclusive", .{});
        help.exec("volume") catch {};
        std.process.exit(1);
    }
    return volume;
}
