const std = @import("std");
const api = @import("../api.zig");

pub const usage =
    \\Usage: zpotify queue
    \\
    \\Description: Display tracks in the queue
    \\
;

fn printTrack(writer: *std.Io.Writer, track: api.Track) !void {
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

    var stdout_buffer: [4096]u8 = undefined;
    const stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    if (queue.currently_playing) |track| {
        try stdout.writeAll("Currently playing: ");
        try printTrack(stdout, track);
    }

    if (queue.queue.len == 0) {
        try stdout.writeAll("Queue is empty\n");
        try stdout.flush();
        return;
    }

    try stdout.writeAll("Queue:\n");
    for (queue.queue, 1..) |track, i| {
        try stdout.print("  Track {d}: ", .{i});
        try printTrack(stdout, track);
    }

    try stdout.flush();
}
