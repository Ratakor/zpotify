const std = @import("std");
const api = @import("../api.zig");
const help = @import("../cmd.zig").help;

pub const usage =
    \\Usage: {s} vol [0-100|up|down]
    \\
    \\Description: Get/Set volume or increase/decrease volume by 10%
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

    if (arg) |vol| {
        if (std.mem.eql(u8, vol, "up")) {
            volume += 10;
            if (volume > 100) {
                volume = 100;
            }
        } else if (std.mem.eql(u8, vol, "down")) {
            volume -|= 10;
        } else {
            volume = std.fmt.parseUnsigned(u64, vol, 10) catch |err| {
                std.log.err("Invalid volume: {}", .{err});
                help.exec("vol");
                std.process.exit(1);
            };
            if (volume > 100) {
                std.log.err("Volume must be between 0 and 100", .{});
                help.exec("vol");
                std.process.exit(1);
            }
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
