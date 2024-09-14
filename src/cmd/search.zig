const std = @import("std");
const spoon = @import("spoon");
const api = @import("../api.zig");
const ui = @import("../ui.zig");
const help = @import("../cmd.zig").help;

// this is allocation fest
// TODO: add number in ui like in vim?
// TODO: add a way to display errors e.g. no active device

pub const usage =
    \\Usage: {s} search [track|artist|album|playlist] [query]...
    \\
    \\Description: Search a track, playlist, album, or artist with a TUI
    \\
    // TODO
    // \\Commands:
    // \\  q    Quit
    // \\
;

const Kind = enum { track, artist, album, playlist };
const limit_max = 50;
const limit = 10;
var current_table: *Table = undefined;

pub fn exec(
    client: *api.Client,
    child_allocator: std.mem.Allocator,
    args: *std.process.ArgIterator,
) !void {
    const kind = if (args.next()) |arg| blk: {
        break :blk std.meta.stringToEnum(Kind, arg) orelse {
            std.log.err("Invalid query type: '{s}'", .{arg});
            help.exec("search");
            std.process.exit(1);
        };
    } else {
        std.log.err("Missing query type", .{});
        help.exec("search");
        std.process.exit(1);
    };

    var arena = std.heap.ArenaAllocator.init(child_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const query = blk: {
        var builder = std.ArrayList([]const u8).init(allocator);
        defer builder.deinit();
        while (args.next()) |arg| {
            try builder.append(arg);
        }
        if (builder.items.len == 0) {
            std.log.err("Missing query", .{});
            help.exec("search");
            std.process.exit(1);
        }
        break :blk try std.mem.join(allocator, " ", builder.items);
    };
    const title = try std.fmt.allocPrint(allocator, "zpotify: search {s} '{s}'", .{
        @tagName(kind),
        query,
    });
    current_table = try Table.init(client, allocator, query, kind, title);

    try ui.term.init(.{});
    defer ui.term.deinit() catch {};

    try std.posix.sigaction(std.posix.SIG.WINCH, &std.posix.Sigaction{
        .handler = .{ .handler = handleSigWinch },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    }, null);

    try ui.term.uncook(.{});
    try ui.term.fetchSize();
    try render();
    try loop();
}

fn loop() !void {
    var fds: [1]std.posix.pollfd = undefined;
    fds[0] = .{
        .fd = ui.term.tty.?,
        .events = std.posix.POLL.IN,
        .revents = undefined,
    };
    var buf: [16]u8 = undefined;
    while (true) {
        _ = try std.posix.poll(&fds, -1);

        const read = try ui.term.readInput(&buf);
        var it = spoon.inputParser(buf[0..read]);
        // TODO: ui.term.height - 5 can be less than 0 here
        while (it.next()) |in| {
            if (in.eqlDescription("escape") or in.eqlDescription("q")) {
                return;
            } else if (in.eqlDescription("arrow-down") or in.eqlDescription("j")) {
                if (current_table.selected < current_table.len() - 1) {
                    current_table.selected += 1;
                    if (current_table.selected - current_table.start >= ui.term.height - 5) {
                        current_table.start += 1;
                    }
                    try render();
                } else if (try current_table.fetchNext()) {
                    try render();
                }
            } else if (in.eqlDescription("arrow-up") or in.eqlDescription("k")) {
                current_table.selected -|= 1;
                if (current_table.selected < current_table.start) {
                    current_table.start -|= 1;
                }
                try render();
            } else if (in.eqlDescription("arrow-right") or in.eqlDescription("l")) {
                current_table = try current_table.nextTable() orelse {
                    // current_table is a track -> play it
                    try current_table.play();
                    continue;
                };
                current_table.selected = 0;
                current_table.start = 0;
                try render();
            } else if (in.eqlDescription("arrow-left") or in.eqlDescription("h")) {
                current_table = current_table.prevTable() orelse continue;
                try render();
            } else if (in.eqlDescription("G")) {
                current_table.selected = current_table.len() - 1;
                current_table.start = current_table.len() -| (ui.term.height - 5);
                try render();
            } else if (in.eqlDescription("g")) {
                current_table.selected = 0;
                current_table.start = 0;
                try render();
            } else if (in.eqlDescription("d") or in.eqlDescription("page-down")) {
                if (current_table.selected + limit < current_table.len() - 1 or
                    try current_table.fetchNext())
                {
                    current_table.selected += limit;
                    if (current_table.selected - current_table.start >= ui.term.height - 5) {
                        // std.log.debug("start: {d}, selected: {d} term.height {d}, selected row {d}", .{
                        //     current_table.start,
                        //     current_table.selected,
                        //     ui.term.height,
                        // });
                        // TODO += @min(limit, ???)
                        current_table.start += limit;
                        // current_table.start = current_table.selected - (ui.term.height - 5);
                        // if (self.selected - term.height - start
                        // current_table.start += 1 + current_table.selected - (ui.term.height - 5);
                    }
                    try render();
                }
            } else if (in.eqlDescription("u") or in.eqlDescription("page-up")) {
                current_table.selected -|= limit;
                if (current_table.selected < current_table.start) {
                    current_table.start = current_table.selected;
                }
                try render();
            } else if (in.eqlDescription("enter")) {
                current_table.play() catch |err| switch (err) {
                    error.NoActiveDevice => {}, // TODO: display error
                    else => return err,
                };
                return;
            } else if (in.eqlDescription("p")) {
                current_table.play() catch |err| switch (err) {
                    error.NoActiveDevice => {}, // TODO: display error
                    else => return err,
                };
            } else if (in.eqlDescription("s")) {
                // TODO: save
            } else if (in.eqlDescription("-") or in.eqlDescription("_")) {
                // TODO: vol -|= 10
            } else if (in.eqlDescription("+") or in.eqlDescription("=")) {
                // TODO: if (vol <= 90) vol += 10 else vol = 100
            } else if (in.eqlDescription("?")) {
                // TODO: help?
            } else if (in.eqlDescription("/")) {
                // TODO: search and reset
                // ask for kind and query
                // if kind is wrong assume it's the same as before and that it's part of the query
            }
        }
    }
}

// TODO: in ui.zig?
fn render() !void {
    var rc = try ui.term.getRenderContext();
    defer rc.done() catch {};

    try rc.clear();

    if (ui.term.width < 40 or ui.term.height < 10) {
        try rc.setAttribute(.{ .fg = .red, .bold = true });
        try rc.writeAllWrapping("Terminal too small!");
        return;
    }

    try drawHeader(&rc);
    try current_table.draw(&rc, 1);
    try drawFooter(&rc);
}

fn drawHeader(rc: *spoon.Term.RenderContext) !void {
    try rc.moveCursorTo(0, 0);
    try rc.setAttribute(.{ .fg = .green, .reverse = true, .bold = true });
    var rpw = rc.restrictedPaddingWriter(ui.term.width);
    try rpw.writer().writeAll(current_table.title);
    try rpw.pad();
}

fn drawFooter(rc: *spoon.Term.RenderContext) !void {
    try rc.moveCursorTo(ui.term.height - 2, 0);
    try rc.setAttribute(.{ .fg = .none, .bold = true });
    var rpw = rc.restrictedPaddingWriter(ui.term.width);
    try rpw.writer().print("Showing {d} of {d} {s}{s}", .{
        current_table.len(),
        current_table.total,
        current_table.getKind(),
        if (current_table.len() == 1) "" else "s",
    });
    try rpw.pad();
    try rc.moveCursorTo(ui.term.height - 1, 0);
    // try rc.setAttribute(.{ .fg = .cyan, .reverse = true });
    try rc.setAttribute(.{ .fg = .none, .bg = .cyan });
    rpw = rc.restrictedPaddingWriter(ui.term.width);
    try rpw.writer().writeAll("[q] Quit [h] Go back [j] Down [k] Up...");
    try rpw.pad();
}

fn handleSigWinch(_: c_int) callconv(.C) void {
    ui.term.fetchSize() catch {};
    render() catch {};
}

const Table = struct {
    list: union(enum) {
        tracks: std.ArrayListUnmanaged(api.Track),
        artists: std.ArrayListUnmanaged(api.Artist),
        albums: std.ArrayListUnmanaged(api.Album),
        playlists: std.ArrayListUnmanaged(api.Playlist),
    },
    client: *api.Client,
    allocator: std.mem.Allocator,
    title: []const u8,
    start: usize = 0,
    selected: usize = 0,

    total: usize = 0,
    has_next: bool,
    // fetchFn: fn (*Table) anyerror!bool = undefined,
    query: []const u8,

    prev: ?*Table = null,
    next: std.AutoHashMapUnmanaged(usize, *Table) = .{},

    pub fn init(
        client: *api.Client,
        allocator: std.mem.Allocator,
        query: []const u8,
        kind: Kind,
        title: []const u8,
    ) !*Table {
        var table = try allocator.create(Table);
        table.* = .{
            .list = switch (kind) {
                .track => .{ .tracks = .{} },
                .artist => .{ .artists = .{} },
                .album => .{ .albums = .{} },
                .playlist => .{ .playlists = .{} },
            },
            .client = client,
            .allocator = allocator,
            .query = query,
            .has_next = true,
            .title = title,
        };
        _ = try table.fetchNext();
        return table;
    }

    fn makeNextTable(prev: *Table, kind: Kind) !*Table {
        const table = try prev.allocator.create(Table);
        table.* = .{
            .list = switch (kind) {
                .track => .{ .tracks = .{} },
                .album => .{ .albums = .{} },
                else => unreachable,
            },
            .client = prev.client,
            .allocator = prev.allocator,
            .query = undefined,
            .has_next = false,
            .title = undefined,
            .prev = prev,
        };
        try prev.next.put(prev.allocator, prev.selected, table);
        return table;
    }

    pub fn fetchNext(self: *Table) !bool {
        if (!self.has_next) {
            return false;
        }

        const search_result = try api.search(
            self.client,
            self.query,
            self.getKind(),
            limit,
            self.len(),
        );

        switch (self.list) {
            .tracks => |*list| {
                try list.appendSlice(self.allocator, search_result.tracks.?.items);
                self.total = search_result.tracks.?.total;
                self.has_next = search_result.tracks.?.next != null;
            },
            .artists => |*list| {
                try list.appendSlice(self.allocator, search_result.artists.?.items);
                self.total = search_result.artists.?.total;
                self.has_next = search_result.artists.?.next != null;
            },
            .albums => |*list| {
                try list.appendSlice(self.allocator, search_result.albums.?.items);
                self.total = search_result.albums.?.total;
                self.has_next = search_result.albums.?.next != null;
            },
            .playlists => |*list| {
                try list.appendSlice(self.allocator, search_result.playlists.?.items);
                self.total = search_result.playlists.?.total;
                self.has_next = search_result.playlists.?.next != null;
            },
        }

        return true;
    }

    pub fn draw(self: Table, rc: *spoon.Term.RenderContext, first_row: usize) !void {
        const start = self.start;
        const end = @min(current_table.len(), current_table.start + ui.term.height - 5);
        const selected_row = first_row + self.selected - self.start;

        switch (self.list) {
            .tracks => |list| {
                const table: ui.TrackTable = .{ .items = list.items[start..end] };
                try table.draw(rc, first_row, selected_row);
            },
            .artists => |list| {
                const table: ui.ArtistTable = .{ .items = list.items[start..end] };
                try table.draw(rc, first_row, selected_row);
            },
            .albums => |list| {
                const table: ui.AlbumTable = .{ .items = list.items[start..end] };
                try table.draw(rc, first_row, selected_row);
            },
            .playlists => |list| {
                const table: ui.PlaylistTable = .{ .items = list.items[start..end] };
                try table.draw(rc, first_row, selected_row);
            },
        }
    }

    pub fn prevTable(self: Table) ?*Table {
        return self.prev;
    }

    pub fn nextTable(self: *Table) !?*Table {
        if (self.next.get(self.selected)) |table| {
            return table;
        }

        switch (self.list) {
            .tracks => return null,
            // TODO: too slow
            .artists => |list| {
                const artist = list.items[self.selected];
                const next_table = try self.makeNextTable(.album);
                next_table.title = try std.fmt.allocPrint(next_table.allocator, "zpotify: {s}", .{
                    artist.name,
                });

                while (true) {
                    const albums = try api.getArtistAlbums(
                        next_table.client,
                        artist.id,
                        limit_max,
                        next_table.len(),
                    );
                    try next_table.list.albums.appendSlice(next_table.allocator, albums.items);
                    next_table.total = albums.total;
                    if (albums.next == null) {
                        break;
                    }
                }

                return next_table;
            },
            .albums => |list| {
                const album = list.items[self.selected];
                const next_table = try self.makeNextTable(.track);
                next_table.title = blk: {
                    var builder = std.ArrayList(u8).init(next_table.allocator);
                    try builder.appendSlice("zpotify: ");
                    try builder.appendSlice(album.name);
                    try builder.appendSlice(" - ");
                    for (album.artists, 0..) |artist, i| {
                        if (i != 0) try builder.appendSlice(", ");
                        try builder.appendSlice(artist.name);
                    }
                    break :blk try builder.toOwnedSlice();
                };

                while (true) {
                    const tracks = try api.getAlbumTracks(
                        next_table.client,
                        album.id,
                        limit_max,
                        next_table.len(),
                    );
                    try next_table.list.tracks.appendSlice(next_table.allocator, tracks.items);
                    next_table.total = tracks.total;
                    if (tracks.next == null) {
                        break;
                    }
                }
                for (next_table.list.tracks.items) |*track| {
                    track.album = album;
                }

                return next_table;
            },
            .playlists => |list| {
                const playlist = list.items[self.selected];
                const next_table = try self.makeNextTable(.track);
                next_table.title = try std.fmt.allocPrint(
                    next_table.allocator,
                    "zpotify: {s} - {s}",
                    .{ playlist.name, playlist.owner.display_name orelse playlist.owner.id },
                );

                // TODO: too slow
                while (true) {
                    const tracks = try api.getPlaylistTracks(
                        next_table.client,
                        playlist.id,
                        limit_max,
                        next_table.len(),
                    );
                    for (tracks.items) |item| {
                        try next_table.list.tracks.append(next_table.allocator, item.track);
                    }
                    next_table.total = tracks.total;
                    if (tracks.next == null) {
                        break;
                    }
                }

                return next_table;
            },
        }
    }

    pub fn play(self: Table) !void {
        switch (self.list) {
            .tracks => |list| {
                const uris = [_][]const u8{list.items[self.selected].uri};
                try api.startPlayback(self.client, .{ .uris = &uris }, null);
            },
            .artists => |list| {
                const uri = list.items[self.selected].uri;
                try api.startPlayback(self.client, .{ .context_uri = uri }, null);
            },
            .albums => |list| {
                const uri = list.items[self.selected].uri;
                try api.startPlayback(self.client, .{ .context_uri = uri }, null);
            },
            .playlists => |list| {
                const uri = list.items[self.selected].uri;
                try api.startPlayback(self.client, .{ .context_uri = uri }, null);
            },
        }
    }

    pub fn getKind(self: Table) []const u8 {
        return @tagName(self.list)[0 .. @tagName(self.list).len - 1];
    }

    pub fn len(self: Table) usize {
        switch (self.list) {
            .tracks => |list| return list.items.len,
            .artists => |list| return list.items.len,
            .albums => |list| return list.items.len,
            .playlists => |list| return list.items.len,
        }
    }
};
