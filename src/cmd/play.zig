const std = @import("std");
const api = @import("../api.zig");
const help = @import("../cmd.zig").help;

pub const usage =
    \\Usage: {s} play [track|playlist|album|artist]
    \\
    \\Description: Play a track, playlist, album, or artist from your library
    \\             If no arguments are provided, playback will be resumed for the current device
    \\             Change the $DMENU environment variable to use a different menu program (default: dmenu -i)
    \\
;

const limit = 50;

const Query = enum {
    track,
    playlist,
    album,
    artist,

    fn Type(comptime query: Query) type {
        return switch (query) {
            .track => api.Track,
            .playlist => api.Playlist,
            .album => api.Album,
            .artist => api.Artist,
        };
    }

    fn ListType(comptime query: Query) type {
        return switch (query) {
            .track => api.Tracks(true),
            .playlist => api.Playlists,
            .album => api.Albums(true),
            .artist => api.Artists,
        };
    }
};

pub fn exec(
    client: *api.Client,
    child_allocator: std.mem.Allocator,
    arg: ?[]const u8,
) !void {
    const query = if (arg) |value| blk: {
        break :blk std.meta.stringToEnum(Query, value) orelse {
            std.log.err("Invalid query type: '{s}'", .{value});
            help.exec("play");
            std.process.exit(1);
        };
    } else {
        std.log.info("Resuming playback", .{});
        api.startPlayback(client, null, null) catch |err| switch (err) {
            error.NoActiveDevice => std.process.exit(1),
            else => return err,
        };
        return;
    };

    var arena = std.heap.ArenaAllocator.init(child_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    switch (query) {
        .track => {
            const track = try getItemFromMenu(.track, client, allocator);
            try startPlayback(.track, client, allocator, track.uri);
            std.log.info("Playing track '{s}' from '{s}' by {s}", .{
                track.name,
                track.album.name,
                track.artists[0].name,
            });
        },
        .playlist => {
            const playlist = try getItemFromMenu(.playlist, client, allocator);
            try startPlayback(.playlist, client, allocator, playlist.uri);
            std.log.info("Playing playlist '{s}' by {?s}", .{
                playlist.name,
                playlist.owner.display_name,
            });
        },
        .album => {
            const album = try getItemFromMenu(.album, client, allocator);
            try startPlayback(.album, client, allocator, album.uri);
            std.log.info("Playing album '{s}' by {s}", .{
                album.name,
                album.artists[0].name,
            });
        },
        .artist => {
            const artist = try getItemFromMenu(.artist, client, allocator);
            try startPlayback(.artist, client, allocator, artist.uri);
            std.log.info("Playing popular songs by {s}", .{artist.name});
        },
    }
}

fn startPlayback(
    query: Query,
    client: *api.Client,
    allocator: std.mem.Allocator,
    uri: []const u8,
) !void {
    if (query == .track) out: {
        api.startPlayback(client, .{ .uris = &[_][]const u8{uri} }, null) catch |err| switch (err) {
            error.NoActiveDevice => break :out,
            else => return err,
        };
        return;
    } else out: {
        api.startPlayback(client, .{ .context_uri = uri }, null) catch |err| switch (err) {
            error.NoActiveDevice => break :out,
            else => return err,
        };
        return;
    }

    const devices = try api.getDevices(client);
    if (devices.len == 0) {
        std.log.err("No device found", .{});
        std.process.exit(1);
    }

    const id = blk: {
        if (devices.len == 1) {
            break :blk devices[0].id.?;
        }

        const dmenu_cmd = std.posix.getenv("DMENU") orelse "dmenu -i";
        const result = try spawnMenu(allocator, dmenu_cmd, devices);
        defer allocator.free(result);

        for (devices) |device| {
            if (std.mem.eql(u8, device.name, result)) {
                break :blk device.id.?;
            }
        }
        std.log.err("Invalid selection: '{s}'", .{result});
        std.process.exit(1);
    };

    if (query == .track) {
        api.startPlayback(client, .{ .uris = &[_][]const u8{uri} }, id) catch |err| switch (err) {
            error.NoActiveDevice => std.process.exit(1),
            else => return err,
        };
    } else {
        api.startPlayback(client, .{ .context_uri = uri }, id) catch |err| switch (err) {
            error.NoActiveDevice => std.process.exit(1),
            else => return err,
        };
    }
}

// this is what zig's polymorphism does to a mf
fn getItemFromMenu(
    comptime query: Query,
    client: *api.Client,
    allocator: std.mem.Allocator, // arena allocator
) !query.Type() {
    const dmenu_cmd = std.posix.getenv("DMENU") orelse "dmenu -i";

    const List = std.DoublyLinkedList(query.ListType());
    var list: List = .{};
    list.prepend(blk: {
        const node = try allocator.create(List.Node);
        node.* = .{ .data = try switch (query) {
            .track => api.getUserTracks(client, limit, 0),
            .playlist => api.getUserPlaylists(client, limit, 0),
            .album => api.getUserAlbums(client, limit, 0),
            .artist => api.getUserArtists(client, limit, null),
        } };
        break :blk node;
    });
    var current = list.first.?;

    while (true) {
        const result = try spawnMenu(allocator, dmenu_cmd, current.data.items);
        defer allocator.free(result);

        if (std.mem.eql(u8, "previous", result)) {
            current = current.prev orelse list.last.?;
        } else if (std.mem.eql(u8, "next", result)) {
            current = current.next orelse blk: {
                if (query == .artist) {
                    if (current.data.cursors.after) |after| {
                        const node = try allocator.create(List.Node);
                        node.* = .{ .data = try api.getUserArtists(client, limit, after) };
                        list.insertAfter(current, node);
                        break :blk node;
                    }
                } else {
                    if (current.data.next) |_| {
                        const offset = current.data.offset + limit;
                        const node = try allocator.create(List.Node);
                        node.* = .{ .data = try switch (query) {
                            .track => api.getUserTracks(client, limit, offset),
                            .playlist => api.getUserPlaylists(client, limit, offset),
                            .album => api.getUserAlbums(client, limit, offset),
                            .artist => unreachable,
                        } };
                        list.insertAfter(current, node);
                        break :blk node;
                    }
                }
                break :blk list.first.?;
            };
        } else {
            for (current.data.items) |_item| {
                const item = switch (query) {
                    .track => _item.track,
                    .playlist => _item,
                    .album => _item.album,
                    .artist => _item,
                };
                if (std.mem.eql(u8, item.name, result)) {
                    return item;
                }
            }
            std.log.err("Invalid selection: '{s}'", .{result});
            std.process.exit(1);
        }
    }
}

fn spawnMenu(allocator: std.mem.Allocator, cmd: []const u8, items: anytype) ![]const u8 {
    // pipe[0] = read, pipe[1] = write
    const p2c_pipe = try std.posix.pipe(); // parent -> child
    const c2p_pipe = try std.posix.pipe(); // child -> parent

    const fork_pid = try std.posix.fork();
    if (fork_pid == 0) {
        std.posix.close(p2c_pipe[1]);
        std.posix.close(c2p_pipe[0]);

        try std.posix.dup2(p2c_pipe[0], std.posix.STDIN_FILENO);
        std.posix.close(p2c_pipe[0]);
        try std.posix.dup2(c2p_pipe[1], std.posix.STDOUT_FILENO);
        std.posix.close(c2p_pipe[1]);

        std.process.execv(allocator, &[_][]const u8{ "sh", "-c", cmd }) catch unreachable;
    }

    std.posix.close(p2c_pipe[0]);
    std.posix.close(c2p_pipe[1]);

    const writer = std.fs.File.writer(.{ .handle = p2c_pipe[1] });
    for (items) |item| {
        if (@hasField(@TypeOf(item), "track")) {
            try writer.print("{s} - {s}\n", .{ item.track.artists[0].name, item.track.name });
        } else if (@hasField(@TypeOf(item), "album")) {
            try writer.print("{s} - {s}\n", .{ item.album.artists[0].name, item.album.name });
        } else {
            try writer.print("{s}\n", .{item.name});
        }
    }
    if (@TypeOf(items[0]) != api.Device) {
        try writer.writeAll("previous\nnext");
    }
    std.posix.close(p2c_pipe[1]);

    const wpr = std.posix.waitpid(fork_pid, 0);
    if (std.posix.W.EXITSTATUS(wpr.status) != 0) {
        std.posix.close(c2p_pipe[0]);
        std.process.exit(1);
    }

    const reader = std.fs.File.reader(.{ .handle = c2p_pipe[0] });
    var buf: [256]u8 = undefined;
    var size = try reader.readAll(&buf);
    std.posix.close(c2p_pipe[0]);

    if (size > 0 and buf[size - 1] == '\n') {
        size -= 1;
    }

    if (@hasField(@TypeOf(items[0]), "track") or @hasField(@TypeOf(items[0]), "album")) {
        if (std.mem.indexOfScalar(u8, buf[0..size], '-')) |i| {
            return allocator.dupe(u8, buf[i + 2 .. size]);
        }
    }

    return allocator.dupe(u8, buf[0..size]);
}
