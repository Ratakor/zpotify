const std = @import("std");
const api = @import("../api.zig");
const help = @import("../cmd.zig").help;

pub const usage =
    \\Usage: {s} play [track|playlist|album|artist] [query]
    \\
    \\Description: Play a track, playlist, album, or artist
    \\             If no arguments are provided, playback will be resumed for the current device
    \\
;

const QueryType = enum { track, playlist, album, artist };

pub fn exec(client: *api.Client, args: *std.process.ArgIterator) !void {
    const query_type: QueryType = if (args.next()) |arg| blk: {
        if (std.mem.eql(u8, arg, "track")) {
            break :blk .track;
        } else if (std.mem.eql(u8, arg, "playlist")) {
            break :blk .playlist;
        } else if (std.mem.eql(u8, arg, "album")) {
            break :blk .album;
        } else if (std.mem.eql(u8, arg, "artist")) {
            break :blk .artist;
        } else {
            std.log.err("Invalid query type: '{s}'", .{arg});
            help.exec("play");
            std.process.exit(1);
        }
    } else {
        std.log.info("Resuming playback", .{});
        api.startPlayback(client, null, null) catch |err| switch (err) {
            error.NotFound => std.process.exit(1),
            else => return err,
        };
        return;
    };
    const query = args.next() orelse {
        std.log.err("Missing query", .{});
        help.exec("play");
        std.process.exit(1);
    };

    const search_result = api.search(client, query, @tagName(query_type), 1, 0) catch |err| switch (err) {
        error.NotPlaying => std.process.exit(1),
        else => return err,
    };
    defer search_result.deinit();

    const uri, const name = switch (query_type) {
        .track => getInfos(search_result.value.tracks),
        .playlist => getInfos(search_result.value.playlists),
        .album => getInfos(search_result.value.albums),
        .artist => getInfos(search_result.value.artists),
    } orelse {
        std.log.err("No {s} found for query: '{s}'", .{ @tagName(query_type), query });
        std.process.exit(1);
    };

    if (query_type == .track) {
        api.startPlayback(client, null, &[_][]const u8{uri}) catch |err| switch (err) {
            error.NotFound => std.process.exit(1),
            else => return err,
        };
    } else {
        api.startPlayback(client, uri, null) catch |err| switch (err) {
            error.NotFound => std.process.exit(1),
            else => return err,
        };
    }

    if (query_type == .artist) {
        std.log.info("Playing popular songs by {s}", .{name});
    } else {
        std.log.info("Playing {s}: {s}", .{ @tagName(query_type), name });
    }
}

fn getInfos(value: anytype) ?struct { []const u8, []const u8 } {
    if (value) |v| {
        if (v.items.len > 0) {
            return .{ v.items[0].uri, v.items[0].name };
        }
    }
    return null;
}
