const std = @import("std");
const spoon = @import("spoon");
const api = @import("../api.zig");
const ui = @import("../ui.zig");
const help = @import("../cmd.zig").help;
const Table = ui.Table;

// this is allocation fest

pub const usage =
    \\Usage: {s} search [track|artist|album|playlist] [query]...
    \\
    \\Description: Search a track, playlist, album, or artist with a TUI
    \\
    \\Commands:
    \\  q or escape                        Quit
    \\  right-click                        Select a row
    \\  j or arrow-down or scroll-down     Move down one row
    \\  k or arrow-up or scroll-up         Move up one row
    \\  l or arrow-right                   Move to the next table or play the selected track
    \\  h or arrow-left                    Move to the previous table
    \\  g or home                          Move to the top of the table
    \\  G or end                           Move to the bottom of the table
    \\  d or C-d or page-down              Move down one page
    \\  u or C-u or page-up                Move up one page
    \\  enter                              Play the selected item and quit
    \\  p                                  Play the selected item
    \\  s                                  Save the selected item
    // \\  r                                  Remove the selected track
    \\  - or _                             Decrease volume
    \\  + or =                             Increase volume
    // \\  /                                  Search
    \\
;

var current_table: *Table = undefined;

pub fn exec(
    client: *api.Client,
    child_allocator: std.mem.Allocator,
    args: *std.process.ArgIterator,
) !void {
    const kind = if (args.next()) |arg| blk: {
        break :blk std.meta.stringToEnum(Table.Kind, arg) orelse {
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
    current_table = try Table.init(client, allocator, kind, title, query, getFetchFn(kind));

    try ui.init(handleSigWinch);
    defer ui.deinit();

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
        while (it.next()) |in| {
            if (in.eqlDescription("escape") or in.eqlDescription("q")) {
                return;
            } else if (in.content == .mouse and in.content.mouse.button == .btn1) {
                // single click -> select clicked row
                if (in.content.mouse.y > 2 and in.content.mouse.y <= current_table.displayed() + 2) {
                    current_table.selected = in.content.mouse.y - 3;
                    try render();
                }
            } else if (in.eqlDescription("arrow-down") or in.eqlDescription("j") or
                (in.content == .mouse and in.content.mouse.button == .scroll_down))
            {
                if (current_table.selected < current_table.len() - 1) {
                    current_table.selected += 1;
                    if (current_table.selected - current_table.start >= current_table.displayed()) {
                        current_table.start += 1;
                    }
                    try render();
                } else if (try current_table.fetchNext()) {
                    try render();
                }
            } else if (in.eqlDescription("arrow-up") or in.eqlDescription("k") or
                (in.content == .mouse and in.content.mouse.button == .scroll_up))
            {
                if (current_table.selected > 0) {
                    current_table.selected -= 1;
                    if (current_table.selected < current_table.start) {
                        current_table.start -= 1;
                    }
                    try render();
                }
            } else if (in.eqlDescription("arrow-right") or in.eqlDescription("l")) {
                current_table = try current_table.nextTable() orelse {
                    // current_table is a track -> play it
                    current_table.play() catch |err| {
                        try notify(.err, "Failed to start playback: {}", .{err});
                    };
                    continue;
                };
                current_table.resetPosition();
                try render();
            } else if (in.eqlDescription("arrow-left") or in.eqlDescription("h")) {
                current_table = current_table.prevTable() orelse continue;
                try render();
            } else if (in.eqlDescription("G") or in.eqlDescription("end")) {
                current_table.selected = current_table.len() - 1;
                current_table.start = current_table.len() - current_table.displayed();
                try render();
            } else if (in.eqlDescription("g") or in.eqlDescription("home")) {
                current_table.resetPosition();
                try render();
            } else if (in.eqlDescription("d") or in.eqlDescription("C-d") or
                in.eqlDescription("page-down"))
            {
                if (current_table.selected + Table.limit < current_table.len() - 1 or
                    try current_table.fetchNext())
                {
                    current_table.selected += Table.limit;
                    if (current_table.selected - current_table.start >= current_table.displayed()) {
                        current_table.start += Table.limit;
                        // make selected row be at the end of the screen to be the opposite of 'u'
                        const selected_row = 1 + current_table.selected - current_table.start;
                        current_table.start -= current_table.displayed() - selected_row;
                    }
                    try render();
                }
            } else if (in.eqlDescription("u") or in.eqlDescription("C-u") or
                in.eqlDescription("page-up"))
            {
                if (current_table.selected > 0) {
                    current_table.selected -|= Table.limit;
                    if (current_table.selected < current_table.start) {
                        current_table.start = current_table.selected;
                    }
                    try render();
                }
            } else if (in.eqlDescription("enter")) {
                if (current_table.play()) {
                    return;
                } else |err| {
                    try notify(.err, "Failed to start playback: {}", .{err});
                }
            } else if (in.eqlDescription("p")) {
                current_table.play() catch |err| {
                    try notify(.err, "Failed to start playback: {}", .{err});
                };
            } else if (in.eqlDescription("s")) {
                try current_table.save(); // rename like command to save?
                switch (current_table.selectedItem()) {
                    .track => |track| try notify(.info, "Saved track '{s}' from '{s}' by {s}", .{
                        track.name,
                        track.album.name,
                        track.artists[0].name,
                    }),
                    .album => |album| try notify(.info, "Saved album '{s}' by {s}", .{
                        album.name,
                        album.artists[0].name,
                    }),
                    .artist => |artist| try notify(.info, "Saved artist '{s}'", .{
                        artist.name,
                    }),
                    .playlist => |playlist| try notify(.info, "Saved playlist '{s}' by {s}", .{
                        playlist.name,
                        playlist.owner.display_name orelse playlist.owner.id,
                    }),
                }
            } else if (in.eqlDescription("r")) {
                // TODO: do it in 's'? (no)
                // try current_table.remove(); // TODO: + add remove command
            } else if (in.eqlDescription("-") or in.eqlDescription("_")) {
                updateVolume(current_table.client, .down) catch |err| {
                    try notify(.err, "Failed to update volume: {}", .{err});
                };
            } else if (in.eqlDescription("+") or in.eqlDescription("=")) {
                updateVolume(current_table.client, .up) catch |err| {
                    try notify(.err, "Failed to update volume: {}", .{err});
                };
            } else if (in.eqlDescription("/")) {
                // TODO: search and reset
                // ask for kind and query
                // if kind is wrong assume it's the same as before and that it's part of the query
            } else if (in.content != .mouse) {
                try notify(.err, "Invalid input: {}", .{in});
            }
        }
    }
}

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
    try rc.setAttribute(.{ .fg = .none, .bg = .cyan });
    rpw = rc.restrictedPaddingWriter(ui.term.width);
    try rpw.writer().writeAll("[q] Quit [h] Back [j] Down [k] Up [l] Forward [g] Top [G] Bottom [s] Save [p] Play [enter] Play and Quit");
    try rpw.pad();
}

const Level = enum {
    err,
    info,

    pub fn asText(comptime self: Level) []const u8 {
        return switch (self) {
            .err => "error",
            .info => "info",
        };
    }
};

fn notify(comptime level: Level, comptime fmt: []const u8, args: anytype) !void {
    var rc = try ui.term.getRenderContext();
    defer rc.done() catch {};

    try rc.moveCursorTo(ui.term.height - 1, 0);
    var rpw = rc.restrictedPaddingWriter(ui.term.width);
    switch (level) {
        .err => try rc.setAttribute(.{ .fg = .none, .bg = .red, .bold = true }),
        .info => try rc.setAttribute(.{ .fg = .none, .bg = .green, .bold = true }),
    }
    const level_txt = comptime level.asText();
    try rpw.writer().print(level_txt ++ ": " ++ fmt, args);
    try rpw.pad();
}

fn handleSigWinch(_: c_int) callconv(.C) void {
    ui.term.fetchSize() catch return;
    current_table.resetPosition();
    if (!ui.term.currently_rendering) {
        render() catch {};
    }
}

fn getFetchFn(kind: Table.Kind) *const fn (*Table) anyerror!void {
    return switch (kind) {
        .track => fetchTracks,
        .artist => fetchArtists,
        .album => fetchAlbums,
        .playlist => fetchPlaylists,
    };
}

fn fetchTracks(self: *Table) !void {
    const result = try api.search(self.client, self.query, "track", Table.limit, self.len());
    try self.list.tracks.appendSlice(self.allocator, result.tracks.?.items);
    self.total = result.tracks.?.total;
    self.has_next = result.tracks.?.next != null;
}

fn fetchArtists(self: *Table) !void {
    const result = try api.search(self.client, self.query, "artist", Table.limit, self.len());
    try self.list.artists.appendSlice(self.allocator, result.artists.?.items);
    self.total = result.artists.?.total;
    self.has_next = result.artists.?.next != null;
}

fn fetchAlbums(self: *Table) !void {
    const result = try api.search(self.client, self.query, "album", Table.limit, self.len());
    try self.list.albums.appendSlice(self.allocator, result.albums.?.items);
    self.total = result.albums.?.total;
    self.has_next = result.albums.?.next != null;
}

fn fetchPlaylists(self: *Table) !void {
    const result = try api.search(self.client, self.query, "playlist", Table.limit, self.len());
    try self.list.playlists.appendSlice(self.allocator, result.playlists.?.items);
    self.total = result.playlists.?.total;
    self.has_next = result.playlists.?.next != null;
}

fn updateVolume(client: *api.Client, arg: enum { up, down }) !void {
    const playback_state = try api.getPlaybackState(client);
    const device = playback_state.device orelse return error.NoActiveDevice;
    var volume = device.volume_percent orelse return error.VolumeControlNotSupported;

    if (arg == .up) {
        volume += 10;
        if (volume > 100) {
            volume = 100;
        }
    } else if (arg == .down) {
        volume -|= 10;
    }

    try api.setVolume(client, volume);
}
