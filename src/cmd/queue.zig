const std = @import("std");
const api = @import("../api.zig");

pub const usage =
    \\Usage: {s} queue
    \\
    \\Description: Display tracks in the queue
    \\
;

fn printTrack(writer: anytype, track: api.Track) !void {
    try writer.print("{s} by ", .{track.name});
    for (track.artists, 0..) |artist, i| {
        if (i > 0) {
            try writer.writeAll(", ");
        }
        try writer.writeAll(artist.name);
    }
    try writer.writeAll("\n");
}

pub fn exec(client: *api.Client) !void {
    const queue = try api.getQueue(client);

    const stdout = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout);
    const writer = bw.writer();

    if (queue.currently_playing) |track| {
        try writer.writeAll("Currently playing: ");
        try printTrack(writer, track);
    }

    if (queue.queue.len == 0) {
        try writer.writeAll("Queue is empty\n");
        try bw.flush();
        return;
    }

    try writer.writeAll("Queue:\n");
    for (queue.queue, 1..) |track, i| {
        try writer.print("  Track {d}: ", .{i});
        try printTrack(writer, track);
    }

    try bw.flush();
}
