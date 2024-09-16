const std = @import("std");
const spoon = @import("spoon");
const api = @import("../api.zig");
const ui = @import("../ui.zig");
const cmd = @import("../cmd.zig");
const Table = ui.Table;

// this is allocation fest
// TODO: add number in ui like in vim?
// TODO: add a way to display errors e.g. no active device
// TODO: add mouse support for clicking on a row

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

var current_table: *Table = undefined;

pub fn exec(
    client: *api.Client,
    child_allocator: std.mem.Allocator,
    args: *std.process.ArgIterator,
) !void {
    const kind = if (args.next()) |arg| blk: {
        break :blk std.meta.stringToEnum(Table.Kind, arg) orelse {
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
        // TODO: ui.term.height - 5 can be less than 0 here
        while (it.next()) |in| {
            if (in.eqlDescription("escape") or in.eqlDescription("q")) {
                return;
            } else if (in.eqlDescription("arrow-down") or in.eqlDescription("j") or
                (in.content == .mouse and in.content.mouse.button == .scroll_down))
            {
                if (current_table.selected < current_table.len() - 1) {
                    current_table.selected += 1;
                    if (current_table.selected - current_table.start >= ui.term.height - 5) {
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
                if (current_table.selected + Table.limit < current_table.len() - 1 or
                    try current_table.fetchNext())
                {
                    current_table.selected += Table.limit;
                    if (current_table.selected - current_table.start >= ui.term.height - 5) {
                        current_table.start += Table.limit;
                        // make selected row be at the end of the screen to be the opposite of 'u'
                        const selected_row = 1 + current_table.selected - current_table.start;
                        current_table.start -= (ui.term.height - 5) - selected_row;
                    }
                    try render();
                }
            } else if (in.eqlDescription("u") or in.eqlDescription("page-up")) {
                if (current_table.selected > 0) {
                    current_table.selected -|= Table.limit;
                    if (current_table.selected < current_table.start) {
                        current_table.start = current_table.selected;
                    }
                    try render();
                }
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
                try current_table.save(); // rename like command to save?
                // TODO: notify user
            } else if (in.eqlDescription("r")) {
                // TODO: do it in 's'? (no)
                // try current_table.remove(); // TODO: + add remove command
                // TODO: notify user
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

    // if (current_table.imageUrl()) |url| {
    //     try ui.drawImage(&rc, url, 0, 0);
    // }
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
    try rpw.writer().writeAll("[q] Quit [h] Go back [j] Down [k] Up..."); // TODO
    try rpw.pad();
}

// fn drawNotification(msg: []const u8, err: ?anyerror) !void {
fn drawNotification(msg: union { err: anyerror, str: []const u8 }) !void {
    var rc = try ui.term.getRenderContext();
    defer rc.done() catch {};

    // TODO: if err display in red and bold else in green and bold?
    //       just text or text with a border?
    _ = msg;
}

fn handleSigWinch(_: c_int) callconv(.C) void {
    ui.term.fetchSize() catch {};
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
