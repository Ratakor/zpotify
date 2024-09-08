const std = @import("std");
const api = @import("../api.zig");
const help = @import("../cmd.zig").help;

pub const usage =
    \\Usage: {s} print [format]...
    \\
    \\Description: Display current track info in a specific format
    \\
    \\Format options:
    \\  {{title}}: prints the title of the current track
    \\  {{state}}: prints the current playback state
    \\  {{state:Playing/Paused}}: prints "Playing" if the track is playing, "Paused" otherwise
    \\  {{album}}: prints the name of the current album
    \\  {{artist}}: prints the name of the first artist of the current track
    \\  {{artists:separator}}: prints all artists separated by the separator (default is ", ")
    \\  {{device}}: prints the name of the current device
    \\  {{volume}}: prints the current volume
    \\  {{repeat}}: prints the current repeat state
    \\  {{shuffle}}: prints the current shuffle state
    \\  {{bar:n}}: prints a progress bar of length n (default is 50)
    \\  {{progress}}: prints the current progress as min:sec
    \\  {{duration}}: prints the duration of the current track as min:sec
    \\  {{url}}: prints the url of the current track
    \\  {{album_url}}: prints the url of the current album
    \\  \{{: prints '{{'
    \\  \}}: prints '}}'
    \\
    \\Default Format:
    \\
++ escapeDefaultFormat();

const default_format =
    \\Track: {title}
    \\Artist(s): {artists}
    \\Album: {album}
    \\Device: {device}
    \\Volume: {volume}%
    \\Repeat: {repeat}
    \\Shuffle: {shuffle}
    \\Progress: {bar} {progress} / {duration}
    \\URL: {url}
    \\Album URL: {album_url}
    \\State: {state}
    \\
;

fn escapeDefaultFormat() []const u8 {
    comptime {
        @setEvalBranchQuota(10000);
        var buffer: [4096]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(buffer[0..]);
        const allocator = fba.allocator();
        const tmp = std.mem.replaceOwned(u8, allocator, default_format, "{", "{{") catch unreachable;
        return std.mem.replaceOwned(u8, allocator, tmp, "}", "}}") catch unreachable;
    }
}

pub fn exec(client: *api.Client, args: *std.process.ArgIterator) !void {
    const playback_state = api.getPlaybackState(client) catch |err| switch (err) {
        error.NotPlaying => return,
        else => return err,
    };
    defer playback_state.deinit();

    const stdout = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout);
    const writer = bw.writer();

    if (args.next()) |arg2| {
        try format(writer, arg2, playback_state.value);
        while (args.next()) |arg| {
            try format(writer, arg, playback_state.value);
        }
    } else {
        try format(writer, default_format, playback_state.value);
    }

    try bw.flush();
}

fn format(writer: anytype, fmt: []const u8, info: api.PlaybackState) !void {
    var i: usize = 0;
    while (i < fmt.len) : (i += 1) {
        switch (fmt[i]) {
            '{' => {
                i += 1;
                const fmt_begin = i;
                while (i < fmt.len and fmt[i] != '}') i += 1;
                const fmt_end = i;
                if (i >= fmt.len) {
                    std.log.err("Missing closing }}", .{});
                    std.process.exit(1);
                }

                // no check for { in arg because I don't care
                const arg = fmt[fmt_begin..fmt_end];
                try handleFormatArg(writer, arg, info);
            },
            '}' => {
                std.log.err("Missing opening {{", .{});
                std.process.exit(1);
            },
            '\\' => {
                i += 1;
                if (i >= fmt.len) {
                    std.log.err("Missing escape sequence", .{});
                    std.process.exit(1);
                }
                const unescaped = switch (fmt[i]) {
                    '{', '}', '\\' => fmt[i],
                    '0' => std.ascii.control_code.nul,
                    'a' => std.ascii.control_code.bel,
                    'b' => std.ascii.control_code.bs,
                    't' => std.ascii.control_code.ht,
                    'n' => std.ascii.control_code.lf,
                    'v' => std.ascii.control_code.vt,
                    'f' => std.ascii.control_code.ff,
                    'r' => std.ascii.control_code.cr,
                    'x' => blk: {
                        i += 1;
                        if (i >= fmt.len) {
                            std.log.err("Missing hex digit", .{});
                            std.process.exit(1);
                        }
                        const p1 = hexToInt(fmt[i]) catch {
                            std.log.warn("Invalid hex digit: {c}", .{fmt[i]});
                            i += 1;
                            continue;
                        };
                        i += 1;
                        if (i >= fmt.len) {
                            std.log.err("Missing hex digit", .{});
                            std.process.exit(1);
                        }
                        const p2 = hexToInt(fmt[i]) catch {
                            std.log.warn("Invalid hex digit: {c}", .{fmt[i]});
                            continue;
                        };
                        break :blk p1 * 16 + p2;
                    },
                    else => {
                        std.log.warn("Unknown escape sequence: \\{c}", .{fmt[i]});
                        continue;
                    },
                };
                try writer.writeByte(unescaped);
            },
            else => try writer.writeByte(fmt[i]),
        }
    }
}

fn hexToInt(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => error.InvalidChar,
    };
}

fn handleFormatArg(writer: anytype, arg: []const u8, info: api.PlaybackState) !void {
    if (std.mem.eql(u8, arg, "title")) {
        if (info.item) |track| {
            try writer.print("{s}", .{track.name});
        } else {
            try writer.writeAll("null");
        }
    } else if (std.mem.startsWith(u8, arg, "state")) {
        const play, const pause = blk: {
            const start_play = std.mem.indexOfScalar(u8, arg, ':') orelse {
                break :blk .{ "Playing", "Paused" };
            };
            const start_pause = (std.mem.indexOfScalar(u8, arg[start_play..], '/') orelse {
                std.log.err("Invalid state format: {s}", .{arg});
                help.exec("print");
                std.process.exit(1);
            }) + start_play;
            break :blk .{ arg[start_play + 1 .. start_pause], arg[start_pause + 1 ..] };
        };
        if (info.is_playing) {
            try writer.writeAll(play);
        } else {
            try writer.writeAll(pause);
        }
    } else if (std.mem.eql(u8, arg, "artist")) {
        if (info.item) |track| {
            // assume at least one artist
            try writer.writeAll(track.artists[0].name);
        } else {
            try writer.writeAll("null");
        }
    } else if (std.mem.startsWith(u8, arg, "artists")) {
        if (info.item) |track| {
            const sep = blk: {
                const idx = std.mem.indexOfScalar(u8, arg, ':') orelse break :blk ", ";
                if (idx == arg.len) break :blk "";
                break :blk arg[idx + 1 ..];
            };
            // assume at least one artist
            try writer.writeAll(track.artists[0].name);
            for (track.artists[1..]) |artist| {
                try writer.print("{s}{s}", .{ sep, artist.name });
            }
        } else {
            try writer.writeAll("null");
        }
    } else if (std.mem.eql(u8, arg, "volume")) {
        if (info.device) |device| {
            try writer.print("{?d}", .{device.volume_percent});
        } else {
            try writer.writeAll("null");
        }
    } else if (std.mem.eql(u8, arg, "device")) {
        if (info.device) |device| {
            try writer.writeAll(device.name);
        } else {
            try writer.writeAll("null");
        }
    } else if (std.mem.eql(u8, arg, "repeat")) {
        try writer.writeAll(info.repeat_state);
    } else if (std.mem.eql(u8, arg, "shuffle")) {
        if (info.shuffle_state) {
            try writer.writeAll("on");
        } else {
            try writer.writeAll("off");
        }
    } else if (std.mem.eql(u8, arg, "progress")) {
        try writeTime(writer, info.progress_ms);
    } else if (std.mem.eql(u8, arg, "album")) {
        if (info.item) |track| {
            try writer.writeAll(track.album.name);
        } else {
            try writer.writeAll("null");
        }
    } else if (std.mem.eql(u8, arg, "duration")) {
        if (info.item) |track| {
            try writeTime(writer, track.duration_ms);
        } else {
            try writer.writeAll("null");
        }
    } else if (std.mem.eql(u8, arg, "url")) {
        if (info.item) |track| {
            try writer.writeAll(track.external_urls.spotify);
        } else {
            try writer.writeAll("null");
        }
    } else if (std.mem.eql(u8, arg, "album_url")) {
        if (info.item) |track| {
            try writer.writeAll(track.album.external_urls.spotify);
        } else {
            try writer.writeAll("null");
        }
    } else if (std.mem.startsWith(u8, arg, "bar")) {
        const bar_len = blk: {
            const idx = std.mem.indexOfScalar(u8, arg, ':') orelse {
                break :blk 50;
            };
            const len = std.fmt.parseUnsigned(u64, arg[idx + 1 ..], 10) catch |err| {
                std.log.err("Invalid bar length: {}", .{err});
                std.process.exit(1);
            };
            break :blk len;
        };

        if (info.item) |track| {
            const duration = track.duration_ms;
            const progress = info.progress_ms;
            const progress_len = (progress * bar_len) / duration;
            try writer.writeBytesNTimes("█", progress_len);
            try writer.writeByteNTimes(' ', bar_len - progress_len);
        }
    } else {
        std.log.err("Unknown format argument: {s}", .{arg});
        help.exec("print");
        std.process.exit(1);
    }
}

pub fn writeTime(writer: anytype, ms: u64) !void {
    const min = ms / std.time.ms_per_min;
    const s = (ms / std.time.ms_per_s) % std.time.s_per_min;
    try writer.print("{d}:{d:0>2}", .{ min, s });
}
