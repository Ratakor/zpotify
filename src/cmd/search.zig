const std = @import("std");
const spoon = @import("spoon");
const api = @import("../api.zig");
const ui = @import("../ui.zig");
const help = @import("../cmd.zig").help;
const Table = ui.Table;

pub const usage =
    \\Usage: {s} search [track|artist|album|playlist] [query]...
    \\
    \\Description: Search a track, playlist, album, or artist with a TUI
    \\
    \\Commands:
    \\  q                                  Quit
    \\  right-click                        Select a row
    \\  j or arrow-down or scroll-down     Move down one row
    \\  k or arrow-up or scroll-up         Move up one row
    \\  l or arrow-right                   Move to the next table or play the selected track
    \\  h or arrow-left                    Move to the previous table
    \\  g or home                          Move to the top of the table
    \\  G or end                           Move to the bottom of the table
    \\  d or C-d or page-down              Move down one page
    \\  u or C-u or page-up                Move up one page
    \\  i                                  Toggle image display
    \\  s                                  Save the selected entry to the library
    \\  r                                  Remove the selected entry from the library
    // \\  /                                  Search
    \\  p                                  Play the selected entry
    \\  enter                              Play the selected entry and quit
    \\
;

var current_table: *Table = undefined;
var devices: struct { items: ?api.Devices, selected: usize } = .{ .items = null, .selected = 0 };

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

    // this is allocation fest
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
    var fds = [1]std.posix.pollfd{.{
        .fd = ui.term.tty.?,
        .events = std.posix.POLL.IN,
        .revents = undefined,
    }};
    var buf: [48]u8 = undefined; // must be a multiple of 6
    while (true) {
        _ = try std.posix.poll(&fds, -1);

        const read = try ui.term.readInput(&buf);
        var it = spoon.inputParser(buf[0..read]);
        while (it.next()) |in| {
            std.log.debug("Input: {}", .{in});

            if (in.eqlDescription("q")) {
                return;
            } else if (in.content == .mouse and in.content.mouse.button == .btn1) {
                // single click -> select clicked row
                if (in.content.mouse.y > 2 and in.content.mouse.y <= current_table.displayed() + 2) {
                    current_table.selected = current_table.start + in.content.mouse.y - 3;
                    try render();
                }
            } else if (in.eqlDescription("arrow-down") or in.eqlDescription("j") or
                (in.content == .mouse and in.content.mouse.button == .scroll_down))
            {
                if (current_table.selected < current_table.len() - 1 or try current_table.fetchNext()) {
                    current_table.selected += 1;
                    if (current_table.selected - current_table.start >= current_table.displayed()) {
                        current_table.start += 1;
                    }
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
                if (try current_table.nextTable()) |next_table| {
                    current_table = next_table;
                    current_table.resetPosition();
                    try render();
                } else if (playFallback()) { // current_table is a track -> play it
                    try notifyAction("Playing");
                } else |err| {
                    try notify(.err, "Failed to start playback: {}", .{err});
                }
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
            } else if (in.eqlDescription("d") or in.eqlDescription("C-d") or in.eqlDescription("page-down")) {
                if (current_table.selected + Table.limit < current_table.len() - 1 or try current_table.fetchNext()) {
                    current_table.selected += Table.limit;
                    if (current_table.selected - current_table.start >= current_table.displayed()) {
                        current_table.start += Table.limit;
                        // make selected row be at the end of the screen to be the opposite of 'u'
                        const selected_row = 1 + current_table.selected - current_table.start;
                        current_table.start -= current_table.displayed() - selected_row;
                    }
                    try render();
                }
            } else if (in.eqlDescription("u") or in.eqlDescription("C-u") or in.eqlDescription("page-up")) {
                if (current_table.selected > 0) {
                    current_table.selected -|= Table.limit;
                    if (current_table.selected < current_table.start) {
                        current_table.start = current_table.selected;
                    }
                    try render();
                }
            } else if (in.eqlDescription("i")) {
                ui.enable_image = !ui.enable_image;
                try render();
            } else if (in.eqlDescription("enter")) {
                if (playFallback()) {
                    return;
                } else |err| {
                    try notify(.err, "Failed to start playback: {}", .{err});
                }
            } else if (in.eqlDescription("p")) {
                if (playFallback()) {
                    try notifyAction("Playing");
                } else |err| {
                    try notify(.err, "Failed to start playback: {}", .{err});
                }
            } else if (in.eqlDescription("s")) {
                try current_table.save(); // rename like command to save?
                try notifyAction("Saved");
            } else if (in.eqlDescription("r")) {
                try current_table.remove(); // add remove command?
                try notifyAction("Removed");
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

    if (devices.items) |items| {
        try drawHeader(&rc, "zpotify: Select a device to play on");
        try ui.drawDevices(items, &rc, 1, devices.selected + 1, {});
        try drawFooter(&rc, "[q] Back [j] Down [k] Up [enter] Select");
    } else {
        try drawHeader(&rc, current_table.title);
        try current_table.draw(&rc, 1);
        try drawFooter(&rc, "[q] Quit [h] Back [j] Down [k] Up [l] Forward [g] Top [G] Bottom [s] Save [r] Remove [p] Play [enter] Play and Quit");
    }
}

fn drawHeader(rc: *spoon.Term.RenderContext, header: []const u8) !void {
    try rc.moveCursorTo(0, 0);
    try rc.setAttribute(.{ .fg = .green, .reverse = true, .bold = true });
    var rpw = rc.restrictedPaddingWriter(ui.term.width);
    try rpw.writer().writeAll(header);
    try rpw.pad();
}

fn drawFooter(rc: *spoon.Term.RenderContext, footer: []const u8) !void {
    try rc.moveCursorTo(ui.term.height - 2, 0);
    try rc.setAttribute(.{ .fg = .none, .bold = true });
    var rpw = rc.restrictedPaddingWriter(ui.term.width);
    if (devices.items) |items| {
        try rpw.writer().print("Showing {0d} of {0d} devices", .{items.len});
    } else {
        const kind = @tagName(current_table.list);
        try rpw.writer().print("Showing {d} of {d} {s}", .{
            current_table.len(),
            current_table.total,
            kind[0 .. kind.len - @intFromBool(current_table.len() == 1)],
        });
    }
    try rpw.finish();

    try rc.moveCursorTo(ui.term.height - 1, 0);
    try rc.setAttribute(.{ .fg = .none, .bg = .cyan });
    rpw = rc.restrictedPaddingWriter(ui.term.width);
    try rpw.writer().writeAll(footer);
    try rpw.pad();
}

fn notify(level: enum { err, info }, comptime fmt: []const u8, args: anytype) !void {
    var rc = try ui.term.getRenderContext();
    defer rc.done() catch {};

    try rc.moveCursorTo(ui.term.height - 1, 0);
    var rpw = rc.restrictedPaddingWriter(ui.term.width);
    switch (level) {
        .err => try rc.setAttribute(.{ .fg = .none, .bg = .red, .bold = true }),
        .info => try rc.setAttribute(.{ .fg = .none, .bg = .blue, .bold = true }),
    }
    try rpw.writer().print(fmt, args);
    try rpw.pad();
}

fn notifyAction(comptime action: []const u8) !void {
    switch (current_table.selectedItem()) {
        .track => |track| try notify(.info, action ++ " track '{s}' from '{s}' by {s}", .{
            track.name,
            track.album.name,
            track.artists[0].name,
        }),
        .album => |album| try notify(.info, action ++ " album '{s}' by {s}", .{
            album.name,
            album.artists[0].name,
        }),
        .artist => |artist| try notify(.info, action ++ " artist '{s}'", .{
            artist.name,
        }),
        .playlist => |playlist| try notify(.info, action ++ " playlist '{s}' by {s}", .{
            playlist.name,
            playlist.owner.display_name orelse playlist.owner.id,
        }),
    }
}

fn playFallback() !void {
    if (current_table.play(null)) {
        return;
    } else |err| {
        if (err != error.NoActiveDevice) {
            return err;
        }

        devices.items = try api.getDevices(current_table.client); // this will be freed at the end of the PROGRAM
        devices.selected = 0;
        defer {
            devices.items = null;
            render() catch {};
        }
        if (devices.items.?.len == 0) {
            return error.NoActiveDevice;
        }

        var fds = [1]std.posix.pollfd{.{
            .fd = ui.term.tty.?,
            .events = std.posix.POLL.IN,
            .revents = undefined,
        }};
        var buf: [48]u8 = undefined; // must be a multiple of 6
        try render();
        while (true) {
            _ = try std.posix.poll(&fds, -1);
            const read = try ui.term.readInput(&buf);
            var it = spoon.inputParser(buf[0..read]);
            while (it.next()) |in| {
                if (in.eqlDescription("q") or in.eqlDescription("h")) {
                    return error.Canceled;
                } else if (in.eqlDescription("arrow-down") or in.eqlDescription("j")) {
                    if (devices.selected < devices.items.?.len - 1) {
                        devices.selected += 1;
                        try render();
                    }
                } else if (in.eqlDescription("arrow-up") or in.eqlDescription("k")) {
                    if (devices.selected > 0) {
                        devices.selected -= 1;
                        try render();
                    }
                } else if (in.eqlDescription("enter") or in.eqlDescription("l")) {
                    const device_id = devices.items.?[devices.selected].id;
                    try current_table.play(device_id);
                    return;
                }
            }
        }
    }
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
