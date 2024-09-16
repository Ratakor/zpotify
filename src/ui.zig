const std = @import("std");
const spoon = @import("spoon");
const api = @import("api.zig");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("jpeglib.h");
    @cInclude("chafa/chafa.h");
});

pub var term: spoon.Term = undefined;
var err_mgr: c.jpeg_error_mgr = undefined; // TODO: custom setup
pub var cinfo: c.jpeg_decompress_struct = undefined;
pub var chafa_config: *c.ChafaCanvasConfig = undefined;
var use_sixels = false;

pub fn init(sigWinchHandler: std.posix.Sigaction.handler_fn) !void {
    try term.init(.{});
    errdefer term.deinit() catch unreachable;

    try std.posix.sigaction(std.posix.SIG.WINCH, &std.posix.Sigaction{
        .handler = .{ .handler = sigWinchHandler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    }, null);
    try term.uncook(.{ .request_mouse_tracking = true });
    try term.fetchSize();

    cinfo.err = c.jpeg_std_error(&err_mgr);

    const symbol_map = c.chafa_symbol_map_new().?;
    defer c.chafa_symbol_map_unref(symbol_map);
    // TODO: experiment with different symbol tags
    c.chafa_symbol_map_add_by_tags(symbol_map, c.CHAFA_SYMBOL_TAG_HALF);
    chafa_config = c.chafa_canvas_config_new().?;
    try detectTerminal(chafa_config);
    // c.chafa_canvas_config_set_geometry(chafa_config, 15, 15); // TODO + also update it based on term size (with sigwinch)
    c.chafa_canvas_config_set_symbol_map(chafa_config, symbol_map);
}

pub fn deinit() void {
    c.chafa_canvas_config_unref(chafa_config);
    term.deinit() catch unreachable;
}

pub const Image = struct {
    width: usize,
    height: usize,
    pixels: []const u8,
    allocator: std.mem.Allocator,

    pub const channel_count = 3;

    pub fn deinit(self: @This()) void {
        self.allocator.free(self.pixels);
    }
};

pub fn drawImage(
    rc: *spoon.Term.RenderContext,
    url: []const u8,
    start_x: usize,
    y: usize,
) !void {
    // TODO: allocator
    var image = try fetchAlbumImage(std.heap.c_allocator, url);
    defer image.deinit();

    var w: c.gint = @intCast(term.width - start_x);
    var h: c.gint = @intCast(term.height - y);
    c.chafa_calc_canvas_geometry(
        @intCast(image.width),
        @intCast(image.height),
        &w,
        &h,
        if (use_sixels) 1 else 0.5,
        @intFromBool(false),
        @intFromBool(false),
    );
    c.chafa_canvas_config_set_geometry(chafa_config, w, h);

    const canvas = c.chafa_canvas_new(chafa_config).?;
    defer c.chafa_canvas_unref(canvas);

    c.chafa_canvas_draw_all_pixels(
        canvas,
        c.CHAFA_PIXEL_RGB8,
        image.pixels.ptr,
        @intCast(image.width),
        @intCast(image.height),
        @intCast(image.width * Image.channel_count),
    );
    const gs = c.chafa_canvas_print(canvas, getTermInfo());
    defer _ = c.g_string_free(gs, @intFromBool(true));

    var iter = std.mem.splitScalar(u8, gs.*.str[0..gs.*.len], '\n');
    var x: usize = start_x;
    while (iter.next()) |line| : (x += 1) {
        try rc.moveCursorTo(x, y);
        try rc.buffer.writer().writeAll(line);
    }
}

fn getCachePath(allocator: std.mem.Allocator, id: []const u8) ![]const u8 {
    if (std.posix.getenv("XDG_CACHE_HOME")) |xdg_cache| {
        return std.fmt.allocPrint(allocator, "{s}/zpotify/{s}.jpeg", .{ xdg_cache, id });
    } else if (std.posix.getenv("HOME")) |home| {
        return std.fmt.allocPrint(allocator, "{s}/.cache/zpotify/{s}.jpeg", .{ home, id });
    } else {
        return error.EnvironmentVariableNotFound;
    }
}

// do not use with an arena
pub fn fetchAlbumImage(allocator: std.mem.Allocator, url: []const u8) !Image {
    const cwd = std.fs.cwd();
    const id = url[std.mem.lastIndexOfScalar(u8, url, '/').? + 1 ..];
    const cache_path = try getCachePath(allocator, id);
    defer allocator.free(cache_path);
    const raw_image = if (cwd.openFile(cache_path, .{})) |file| blk: {
        defer file.close();
        break :blk try file.readToEndAlloc(allocator, 1024 * 1024);
    } else |err| blk: {
        if (err != error.FileNotFound) {
            return err;
        }
        try cwd.makePath(cache_path[0..std.mem.lastIndexOfScalar(u8, cache_path, '/').?]);
        const file = try cwd.createFile(cache_path, .{});
        defer file.close();

        var client: std.http.Client = .{ .allocator = allocator };
        defer client.deinit();
        var response = std.ArrayList(u8).init(allocator);
        defer response.deinit();
        const result = try client.fetch(.{
            .method = .GET,
            .location = .{ .url = url },
            .response_storage = .{ .dynamic = &response },
        });
        std.debug.assert(result.status == .ok); // TODO

        try file.writeAll(response.items);
        break :blk try response.toOwnedSlice();
    };
    defer allocator.free(raw_image);

    c.jpeg_create_decompress(&cinfo);
    defer c.jpeg_destroy_decompress(&cinfo);
    c.jpeg_mem_src(&cinfo, raw_image.ptr, raw_image.len);
    _ = c.jpeg_read_header(&cinfo, @intFromBool(true));
    _ = c.jpeg_start_decompress(&cinfo);
    defer _ = c.jpeg_finish_decompress(&cinfo);

    if (cinfo.data_precision != 8 or cinfo.output_components != 3) {
        return error.UnsupportedImageFormat;
    }

    const row_stride = cinfo.output_width * @as(c_uint, @intCast(cinfo.output_components));
    var pixels = try allocator.alloc(u8, cinfo.image_height * row_stride);
    errdefer allocator.free(pixels);

    var index: usize = 0;
    while (index != pixels.len) {
        const amt = c.jpeg_read_scanlines(&cinfo, @constCast(@ptrCast(&pixels.ptr[index..])), 1);
        if (amt == 0) return error.FailedToReadImage;
        index += amt * row_stride;
    }

    return .{
        .width = cinfo.image_width,
        .height = cinfo.image_height,
        .pixels = pixels,
        .allocator = allocator,
    };
}

fn getTermInfo() ?*c.ChafaTermInfo {
    return c.chafa_term_db_detect(c.chafa_term_db_get_default(), std.c.environ);
}

fn detectTerminal(config: *c.ChafaCanvasConfig) !void {
    const term_info = getTermInfo() orelse return error.TermInfoNotFound;

    if (c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_SET_COLOR_FGBG_DIRECT) != 0 and
        c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_SET_COLOR_FG_DIRECT) != 0 and
        c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_SET_COLOR_BG_DIRECT) != 0)
    {
        c.chafa_canvas_config_set_canvas_mode(config, c.CHAFA_CANVAS_MODE_TRUECOLOR);
    } else {
        return error.TrueColorNotSupported;
    }

    if (c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_BEGIN_KITTY_IMMEDIATE_IMAGE_V1) != 0) {
        c.chafa_canvas_config_set_pixel_mode(config, c.CHAFA_PIXEL_MODE_KITTY);
    } else if (c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_BEGIN_SIXELS) != 0 and
        c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_END_SIXELS) != 0)
    {
        c.chafa_canvas_config_set_pixel_mode(config, c.CHAFA_PIXEL_MODE_SIXELS);
        use_sixels = true;
    } else if (c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_BEGIN_ITERM2_IMAGE) != 0 and
        c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_END_ITERM2_IMAGE) != 0)
    {
        c.chafa_canvas_config_set_pixel_mode(config, c.CHAFA_PIXEL_MODE_ITERM2);
    } else {
        c.chafa_canvas_config_set_pixel_mode(config, c.CHAFA_PIXEL_MODE_SYMBOLS);
    }
}

pub const Table = struct {
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

    pub const Kind = enum { track, artist, album, playlist };
    pub const limit = 10;
    pub const limit_max = 50;

    pub fn init(
        client: *api.Client,
        allocator: std.mem.Allocator,
        kind: Kind,
        title: []const u8,
        query: []const u8,
        fetchFn: *const fn (*Table) anyerror!void,
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
            .fetchFn = fetchFn,
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
        const end = @min(self.len(), self.start + term.height - 5);
        const selected_row = first_row + self.selected - self.start;

        switch (self.list) {
            .tracks => |list| try drawTracks(list.items[start..end], rc, first_row, selected_row),
            .artists => |list| try drawArtists(list.items[start..end], rc, first_row, selected_row),
            .albums => |list| try drawAlbums(list.items[start..end], rc, first_row, selected_row),
            .playlists => |list| try drawPlaylists(list.items[start..end], rc, first_row, selected_row),
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
            inline else => |list| {
                const uri = list.items[self.selected].uri;
                try api.startPlayback(self.client, .{ .context_uri = uri }, null);
            },
        }
    }

    pub fn save(self: Table) !void {
        switch (self.list) {
            .tracks => |list| try api.saveTracks(self.client, list.items[self.selected].id),
            .artists => |list| try api.followArtist(self.client, list.items[self.selected].id),
            .albums => |list| try api.saveAlbums(self.client, list.items[self.selected].id),
            .playlists => |list| try api.followPlaylist(self.client, list.items[self.selected].id),
        }
    }

    pub fn imageUrl(self: Table) ?[]const u8 {
        const images = switch (self.list) {
            .tracks => |list| list.items[self.selected].album.images,
            inline else => |list| list.items[self.selected].images,
        };
        return switch (images.len) {
            0 => null,
            1 => images[0].url,
            else => blk: {
                // TODO: pick the best one based on the terminal size
                break :blk images[1].url;
            },
        };
    }

    pub fn len(self: Table) usize {
        switch (self.list) {
            inline else => |list| return list.items.len,
        }
    }

    const Column = struct {
        header_name: []const u8,
        field: @Type(.EnumLiteral),
        size: usize, // in %
    };

    fn makeDrawFn(
        comptime T: type,
        comptime title: []const u8,
        comptime columns: []const Column,
        comptime writeField: fn (
            comptime field: @Type(.EnumLiteral),
            item: T,
            writer: anytype,
        ) anyerror!void,
    ) fn ([]const T, *spoon.Term.RenderContext, usize, usize) anyerror!void {
        comptime {
            var size = 0;
            for (columns) |col| {
                size += col.size;
            }
            std.debug.assert(size == 100);
        }

        return struct {
            fn draw(
                items: []const T,
                rc: *spoon.Term.RenderContext,
                first_row: usize,
                selected_row: usize,
            ) !void {
                try drawHeader(rc, first_row);
                try drawEntries(items, rc, first_row + 2, selected_row + 2);
            }

            fn drawHeader(rc: *spoon.Term.RenderContext, row: usize) !void {
                try rc.setAttribute(.{ .fg = .none, .bold = true });

                try rc.moveCursorTo(row, 0);
                var rpw = rc.restrictedPaddingWriter(term.width);
                const writer = rpw.writer();
                try writer.writeAll(title);
                try rpw.finish();

                var pos: usize = 0;
                inline for (columns) |col| {
                    try rc.moveCursorTo(row + 1, pos);
                    const size = term.width * col.size / 100;
                    rpw.len_left = size - 1;
                    try writer.writeAll(col.header_name);
                    pos += size;
                }
                try rpw.finish();
            }

            fn drawEntries(
                items: []const T,
                rc: *spoon.Term.RenderContext,
                first_row: usize,
                selected_row: usize,
            ) !void {
                for (items, first_row..) |item, row| {
                    try rc.moveCursorTo(row, 0);
                    var rpw = rc.restrictedPaddingWriter(term.width);
                    const writer = rpw.writer();

                    if (row == selected_row) {
                        try rc.setAttribute(.{ .reverse = true, .fg = .none });
                        try rpw.pad();
                    } else {
                        try rc.setAttribute(.{ .fg = .none });
                    }

                    var pos: usize = 0;
                    inline for (columns) |col| {
                        try rc.moveCursorTo(row, pos);
                        const size = term.width * col.size / 100;
                        rpw.len_left = size - 1;
                        try writeField(col.field, item, writer);
                        pos += size;
                        try rpw.finish();
                    }
                }
            }
        }.draw;
    }

    const drawTracks = makeDrawFn(
        api.Track,
        "Tracks",
        &[_]Column{
            .{ .header_name = "Name", .field = .name, .size = 40 },
            .{ .header_name = "Album", .field = .album, .size = 20 },
            .{ .header_name = "Artists", .field = .artists, .size = 30 },
            .{ .header_name = "Duration", .field = .duration_ms, .size = 10 },
        },
        struct {
            fn writeField(
                comptime field: @Type(.EnumLiteral),
                item: api.Track,
                writer: anytype,
            ) anyerror!void {
                switch (field) {
                    .album => try writer.writeAll(item.album.name),
                    .artists => {
                        for (item.artists, 0..) |artist, i| {
                            if (i != 0) {
                                try writer.writeAll(", ");
                            }
                            try writer.writeAll(artist.name);
                        }
                    },
                    .duration_ms => {
                        const min = item.duration_ms / std.time.ms_per_min;
                        const sec = (item.duration_ms / std.time.ms_per_s) % std.time.s_per_min;
                        try writer.print("{d}:{d:0>2}", .{ min, sec });
                    },
                    else => try writer.writeAll(@field(item, @tagName(field))),
                }
            }
        }.writeField,
    );

    const drawArtists = makeDrawFn(
        api.Artist,
        "Artists",
        &[_]Column{
            .{ .header_name = "Name", .field = .name, .size = 30 },
            .{ .header_name = "Genres", .field = .genres, .size = 55 },
            .{ .header_name = "Followers", .field = .followers, .size = 15 },
        },
        struct {
            fn writeField(
                comptime field: @Type(.EnumLiteral),
                item: api.Artist,
                writer: anytype,
            ) anyerror!void {
                switch (field) {
                    .genres => {
                        for (item.genres, 0..) |genre, i| {
                            if (i != 0) {
                                try writer.writeAll(", ");
                            }
                            try writer.writeAll(genre);
                        }
                    },
                    .followers => try writer.print("{d}", .{item.followers.total}),
                    else => try writer.writeAll(@field(item, @tagName(field))),
                }
            }
        }.writeField,
    );

    const drawAlbums = makeDrawFn(
        api.Album,
        "Albums",
        &[_]Column{
            .{ .header_name = "Name", .field = .name, .size = 40 },
            .{ .header_name = "Artists", .field = .artists, .size = 40 },
            .{ .header_name = "Release Date", .field = .release_date, .size = 20 },
        },
        struct {
            fn writeField(
                comptime field: @Type(.EnumLiteral),
                item: api.Album,
                writer: anytype,
            ) anyerror!void {
                switch (field) {
                    .artists => {
                        for (item.artists, 0..) |artist, i| {
                            if (i != 0) {
                                try writer.writeAll(", ");
                            }
                            try writer.writeAll(artist.name);
                        }
                    },
                    else => try writer.writeAll(@field(item, @tagName(field))),
                }
            }
        }.writeField,
    );

    const drawPlaylists = makeDrawFn(
        api.Playlist,
        "Playlists",
        &[_]Column{
            .{ .header_name = "Name", .field = .name, .size = 30 },
            .{ .header_name = "Description", .field = .description, .size = 50 },
            .{ .header_name = "Owner", .field = .owner, .size = 15 },
            .{ .header_name = "Tracks", .field = .tracks, .size = 5 },
        },
        struct {
            fn writeField(
                comptime field: @Type(.EnumLiteral),
                item: api.Playlist,
                writer: anytype,
            ) anyerror!void {
                switch (field) {
                    .owner => try writer.print("{?s}", .{item.owner.display_name}),
                    .tracks => try writer.print("{d}", .{item.tracks.total}),
                    else => try writer.writeAll(@field(item, @tagName(field))),
                }
            }
        }.writeField,
    );
};
