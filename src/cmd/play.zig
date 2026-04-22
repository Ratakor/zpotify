const std = @import("std");
const api = @import("zpotify");
const cmd = @import("../cmd.zig");
const help = cmd.help;

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
            .album => api.Album,
            .artist => api.Artist,
        };
    }

    fn NodeType(comptime query: Query) type {
        return struct {
            data: switch (query) {
                .track => api.Tracks(.saved),
                .playlist => api.Playlists,
                .album => api.Albums,
                .artist => api.Artists,
            },
            node: std.DoublyLinkedList.Node = .{},
        };
    }
};

var dmenu_cmd: []const u8 = undefined;

pub fn exec(ctx: *cmd.Context) !void {
    const query = if (ctx.args.next()) |value| blk: {
        break :blk std.meta.stringToEnum(Query, value) orelse {
            std.log.err("Invalid query type: '{s}'", .{value});
            try help.exec(ctx, "play");
            std.process.exit(1);
        };
    } else {
        std.log.info("Resuming playback", .{});
        try api.player.startPlayback(ctx.client, null, null);
        return;
    };

    const allocator = ctx.arena.allocator();

    // Checking $DMENU for backward compatibility
    dmenu_cmd = ctx.env_map.get("ZPOTIFY_DMENU") orelse ctx.env_map.get("DMENU") orelse "dmenu -i";

    switch (query) {
        .track => {
            const track = try getItemFromMenu(.track, ctx, allocator);
            try startPlayback(.track, ctx, allocator, track.uri);
            std.log.info("Playing track '{s}' from '{s}' by {s}", .{
                track.name,
                track.album.name,
                track.artists[0].name,
            });
        },
        .playlist => {
            const playlist = try getItemFromMenu(.playlist, ctx, allocator);
            try startPlayback(.playlist, ctx, allocator, playlist.uri);
            std.log.info("Playing playlist '{s}' by {s}", .{
                playlist.name,
                playlist.owner.display_name orelse playlist.owner.id,
            });
        },
        .album => {
            const album = try getItemFromMenu(.album, ctx, allocator);
            try startPlayback(.album, ctx, allocator, album.uri);
            std.log.info("Playing album '{s}' by {s}", .{
                album.name,
                album.artists[0].name,
            });
        },
        .artist => {
            const artist = try getItemFromMenu(.artist, ctx, allocator);
            try startPlayback(.artist, ctx, allocator, artist.uri);
            std.log.info("Playing popular songs by {s}", .{artist.name});
        },
    }
}

fn startPlayback(
    query: Query,
    ctx: *cmd.Context,
    allocator: std.mem.Allocator, // arena allocator
    uri: []const u8,
) !void {
    if (query == .track) out: {
        api.player.startPlayback(ctx.client, .{ .uris = &.{uri} }, null) catch |err| switch (err) {
            error.NoActiveDevice => break :out,
            else => return err,
        };
        return;
    } else out: {
        api.player.startPlayback(ctx.client, .{ .context_uri = uri }, null) catch |err| switch (err) {
            error.NoActiveDevice => break :out,
            else => return err,
        };
        return;
    }

    const devices = try api.player.getDevices(ctx.client);
    if (devices.len == 0) {
        std.log.err("No device found", .{});
        std.process.exit(1);
    }

    const id = blk: {
        if (devices.len == 1) {
            break :blk devices[0].id.?;
        }

        const result = try spawnMenu(ctx, dmenu_cmd, devices);
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
        try api.player.startPlayback(ctx.client, .{ .uris = &.{uri} }, id);
    } else {
        try api.player.startPlayback(ctx.client, .{ .context_uri = uri }, id);
    }
}

// this is what zig's polymorphism does to a mf
fn getItemFromMenu(
    comptime query: Query,
    ctx: *cmd.Context,
    allocator: std.mem.Allocator, // arena allocator
) !query.Type() {
    const Node = query.NodeType();
    const nullable = query == .playlist; // we should check for optional type instead

    var list: std.DoublyLinkedList = .{};
    list.prepend(blk: {
        const node = try allocator.create(Node);
        node.* = .{ .data = try switch (query) {
            .track => api.tracks.getUserTracks(ctx.client, limit, 0),
            .playlist => api.playlists.getCurrentUserPlaylists(ctx.client, limit, 0),
            .album => api.albums.getUserAlbums(ctx.client, limit, 0),
            .artist => api.users.getFollowedArtists(ctx.client, limit, null),
        } };
        break :blk &node.node;
    });
    var current = list.first.?;

    while (true) {
        const current_data = @as(*Node, @fieldParentPtr("node", current)).data;
        const result = try spawnMenu(ctx, dmenu_cmd, current_data.items);
        defer allocator.free(result);

        if (std.mem.eql(u8, "previous", result)) {
            current = current.prev orelse list.last.?;
        } else if (std.mem.eql(u8, "next", result)) {
            current = current.next orelse blk: {
                if (query == .artist) {
                    if (current_data.cursors.after) |after| {
                        const node = try allocator.create(Node);
                        node.* = .{ .data = try api.users.getFollowedArtists(ctx.client, limit, after) };
                        list.insertAfter(current, &node.node);
                        break :blk &node.node;
                    }
                } else {
                    if (current_data.next) |_| {
                        const offset = current_data.offset + limit;
                        const node = try allocator.create(Node);
                        node.* = .{ .data = try switch (query) {
                            .track => api.tracks.getUserTracks(ctx.client, limit, offset),
                            .playlist => api.playlists.getCurrentUserPlaylists(ctx.client, limit, offset),
                            .album => api.albums.getUserAlbums(ctx.client, limit, offset),
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

fn spawnMenu(ctx: *cmd.Context, command: []const u8, items: anytype) ![]const u8 {
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

    var child = try std.process.spawn(ctx.io, .{
        .argv = &.{ "sh", "-c", command },
        .stdout = .pipe,
        .stdin = .pipe,
    });

    var p2c_writer = child.stdin.?.writer(ctx.io, &common_buffer);
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
    child.stdin.?.close(ctx.io);

    switch (try child.wait(ctx.io)) {
        .exited => |status| if (status != 0) std.process.exit(1),
        else => std.process.exit(1),
    }

    var c2p_reader = child.stdout.?.reader(ctx.io, &common_buffer);
    const item = try c2p_reader.interface.takeDelimiterExclusive('\n');
    child.stdout.?.close(ctx.io);

    if (@hasField(T, "track") or @hasField(T, "album")) {
        if (std.mem.indexOfScalar(u8, item, '-')) |i| {
            return ctx.allocator.dupe(u8, item[i + 2 ..]);
        }
    }
    return ctx.allocator.dupe(u8, item);
}
