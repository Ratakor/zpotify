const std = @import("std");
const api = @import("../api.zig");
const help = @import("../cmd.zig").help;

pub const usage =
    \\Usage: {s} vol [0-100|up|down]
    \\
    \\Description: Get/Set volume or increase/decrease volume by 10%
    \\
;

pub fn exec(
    allocator: std.mem.Allocator,
    arg: ?[]const u8,
    client: *std.http.Client,
    access_token: []const u8,
) !void {
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

    var volume = blk: {
        if (playback_state.value.device) |device| {
            if (device.supports_volume) {
                break :blk device.volume_percent.?;
            } else {
                std.log.err("Volume control is not supported for this device", .{});
                std.process.exit(1);
            }
        } else {
            std.log.err("No active device", .{});
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
        try api.put(.volume, allocator, client, access_token, .{volume});
    } else {
        std.log.info("Volume for {s} is set to {d}%", .{
            playback_state.value.device.?.name,
            volume,
        });
    }
}
