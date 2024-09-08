const std = @import("std");
const api = @import("../api.zig");
const writeTime = @import("../cmd.zig").print.writeTime;

pub const usage =
    \\Usage: {s} waybar
    \\
    \\Description: Display infos about the current playback every second for use in a waybar module
    \\
    \\Return format:
    \\{{
    \\    "text": "{{state:/}} {{artist}} - {{title}}",
    \\    "tooltip": "Track: {{title}}\nArtist(s): {{artists}}\nAlbum: {{album}}\nDevice: {{device}}\nProgress: {{bar:40}} {{progress}} / {{duration}}\nShuffle: {{shuffle}}\t\tVolume: {{volume}}%\t\tRepeat: {{repeat}}"
    \\}}
    \\
;

const bar_len = 40;

pub fn exec(client: *api.Client, allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout);
    const writer = bw.writer();

    while (true) {
        defer std.time.sleep(std.time.ns_per_s);

        const playback_state = api.getPlaybackState(client) catch |err| switch (err) {
            error.NotPlaying => continue,
            else => {
                std.log.err("Failed to get playback state: {}\n", .{err});
                continue;
            },
        };
        defer playback_state.deinit();
        const info = playback_state.value;
        const device = info.device orelse continue;
        const track = info.item orelse continue;

        const text = blk: {
            var builder = std.ArrayList(u8).init(allocator);
            defer builder.deinit();
            try builder.appendSlice(if (info.is_playing) "" else "");
            try builder.append(' ');
            try builder.appendSlice(track.artists[0].name);
            try builder.appendSlice(" - ");
            try builder.appendSlice(track.name);
            break :blk try std.mem.replaceOwned(u8, allocator, builder.items, "&", "&amp;");
        };
        defer allocator.free(text);

        const tooltip = blk: {
            var builder = std.ArrayList(u8).init(allocator);
            defer builder.deinit();
            const builder_writer = builder.writer();
            try builder.appendSlice("Track: ");
            try builder.appendSlice(track.name);
            try builder.appendSlice("\nArtist(s): ");
            try builder.appendSlice(track.artists[0].name);
            try builder.appendSlice("\nAlbum: ");
            try builder.appendSlice(track.album.name);
            try builder.appendSlice("\nDevice: ");
            try builder.appendSlice(device.name);
            try builder.appendSlice("\nProgress: ");
            const progress_len = (info.progress_ms * bar_len) / track.duration_ms;
            try builder_writer.writeBytesNTimes("█", progress_len);
            try builder_writer.writeByteNTimes(' ', bar_len - progress_len + 1);
            try writeTime(builder_writer, info.progress_ms);
            try builder.appendSlice(" / ");
            try writeTime(builder_writer, track.duration_ms);
            try builder.appendSlice("\nShuffle: ");
            try builder.appendSlice(if (info.shuffle_state) "on" else "off");
            try builder.appendSlice("\t\tVolume: ");
            try builder_writer.print("{?d}%\t", .{device.volume_percent});
            try builder_writer.writeByteNTimes(' ', 14 - info.repeat_state.len);
            try builder.appendSlice("Repeat: ");
            try builder.appendSlice(info.repeat_state);
            break :blk try std.mem.replaceOwned(u8, allocator, builder.items, "&", "&amp;");
        };
        defer allocator.free(tooltip);

        try std.json.stringify(.{ .text = text, .tooltip = tooltip }, .{}, writer);
        try bw.flush();
    }
}
