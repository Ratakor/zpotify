const std = @import("std");
const spoon = @import("spoon");
const api = @import("../api.zig");
const ui = @import("../ui.zig");
const help = @import("../cmd.zig").help;

pub const usage =
    \\Usage: {s} search [track|artist|album|playlist] [query]...
    \\
    \\Description: Search a track, playlist, album, or artist with a TUI
    \\
;

// TODO: remove this
const QueryType = enum { track, artist, album, playlist, album_tracks };

const limit = 10;
var current_table: *Table = undefined;
var previous_tables: std.ArrayList(*Table) = undefined;

// TODO: add number in ui like in vim

pub fn exec(
    client: *api.Client,
    allocator: std.mem.Allocator,
    args: *std.process.ArgIterator,
) !void {
    const query_type = if (args.next()) |arg| blk: {
        break :blk std.meta.stringToEnum(QueryType, arg) orelse {
            std.log.err("Invalid query type: '{s}'", .{arg});
            help.exec("search");
            std.process.exit(1);
        };
    } else {
        std.log.err("Missing query type", .{});
        help.exec("search");
        std.process.exit(1);
    };

    var query_builder = std.ArrayList([]const u8).init(allocator);
    defer query_builder.deinit();
    while (args.next()) |arg| {
        try query_builder.append(arg);
    }

    if (query_builder.items.len == 0) {
        std.log.err("Missing query", .{});
        help.exec("search");
        std.process.exit(1);
    }

    previous_tables = std.ArrayList(*Table).init(allocator);
    defer previous_tables.deinit();

    const query = try std.mem.join(allocator, " ", query_builder.items);
    defer allocator.free(query);
    const title = try std.fmt.allocPrint(allocator, "zpotify: search {s} '{s}'", .{
        @tagName(query_type),
        query,
    });
    defer allocator.free(title);
    current_table = try Table.init(client, allocator, query, query_type, title);
    defer current_table.deinit();

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
                const next_table = try current_table.nextTable() orelse continue;
                std.log.debug("next table: {s}", .{next_table.title});
                try previous_tables.append(current_table);
                current_table = next_table;
                try render();
            } else if (in.eqlDescription("arrow-left") or in.eqlDescription("h")) {
                const prev_table = previous_tables.popOrNull() orelse continue;
                try previous_tables.append(current_table);
                current_table = prev_table;
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
                break;
            } else if (in.eqlDescription("p")) {
                current_table.play() catch |err| switch (err) {
                    error.NoActiveDevice => {}, // TODO: display error
                    else => return err,
                };
            } else if (in.eqlDescription("s")) {
                // TODO: save
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
    try rpw.writer().print("Showing {d} of {d} {s}s", .{
        current_table.len(),
        current_table.total,
        current_table.kind(),
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
        tracks: std.ArrayList(api.Track),
        artists: std.ArrayList(api.Artist),
        albums: std.ArrayList(api.Album),
        playlists: std.ArrayList(api.Playlist),
        album_tracks: std.ArrayList(api.Track),

        // artist: api.Artist, // TODO: this one is annoying
        // playlist: api.Playlist,
    },
    client: *api.Client,
    arena: std.heap.ArenaAllocator,
    query: []const u8,
    total: usize,
    has_next: bool,
    selected: usize,
    start: usize,
    title: []const u8,

    pub fn init(
        client: *api.Client,
        allocator: std.mem.Allocator,
        query: []const u8,
        query_type: QueryType,
        title: []const u8,
    ) !*Table {
        var table = try allocator.create(Table);
        table.* = .{
            .list = switch (query_type) {
                .track => .{ .tracks = std.ArrayList(api.Track).init(allocator) },
                .artist => .{ .artists = std.ArrayList(api.Artist).init(allocator) },
                .album => .{ .albums = std.ArrayList(api.Album).init(allocator) },
                .playlist => .{ .playlists = std.ArrayList(api.Playlist).init(allocator) },
                .album_tracks => .{ .album_tracks = std.ArrayList(api.Track).init(allocator) },
            },
            .client = client,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .query = try allocator.dupe(u8, query),
            .total = 0,
            .has_next = true,
            .selected = 0,
            .start = 0,
            .title = try allocator.dupe(u8, title),
        };
        errdefer table.deinit();
        _ = try table.fetchNext();
        return table;
    }

    pub fn deinit(self: *Table) void {
        switch (self.list) {
            .tracks, .album_tracks => |*list| list.deinit(),
            .artists => |*list| list.deinit(),
            .albums => |*list| list.deinit(),
            .playlists => |*list| list.deinit(),
        }
        const allocator = self.arena.child_allocator;
        allocator.free(self.title);
        allocator.free(self.query);
        self.arena.deinit();
        allocator.destroy(self);
    }

    pub fn fetchNext(self: *Table) !bool {
        if (!self.has_next) {
            return false;
        }

        if (self.list == .album_tracks) {
            const tracks = try api.getAlbumTracksLeaky(
                self.client,
                self.query,
                limit,
                self.len(),
                self.arena.allocator(),
            );
            try self.list.album_tracks.appendSlice(tracks.items);
            self.total = tracks.total;
            self.has_next = tracks.next != null;
            return true;
        }

        const search_result = try api.searchLeaky(
            self.client,
            self.query,
            self.kind(),
            limit,
            self.len(),
            self.arena.allocator(),
        );

        switch (self.list) {
            .tracks => |*list| {
                try list.appendSlice(search_result.tracks.?.items);
                self.total = search_result.tracks.?.total;
                self.has_next = search_result.tracks.?.next != null;
            },
            .artists => |*list| {
                try list.appendSlice(search_result.artists.?.items);
                self.total = search_result.artists.?.total;
                self.has_next = search_result.artists.?.next != null;
            },
            .albums => |*list| {
                try list.appendSlice(search_result.albums.?.items);
                self.total = search_result.albums.?.total;
                self.has_next = search_result.albums.?.next != null;
            },
            .playlists => |*list| {
                try list.appendSlice(search_result.playlists.?.items);
                self.total = search_result.playlists.?.total;
                self.has_next = search_result.playlists.?.next != null;
            },
            else => unreachable,
        }

        return true;
    }

    pub fn draw(self: Table, rc: *spoon.Term.RenderContext, first_row: usize) !void {
        const end = @min(current_table.len(), current_table.start + ui.term.height - 5);
        switch (self.list) {
            .tracks, .album_tracks => |list| {
                const table: ui.TrackTable = .{ .items = list.items[self.start..end] };
                try table.draw(rc, first_row, first_row + self.selected - self.start);
            },
            .artists => |list| {
                const table: ui.ArtistTable = .{ .items = list.items[self.start..end] };
                try table.draw(rc, first_row, first_row + self.selected - self.start);
            },
            .albums => |list| {
                const table: ui.AlbumTable = .{ .items = list.items[self.start..end] };
                try table.draw(rc, first_row, first_row + self.selected - self.start);
            },
            .playlists => |list| {
                const table: ui.PlaylistTable = .{ .items = list.items[self.start..end] };
                try table.draw(rc, first_row, first_row + self.selected - self.start);
            },
        }
    }

    pub fn nextTable(self: Table) !?*Table {
        switch (self.list) {
            .tracks, .album_tracks => return null,
            .artists => |list| {
                // const allocator = self.arena.child_allocator;
                // const id = list.items[self.selected].id;
                // const artist = try api.getArtistLeaky(self.client, id, self.arena.allocator());
                // const title = try std.fmt.allocPrint(allocator, "{s} - {s}", .{
                //     artist.name,
                //     @tagName(self.list),
                // });
                // TODO: no query or query_type
                // TODO: add another Init method
                // return Table.init(self.client, allocator, "", .artist, artist.name);
                _ = list;
                return null;
            },
            .albums => |list| {
                const allocator = self.arena.child_allocator;
                const album = list.items[self.selected];
                const title = try std.fmt.allocPrint(allocator, "zpotify: {s} - {s}", .{
                    album.name,
                    album.artists[0].name,
                });
                defer allocator.free(title);
                return try Table.init(self.client, allocator, album.id, .album_tracks, title);
            },
            .playlists => return null, // TODO
        }
    }

    pub fn play(self: Table) !void {
        switch (self.list) {
            .tracks, .album_tracks => |list| {
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

    pub fn kind(self: Table) []const u8 {
        if (self.list == .album_tracks) {
            return "album track";
        }
        return @tagName(self.list)[0 .. @tagName(self.list).len - 1];
    }

    pub fn len(self: Table) usize {
        switch (self.list) {
            .tracks, .album_tracks => |list| return list.items.len,
            .artists => |list| return list.items.len,
            .albums => |list| return list.items.len,
            .playlists => |list| return list.items.len,
        }
    }
};
