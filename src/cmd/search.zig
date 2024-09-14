const std = @import("std");
const spoon = @import("spoon");
const api = @import("../api.zig");
const ui = @import("../ui.zig");
const cmd = @import("../cmd.zig");

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
            cmd.help.exec("search");
            std.process.exit(1);
        };
    } else {
        std.log.err("Missing query type", .{});
        cmd.help.exec("search");
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
            cmd.help.exec("search");
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
                        current_table.start += limit;
                        // make selected row be at the end of the screen to be the opposite of 'u'
                        const selected_row = 1 + current_table.selected - current_table.start;
                        current_table.start -= (ui.term.height - 5) - selected_row;
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
                // try cmd.vol.exec(current_table.client, "down"); // TODO: display log correctly
            } else if (in.eqlDescription("+") or in.eqlDescription("=")) {
                // try cmd.vol.exec(current_table.client, "up"); // TODO: display log correctly
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

// fn drawNotification(msg: []const u8, err: ?anyerror) !void {
fn drawNotification(msg: union { err: anyerror, str: []const u8 }) !void {
    var rc = try ui.term.getRenderContext();
    defer rc.done() catch {};

    // TODO: if err display in red and bold else in green and bold?
    //       just text or text with a border?
    _ = msg;
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
    const kind = @tagName(current_table.list);
    try rpw.writer().print("Showing {d} of {d} {s}", .{
        current_table.len(),
        current_table.total,
        kind[0 .. kind.len - @intFromBool(current_table.len() == 1)],
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
    has_next: bool = true,
    fetchFn: *const fn (*Table) anyerror!void,
    query: []const u8, // can also be an id

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
            .fetchFn = switch (kind) {
                .track => fetchTracksSearch,
                .artist => fetchArtistsSearch,
                .album => fetchAlbumsSearch,
                .playlist => fetchPlaylistsSearch,
            },
            .title = title,
        };
        _ = try table.fetchNext();
        return table;
    }

    // make sure to init query, fetchFn, and title
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
            .fetchFn = undefined,
            .title = undefined,
            .prev = prev,
        };
        try prev.next.put(prev.allocator, prev.selected, table);
        return table;
    }

    fn fetchTracksSearch(self: *Table) !void {
        const result = try api.search(self.client, self.query, "track", limit, self.len());
        try self.list.tracks.appendSlice(self.allocator, result.tracks.?.items);
        self.total = result.tracks.?.total;
        self.has_next = result.tracks.?.next != null;
    }

    fn fetchArtistsSearch(self: *Table) !void {
        const result = try api.search(self.client, self.query, "artist", limit, self.len());
        try self.list.artists.appendSlice(self.allocator, result.artists.?.items);
        self.total = result.artists.?.total;
        self.has_next = result.artists.?.next != null;
    }

    fn fetchAlbumsSearch(self: *Table) !void {
        const result = try api.search(self.client, self.query, "album", limit, self.len());
        try self.list.albums.appendSlice(self.allocator, result.albums.?.items);
        self.total = result.albums.?.total;
        self.has_next = result.albums.?.next != null;
    }

    fn fetchPlaylistsSearch(self: *Table) !void {
        const result = try api.search(self.client, self.query, "playlist", limit, self.len());
        try self.list.playlists.appendSlice(self.allocator, result.playlists.?.items);
        self.total = result.playlists.?.total;
        self.has_next = result.playlists.?.next != null;
    }

    fn fetchAlbumsArtist(self: *Table) !void {
        const albums = try api.getArtistAlbums(self.client, self.query, limit, self.len());
        try self.list.albums.appendSlice(self.allocator, albums.items);
        self.total = albums.total;
        self.has_next = albums.next != null;
    }

    fn fetchTracksPlaylist(self: *Table) !void {
        const tracks = try api.getPlaylistTracks(self.client, self.query, limit, self.len());
        for (tracks.items) |item| {
            try self.list.tracks.append(self.allocator, item.track);
        }
        self.total = tracks.total;
        self.has_next = tracks.next != null;
    }

    pub fn fetchNext(self: *Table) !bool {
        if (!self.has_next) {
            return false;
        }
        try self.fetchFn(self);
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
            .artists => |list| {
                const artist = list.items[self.selected];
                const next_table = try self.makeNextTable(.album);
                next_table.query = artist.id;
                next_table.fetchFn = fetchAlbumsArtist;
                next_table.title = try std.fmt.allocPrint(next_table.allocator, "zpotify: {s}", .{
                    artist.name,
                });
                _ = try next_table.fetchNext();
                return next_table;
            },
            .albums => |list| {
                const album = list.items[self.selected];
                const next_table = try self.makeNextTable(.track);
                next_table.query = album.id;
                next_table.has_next = false; // it's easier to fetch all tracks at once
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
                next_table.query = playlist.id;
                next_table.fetchFn = fetchTracksPlaylist;
                next_table.title = try std.fmt.allocPrint(
                    next_table.allocator,
                    "zpotify: {s} - {s}",
                    .{ playlist.name, playlist.owner.display_name orelse playlist.owner.id },
                );
                _ = try next_table.fetchNext();
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

    pub fn len(self: Table) usize {
        switch (self.list) {
            .tracks => |list| return list.items.len,
            .artists => |list| return list.items.len,
            .albums => |list| return list.items.len,
            .playlists => |list| return list.items.len,
        }
    }
};
