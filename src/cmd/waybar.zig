const std = @import("std");
const axe = @import("../main.zig").axe;
const api = @import("zpotify");
const writeTime = @import("../cmd.zig").print.writeTime;

pub const description = "Display infos about the current playback for a waybar module";
pub const usage =
    \\Usage: zpotify waybar
    \\
    \\Description: Display infos about the current playback every second for use in a waybar module
    \\
    \\Return format:
    \\{
    \\    "text": "{state:/} {artist} - {title}",
    \\    "tooltip": "Track: {title}\nArtist(s): {artists}\nAlbum: {album}\nDevice: {device}\nProgress: {bar:40} {progress} / {duration}\nShuffle: {shuffle}\t\tVolume: {volume}%\t\tRepeat: {repeat}"
    \\}
    \\
    \\Configuration:
    \\"custom/zpotify": {
    \\    "exec": "zpotify waybar",
    \\    "return-type": "json",
    \\    "tooltip": true,
    \\    "on-click": "zpotify pause >/dev/null"
    \\}
    \\
;

const bar_len = 40;

pub fn exec(client: *api.Client, child_allocator: std.mem.Allocator) !void {
    // buffering not needed & disabled on purpose
    var stdout_writer = std.fs.File.stdout().writer(&.{});
    const stdout = &stdout_writer.interface;

    // arena is reset on each loop iteration, there is no need to call deinit or free
    var arena = std.heap.ArenaAllocator.init(child_allocator);
    const allocator = arena.allocator();

    // disable colored logs
    axe.updateTtyConfig(.never);

    while (true) {
        defer std.Thread.sleep(std.time.ns_per_s);
        defer stdout.writeAll("\n") catch {};

        const info = api.player.getPlaybackStateOwned(client, allocator) catch |err| switch (err) {
            error.PlaybackNotAvailable => continue,
            else => {
                std.log.scoped(.zpotify).err("{t}", .{err});
                continue;
            },
        };
        defer _ = arena.reset(.retain_capacity);

        const device = info.device orelse continue;
        const track = info.item orelse continue;

        const text = blk: {
            var builder: std.Io.Writer.Allocating = .init(allocator);
            const writer = &builder.writer;
            try writer.writeAll(if (info.is_playing) "" else "");
            try writer.writeAll(" ");
            try writer.writeAll(track.artists[0].name);
            try writer.writeAll(" - ");
            try writer.writeAll(track.name);
            break :blk try std.mem.replaceOwned(u8, allocator, writer.buffered(), "&", "&amp;");
        };

        const tooltip = blk: {
            var builder: std.Io.Writer.Allocating = .init(allocator);
            const writer = &builder.writer;
            try writer.writeAll("Track: ");
            try writer.writeAll(track.name);
            if (track.artists.len == 1) {
                try writer.writeAll("\nArtist: ");
                try writer.writeAll(track.artists[0].name);
            } else {
                try writer.writeAll("\nArtists: ");
                try writer.writeAll(track.artists[0].name);
                for (track.artists[1..]) |artist| {
                    try writer.writeAll(", ");
                    try writer.writeAll(artist.name);
                }
            }
            try writer.writeAll("\nAlbum: ");
            try writer.writeAll(track.album.name);
            try writer.writeAll("\nDevice: ");
            try writer.writeAll(device.name);
            try writer.writeAll("\nProgress: ");
            const progress_len = (info.progress_ms * bar_len) / track.duration_ms;
            try writer.splatBytesAll("█", progress_len);
            try writer.splatByteAll(' ', bar_len - progress_len + 1);
            try writeTime(writer, info.progress_ms);
            try writer.writeAll(" / ");
            try writeTime(writer, track.duration_ms);
            try writer.writeAll("\nShuffle: ");
            try writer.writeAll(if (info.shuffle_state) "on" else "off");
            try writer.writeAll("\t\tVolume: ");
            try writer.print("{?d}%\t", .{device.volume_percent});
            try writer.splatByteAll(' ', 14 - info.repeat_state.len);
            try writer.writeAll("Repeat: ");
            try writer.writeAll(info.repeat_state);
            break :blk try std.mem.replaceOwned(u8, allocator, writer.buffered(), "&", "&amp;");
        };

        try stdout.print("{f}", .{std.json.fmt(.{ .text = text, .tooltip = tooltip }, .{})});
    }
}
