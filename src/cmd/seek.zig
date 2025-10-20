const std = @import("std");
const api = @import("../api.zig");
const help = @import("../cmd.zig").help;

pub const description = "Get/Set the position of the current track";
pub const usage =
    \\Usage: zpotify seek [[+/-][minutes:]seconds]
    \\
    \\Description: Get/Set the position of the current track
    \\             Format is either composed only of seconds or minutes:seconds
    \\             Prepend +/- to relatively increase/decrease the position
    \\
;

const Time = struct {
    min: u32,
    sec: u32,

    fn cmp(self: Time, other: Time) std.math.Order {
        const min_order = std.math.order(self.min, other.min);
        return if (min_order == .eq)
            std.math.order(self.sec, other.sec)
        else
            min_order;
    }

    fn add(self: Time, other: Time) Time {
        var min = self.min + other.min;
        var sec = self.sec + other.sec;
        min += sec / std.time.s_per_min;
        sec %= std.time.s_per_min;
        return .{ .min = min, .sec = sec };
    }

    fn sub(self: Time, other: Time) Time {
        std.debug.assert(self.cmp(other) != .lt);
        var min = self.min - other.min;
        var sec = self.sec;
        if (sec < other.sec) {
            sec = sec + 60 - other.sec;
            min -= 1;
        } else {
            sec -= other.sec;
        }
        return .{ .min = min, .sec = sec };
    }

    pub fn format(self: Time, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        return writer.print("{d}:{d:0>2}", .{ self.min, self.sec });
    }
};

pub fn exec(client: *api.Client, arg: ?[]const u8) !void {
    if (arg) |buf| {
        const time = if (buf[0] == '+')
            try parseInputRelative(client, buf[1..], .pos)
        else if (buf[0] == '-')
            try parseInputRelative(client, buf[1..], .neg)
        else
            parseInputAbsolute(buf);
        const ms = (time.min * std.time.ms_per_min) + (time.sec * std.time.ms_per_s);
        std.log.info("Seeking to {f}", .{time});
        try api.seekToPosition(client, ms);
    } else {
        const playback_state = try api.getPlaybackState(client);

        if (playback_state.item) |track| {
            const progress_ms = playback_state.progress_ms;
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
            std.process.exit(1);
        }
    }
}

fn parseUnsigned(buf: []const u8) u32 {
    return std.fmt.parseUnsigned(u32, buf, 10) catch |err| {
        std.log.err("Invalid time format: {}", .{err});
        help.exec("seek") catch {};
        std.process.exit(1);
    };
}

fn parseInputAbsolute(buf: []const u8) Time {
    var min, var sec = blk: {
        const sep = std.mem.indexOfScalar(u8, buf, ':') orelse {
            break :blk .{ 0, parseUnsigned(buf) };
        };
        const min = parseUnsigned(buf[0..sep]);
        const sec = parseUnsigned(buf[sep + 1 ..]);
        break :blk .{ min, sec };
    };
    min += sec / std.time.s_per_min;
    sec %= std.time.s_per_min;
    return .{ .min = min, .sec = sec };
}

fn parseInputRelative(client: *api.Client, buf: []const u8, sign: enum { pos, neg }) !Time {
    const progress: Time = blk: {
        const playback_state = try api.getPlaybackState(client);
        const progress_ms = playback_state.progress_ms;
        const progress_min = progress_ms / std.time.ms_per_min;
        const progress_s = (progress_ms / std.time.ms_per_s) % std.time.s_per_min;
        break :blk .{ .min = @intCast(progress_min), .sec = @intCast(progress_s) };
    };
    const diff = parseInputAbsolute(buf);

    return switch (sign) {
        .pos => progress.add(diff),
        .neg => switch (progress.cmp(diff)) {
            .lt, .eq => .{ .min = 0, .sec = 0 },
            .gt => progress.sub(diff),
        },
    };
}

test "Time.cmp" {
    const expect = std.testing.expect;

    var t1: Time = .{ .min = 0, .sec = 0 };
    var t2: Time = .{ .min = 0, .sec = 0 };
    try expect(t1.cmp(t2) == .eq);
    t1.sec = 1;
    try expect(t1.cmp(t2) == .gt);
    t2.min = 1;
    try expect(t1.cmp(t2) == .lt);
}

test "Time.add" {
    const expect = std.testing.expect;

    var t1: Time = .{ .min = 1, .sec = 33 };
    var t2: Time = .{ .min = 42, .sec = 42 };
    var r = t1.add(t2);
    try expect(r.min == 44);
    try expect(r.sec == 15);

    t1 = .{ .min = 0, .sec = 69420 };
    t2 = .{ .min = 42, .sec = 42 };
    r = t1.add(t2);
    try expect(r.min == 1199);
    try expect(r.sec == 42);
}

test "Time.sub" {
    const expect = std.testing.expect;

    var t1: Time = .{ .min = 3, .sec = 9 };
    var t2: Time = .{ .min = 3, .sec = 9 };
    var r = t1.sub(t2);
    try expect(r.min == 0);
    try expect(r.sec == 0);

    t1 = .{ .min = 4, .sec = 1 };
    t2 = .{ .min = 3, .sec = 9 };
    r = t1.sub(t2);
    try expect(r.min == 0);
    try expect(r.sec == 52);
}
