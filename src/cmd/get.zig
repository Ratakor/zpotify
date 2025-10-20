const std = @import("std");
const api = @import("../api.zig");
const help = @import("../cmd.zig").help;

pub const description = "Get data from Spotify";
// TODO: description, key looks ugly
pub const usage = blk: {
    var str: []const u8 =
        \\Usage: zpotify get [--raw] <Key>
        \\
        \\Description:
        \\
        \\Key:
        \\
    ;
    for (std.enums.values(Key)) |key| {
        str = str ++ "\t" ++ @tagName(key) ++ "\n";
    }
    str = str ++ "\n";
    break :blk str;
};

// for playlists, tracks, albums, artists should we do mutliple calls to get all?
// yes or --max...
const Key = enum {
    playback,
    devices,
    playlists,
    tracks,
    albums,
    artists,
    // top_tracks,
    queue,
};

pub fn exec(client: *api.Client, args: *std.process.ArgIterator) !void {
    // TODO: kinda depends on #5
    var raw = false;
    var key_str: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--raw")) {
            raw = true;
        } else {
            if (key_str != null) {
                std.log.err("Unexpected argument '{s}' found", .{arg});
                try help.exec("get");
                std.process.exit(1);
            }
            key_str = arg;
        }
    }

    const key = if (key_str) |key| std.meta.stringToEnum(Key, key) orelse {
        std.log.err("Invalid key: '{s}'", .{key});
        try help.exec("get");
        std.process.exit(1);
    } else {
        std.log.err("Missing key", .{});
        try help.exec("get");
        std.process.exit(1);
    };

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    switch (key) {
        .playback => {
            const playback = try api.getPlaybackState(client);
            try stdout.print("{f}\n", .{std.json.fmt(playback, .{})});
        },
        .devices => {
            const devices = try api.getDevices(client);
            try stdout.print("{f}\n", .{std.json.fmt(devices, .{})});
        },
        .playlists => {
            const playlists = try api.getUserPlaylists(client, 50, 0);
            try stdout.print("{f}\n", .{std.json.fmt(playlists, .{})});
        },
        .tracks => {
            const tracks = try api.getUserTracks(client, 50, 0);
            try stdout.print("{f}\n", .{std.json.fmt(tracks, .{})});
        },
        .albums => {
            const albums = try api.getUserAlbums(client, 50, 0);
            try stdout.print("{f}\n", .{std.json.fmt(albums, .{})});
        },
        .artists => {
            const artists = try api.getUserArtists(client, 50, null);
            try stdout.print("{f}\n", .{std.json.fmt(artists, .{})});
        },
        .queue => {
            const queue = try api.getQueue(client);
            try stdout.print("{f}\n", .{std.json.fmt(queue, .{})});
        },
    }

    try stdout.flush();
}
