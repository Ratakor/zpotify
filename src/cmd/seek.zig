const std = @import("std");
const api = @import("../api.zig");
const help = @import("../cmd.zig").help;

pub const usage =
    \\Usage: {s} seek [time]
    \\
    \\Description: Get/Set the position of the current track in seconds or minutes:seconds format
    \\
;

pub fn exec(client: *api.Client, arg: ?[]const u8) !void {
    if (arg) |raw_arg| {
        var min, var sec = blk: {
            const sep = std.mem.indexOfScalar(u8, raw_arg, ':') orelse {
                break :blk .{ 0, parseUnsigned(raw_arg) };
            };
            const min = parseUnsigned(raw_arg[0..sep]);
            const sec = parseUnsigned(raw_arg[sep + 1 ..]);
            break :blk .{ min, sec };
        };
        min += sec / std.time.s_per_min;
        sec %= std.time.s_per_min;
        const ms = (min * std.time.ms_per_min) + (sec * std.time.ms_per_s);

        std.log.info("Seeking to {d}:{d:0>2}", .{ min, sec });
        try api.seekToPosition(client, ms);
    } else {
        const playback_state = api.getPlaybackState(client) catch |err| switch (err) {
            error.NotPlaying => std.process.exit(1),
            else => return err,
        };
        defer playback_state.deinit();

        if (playback_state.value.item) |track| {
            const progress_ms = playback_state.value.progress_ms;
            const progress_min = progress_ms / std.time.ms_per_min;
            const progress_s = (progress_ms / std.time.ms_per_s) % std.time.s_per_min;

            const duration_ms = track.duration_ms;
            const duration_min = duration_ms / std.time.ms_per_min;
            const duration_s = (duration_ms / std.time.ms_per_s) % std.time.s_per_min;

            std.log.info(
                "Time elapsed: {d}:{d:0>2} - {d}:{d}",
                .{ progress_min, progress_s, duration_min, duration_s },
            );
        } else {
            std.log.warn("No track is currently playing", .{});
            return;
        }
    }
}

fn parseUnsigned(buf: []const u8) u64 {
    return std.fmt.parseUnsigned(u64, buf, 10) catch |err| {
        std.log.err("Invalid time format: {}", .{err});
        help.exec("seek");
        std.process.exit(1);
    };
}
