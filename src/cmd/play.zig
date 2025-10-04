const std = @import("std");
const api = @import("../api.zig");
const help = @import("../cmd.zig").help;

pub const description = "Play a track, playlist, album, or artist from your library";
pub const usage =
    \\Usage: zpotify play <track|playlist|album|artist>
    \\
    \\Description: Play a track, playlist, album, or artist from your library
    \\             If no arguments are provided, playback will be resumed for the current device
    \\             Change the $ZPOTIFY_DMENU environment variable to use a different menu program (default: dmenu -i)
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
            .album => api.SavedAlbum,
            .artist => api.Artist,
        };
    }

    fn NodeType(comptime query: Query) type {
        return struct {
            data: switch (query) {
                .track => api.Tracks(.saved),
                .playlist => api.Playlists,
                .album => api.Albums(.saved),
                .artist => api.Artists,
            },
            node: std.DoublyLinkedList.Node = .{},
        };
    }
};

var dmenu_cmd: []const u8 = undefined;

pub fn exec(
    client: *api.Client,
    child_allocator: std.mem.Allocator,
    arg: ?[]const u8,
) !void {
    const query = if (arg) |value| blk: {
        break :blk std.meta.stringToEnum(Query, value) orelse {
            std.log.err("Invalid query type: '{s}'", .{value});
            try help.exec("play");
            std.process.exit(1);
        };
    } else {
        std.log.info("Resuming playback", .{});
        try api.startPlayback(client, null, null);
        return;
    };

    var arena = std.heap.ArenaAllocator.init(child_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Checking $DMENU for backward compatibility
    dmenu_cmd = std.posix.getenv("ZPOTIFY_DMENU") orelse std.posix.getenv("DMENU") orelse "dmenu -i";

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
            std.log.info("Playing playlist '{s}' by {s}", .{
                playlist.name,
                playlist.owner.display_name orelse playlist.owner.id,
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
        try api.startPlayback(client, .{ .uris = &[_][]const u8{uri} }, id);
    } else {
        try api.startPlayback(client, .{ .context_uri = uri }, id);
    }
}

// this is what zig's polymorphism does to a mf
fn getItemFromMenu(
    comptime query: Query,
    client: *api.Client,
    allocator: std.mem.Allocator, // arena allocator
) !query.Type() {
    const Node = query.NodeType();
    const nullable = query == .playlist; // we should check for optional type instead

    var list: std.DoublyLinkedList = .{};
    list.prepend(blk: {
        const node = try allocator.create(Node);
        node.* = .{ .data = try switch (query) {
            .track => api.getUserTracks(client, limit, 0),
            .playlist => api.getUserPlaylists(client, limit, 0),
            .album => api.getUserAlbums(client, limit, 0),
            .artist => api.getUserArtists(client, limit, null),
        } };
        break :blk &node.node;
    });
    var current = list.first.?;

    while (true) {
        const current_data = @as(*Node, @fieldParentPtr("node", current)).data;
        const result = try spawnMenu(allocator, dmenu_cmd, current_data.items);
        defer allocator.free(result);

        if (std.mem.eql(u8, "previous", result)) {
            current = current.prev orelse list.last.?;
        } else if (std.mem.eql(u8, "next", result)) {
            current = current.next orelse blk: {
                if (query == .artist) {
                    if (current_data.cursors.after) |after| {
                        const node = try allocator.create(Node);
                        node.* = .{ .data = try api.getUserArtists(client, limit, after) };
                        list.insertAfter(current, &node.node);
                        break :blk &node.node;
                    }
                } else {
                    if (current_data.next) |_| {
                        const offset = current_data.offset + limit;
                        const node = try allocator.create(Node);
                        node.* = .{ .data = try switch (query) {
                            .track => api.getUserTracks(client, limit, offset),
                            .playlist => api.getUserPlaylists(client, limit, offset),
                            .album => api.getUserAlbums(client, limit, offset),
                            .artist => unreachable,
                        } };
                        list.insertAfter(current, &node.node);
                        break :blk &node.node;
                    }
                }
                break :blk list.first.?;
            };
        } else {
            for (current_data.items) |_item| {
                const item = switch (query) {
                    .track => _item.track,
                    .album => _item.album,
                    else => _item,
                };
                // This is mainly because playlist can be null with a search
                // query and since play share the same structure there is this
                // ugly code here
                if (nullable) {
                    if (item) |it| {
                        if (std.mem.eql(u8, it.name, result)) {
                            return it;
                        }
                    }
                } else {
                    if (std.mem.eql(u8, item.name, result)) {
                        return item;
                    }
                }
            }
            std.log.err("Invalid selection: '{s}'", .{result});
            std.process.exit(1);
        }
    }
}

fn spawnMenu(allocator: std.mem.Allocator, cmd: []const u8, items: anytype) ![]const u8 {
    const T, const nullable = blk: {
        const T = @typeInfo(@TypeOf(items)).pointer.child;
        const ti = @typeInfo(T);
        break :blk switch (ti) {
            .optional => |opt| .{ opt.child, true },
            else => .{ T, false },
        };
    };

    // buffer used for writing to the child process then reading from it
    var common_buffer: [4096]u8 = undefined;

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

    var p2c_writer = std.fs.File.writer(.{ .handle = p2c_pipe[1] }, &common_buffer);
    const writer = &p2c_writer.interface;
    for (items) |item| {
        if (@hasField(T, "track")) {
            try writer.print("{s} - {s}\n", .{ item.track.artists[0].name, item.track.name });
        } else if (@hasField(T, "album")) {
            try writer.print("{s} - {s}\n", .{ item.album.artists[0].name, item.album.name });
        } else if (nullable) {
            if (item) |it| {
                try writer.print("{s}\n", .{it.name});
            }
        } else {
            try writer.print("{s}\n", .{item.name});
        }
    }
    if (T != api.Device) {
        try writer.writeAll("previous\nnext");
    }
    try writer.flush();
    std.posix.close(p2c_pipe[1]);

    const wpr = std.posix.waitpid(fork_pid, 0);
    if (std.posix.W.EXITSTATUS(wpr.status) != 0) {
        std.posix.close(c2p_pipe[0]);
        std.process.exit(1);
    }

    var c2p_reader = std.fs.File.reader(.{ .handle = c2p_pipe[0] }, &common_buffer);
    const item = try c2p_reader.interface.takeDelimiterExclusive('\n');
    std.posix.close(c2p_pipe[0]);

    if (@hasField(T, "track") or @hasField(T, "album")) {
        if (std.mem.indexOfScalar(u8, item, '-')) |i| {
            return allocator.dupe(u8, item[i + 2 ..]);
        }
    }

    return allocator.dupe(u8, item);
}
