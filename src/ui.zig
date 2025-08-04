const std = @import("std");
const spoon = @import("spoon");
const api = @import("api.zig");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("jpeglib.h");
    @cInclude("jerror.h");
    @cInclude("setjmp.h");
    @cInclude("chafa.h");
});

pub var term: spoon.Term = undefined;
pub var enable_image = true;
var term_info: *c.ChafaTermInfo = undefined;
var chafa_config: *c.ChafaCanvasConfig = undefined;

pub fn init(sigWinchHandler: std.posix.Sigaction.handler_fn) !void {
    try term.init(.{});
    errdefer term.deinit();

    const sa: std.posix.Sigaction = .{
        .handler = .{ .handler = sigWinchHandler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.WINCH, &sa, null);

    try term.uncook(.{ .request_mouse_tracking = true });
    try term.fetchSize();

    term_info = c.chafa_term_db_detect(c.chafa_term_db_get_default(), @ptrCast(std.c.environ)).?;

    const symbol_map = c.chafa_symbol_map_new().?;
    defer c.chafa_symbol_map_unref(symbol_map);
    c.chafa_symbol_map_add_by_tags(symbol_map, c.CHAFA_SYMBOL_TAG_HALF);
    chafa_config = c.chafa_canvas_config_new().?;
    c.chafa_canvas_config_set_symbol_map(chafa_config, symbol_map);
    detectTerminal(chafa_config);
}

pub fn deinit() void {
    c.chafa_term_info_unref(term_info);
    c.chafa_canvas_config_unref(chafa_config);
    term.deinit();
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

const JpegErrorManager = extern struct {
    mgr: c.jpeg_error_mgr,
    setjmp_buffer: c.jmp_buf,

    fn init(self: *JpegErrorManager) *c.jpeg_error_mgr {
        _ = c.jpeg_std_error(&self.mgr);
        self.mgr.error_exit = errorExit;
        self.mgr.output_message = outputMessage;
        return &self.mgr;
    }

    fn errorExit(cinfo: c.j_common_ptr) callconv(.C) void {
        const self: *JpegErrorManager = @ptrCast(cinfo.*.err);
        self.mgr.output_message.?(cinfo);
        c.longjmp(&self.setjmp_buffer, 1);
    }

    fn outputMessage(cinfo: c.j_common_ptr) callconv(.C) void {
        const self: *JpegErrorManager = @ptrCast(cinfo.*.err);
        var buffer: [c.JMSG_LENGTH_MAX]u8 = undefined;
        const ptr: [*c]u8 = @ptrCast(&buffer);
        self.mgr.format_message.?(cinfo, ptr);
        const len = std.mem.len(ptr);
        // std.log.err("{s}", .{ptr[0..len]});
        std.log.debug("jpeglib: {s}", .{ptr[0..len]});
    }
};

fn getCachePath(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    if (std.posix.getenv("XDG_CACHE_HOME")) |xdg_cache| {
        return std.fmt.allocPrint(allocator, "{s}/zpotify/{s}.jpeg", .{ xdg_cache, name });
    } else if (std.posix.getenv("HOME")) |home| {
        return std.fmt.allocPrint(allocator, "{s}/.cache/zpotify/{s}.jpeg", .{ home, name });
    } else {
        return error.EnvironmentVariableNotFound;
    }
}

// do not use with an arena
pub fn fetchImage(allocator: std.mem.Allocator, url: []const u8) !Image {
    const cwd = std.fs.cwd();
    const name = url[std.mem.lastIndexOfScalar(u8, url, '/').? + 1 ..];
    const cache_path = try getCachePath(allocator, name);
    defer allocator.free(cache_path);

    const jpeg_image = if (cwd.openFile(cache_path, .{})) |file| blk: {
        defer file.close();
        break :blk try file.readToEndAlloc(allocator, 1024 * 1024);
    } else |err| blk: {
        if (err != error.FileNotFound) {
            return err;
        }
        try cwd.makePath(cache_path[0..std.mem.lastIndexOfScalar(u8, cache_path, '/').?]);
        const file = try cwd.createFile(cache_path, .{});
        defer file.close();
        errdefer cwd.deleteFile(cache_path) catch {};

        var client: std.http.Client = .{ .allocator = allocator };
        defer client.deinit();
        var response = std.ArrayList(u8).init(allocator);
        defer response.deinit();
        // TODO: this is a big bottleneck
        const result = try client.fetch(.{
            .method = .GET,
            .location = .{ .url = url },
            .response_storage = .{ .dynamic = &response },
            .max_append_size = 1024 * 1024,
        });

        if (result.status != .ok) {
            // std.log.err("Failed to fetch {s}: {d}", .{ url, result.status });
            std.log.debug("Failed to fetch {s}: {d}", .{ url, result.status });
            std.log.debug("Response: {s}", .{response.items});
            return error.BadResponse;
        }

        try file.writeAll(response.items);
        break :blk try response.toOwnedSlice();
    };
    defer allocator.free(jpeg_image);

    var pixels: ?[]const u8 = null;

    var cinfo: c.jpeg_decompress_struct = undefined;
    c.jpeg_create_decompress(&cinfo);
    defer c.jpeg_destroy_decompress(&cinfo);

    var jerr: JpegErrorManager = undefined;
    cinfo.err = jerr.init();

    if (c.setjmp(&jerr.setjmp_buffer) != 0) {
        if (pixels) |pix| {
            allocator.free(pix);
        }
        return error.FailedToReadImage;
    }

    c.jpeg_mem_src(&cinfo, jpeg_image.ptr, jpeg_image.len);
    _ = c.jpeg_read_header(&cinfo, @intFromBool(true));
    _ = c.jpeg_start_decompress(&cinfo);
    defer _ = c.jpeg_finish_decompress(&cinfo);

    if (cinfo.data_precision != 8 or cinfo.output_components != Image.channel_count) {
        return error.UnsupportedImageFormat;
    }

    const row_stride = cinfo.output_width * Image.channel_count;
    pixels = try allocator.alloc(u8, cinfo.image_height * row_stride);
    errdefer allocator.free(pixels.?);

    var index: usize = 0;
    while (index != pixels.?.len) {
        const amt = c.jpeg_read_scanlines(&cinfo, @constCast(@ptrCast(&pixels.?.ptr[index..])), 1);
        if (amt == 0) return error.FailedToReadImage;
        index += amt * row_stride;
    }

    return .{
        .width = cinfo.image_width,
        .height = cinfo.image_height,
        .pixels = pixels.?,
        .allocator = allocator,
    };
}

fn detectTerminal(config: *c.ChafaCanvasConfig) void {
    if (c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_SET_COLOR_FGBG_DIRECT) != 0 and
        c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_SET_COLOR_FG_DIRECT) != 0 and
        c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_SET_COLOR_BG_DIRECT) != 0)
    {
        c.chafa_canvas_config_set_canvas_mode(config, c.CHAFA_CANVAS_MODE_TRUECOLOR);
    } else if (c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_SET_COLOR_FGBG_256) != 0 and
        c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_SET_COLOR_FG_256) != 0 and
        c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_SET_COLOR_BG_256) != 0)
    {
        c.chafa_canvas_config_set_canvas_mode(config, c.CHAFA_CANVAS_MODE_INDEXED_240);
    } else if (c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_SET_COLOR_FGBG_16) != 0 and
        c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_SET_COLOR_FG_16) != 0 and
        c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_SET_COLOR_BG_16) != 0)
    {
        c.chafa_canvas_config_set_canvas_mode(config, c.CHAFA_CANVAS_MODE_INDEXED_16);
    } else if (c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_SET_COLOR_FGBG_8) != 0 and
        c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_SET_COLOR_FG_8) != 0 and
        c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_SET_COLOR_BG_8) != 0)
    {
        c.chafa_canvas_config_set_canvas_mode(config, c.CHAFA_CANVAS_MODE_INDEXED_8);
    } else if (c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_INVERT_COLORS) != 0 and
        c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_RESET_ATTRIBUTES) != 0)
    {
        c.chafa_canvas_config_set_canvas_mode(config, c.CHAFA_CANVAS_MODE_FGBG_BGFG);
    } else {
        c.chafa_canvas_config_set_canvas_mode(config, c.CHAFA_CANVAS_MODE_FGBG);
    }

    if (c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_BEGIN_KITTY_IMMEDIATE_IMAGE_V1) != 0) {
        c.chafa_canvas_config_set_pixel_mode(config, c.CHAFA_PIXEL_MODE_KITTY);
    } else if (c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_BEGIN_SIXELS) != 0 and
        c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_END_SIXELS) != 0)
    {
        c.chafa_canvas_config_set_pixel_mode(config, c.CHAFA_PIXEL_MODE_SIXELS);
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
    pub const Item = union(Kind) {
        track: *const api.Track,
        artist: *const api.Artist,
        album: *const api.Album,
        playlist: *const api.Playlist,
    };
    pub const limit = 20;
    pub const limit_max = 50;

    pub fn init(
        client: *api.Client,
        arena_allocator: std.mem.Allocator, // TODO: move to gpa?
        kind: Kind,
        title: []const u8,
        query: []const u8,
        fetchFn: *const fn (*Table) anyerror!void,
    ) !*Table {
        var table = try arena_allocator.create(Table);
        table.* = .{
            .list = switch (kind) {
                .track => .{ .tracks = .{} },
                .artist => .{ .artists = .{} },
                .album => .{ .albums = .{} },
                .playlist => .{ .playlists = .{} },
            },
            .client = client,
            .allocator = arena_allocator,
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

    pub fn displayed(self: Table) usize {
        // 0                       is the header from cmd.search.drawHeader()
        // 1                       is the title from Table.draw()
        // 2                       are the headers from Table.draw()
        // 3 to term.height - 3    are all items
        // term.height - 2         is the footer from cmd.search.drawFooter()
        // term.height - 1         is the command helper from cmd.search.drawFooter()
        return @min(self.len(), term.height -| 5);
    }

    pub fn resetPosition(self: *Table) void {
        self.start = 0;
        self.selected = 0;
    }

    pub fn draw(self: Table, rc: *spoon.Term.RenderContext, first_row: usize) !void {
        const start = self.start;
        const end = self.start + self.displayed();
        const selected_row = first_row + self.selected - self.start;

        // TODO: find a way to use an inline else or make this better
        switch (self.list) {
            .tracks => |list| try drawTracks(
                list.items[start..end],
                rc,
                first_row,
                selected_row,
                self.imageUrl(),
            ),
            .artists => |list| try drawArtists(
                list.items[start..end],
                rc,
                first_row,
                selected_row,
                self.imageUrl(),
            ),
            .albums => |list| try drawAlbums(
                list.items[start..end],
                rc,
                first_row,
                selected_row,
                self.imageUrl(),
            ),
            .playlists => |list| try drawPlaylists(
                list.items[start..end],
                rc,
                first_row,
                selected_row,
                self.imageUrl(),
            ),
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

    pub fn play(self: Table, device_id: ?[]const u8) !void {
        switch (self.list) {
            .tracks => |list| {
                const uris = [_][]const u8{list.items[self.selected].uri};
                try api.startPlayback(self.client, .{ .uris = &uris }, device_id);
            },
            inline else => |list| {
                const uri = list.items[self.selected].uri;
                try api.startPlayback(self.client, .{ .context_uri = uri }, device_id);
            },
        }
    }

    pub fn save(self: Table) !void {
        switch (self.list) {
            .tracks => |list| try api.saveTracks(self.client, list.items[self.selected].id),
            .artists => |list| try api.followArtists(self.client, list.items[self.selected].id),
            .albums => |list| try api.saveAlbums(self.client, list.items[self.selected].id),
            .playlists => |list| try api.followPlaylist(self.client, list.items[self.selected].id),
        }
    }

    pub fn remove(self: Table) !void {
        switch (self.list) {
            .tracks => |list| try api.removeTracks(self.client, list.items[self.selected].id),
            .artists => |list| try api.unfollowArtists(self.client, list.items[self.selected].id),
            .albums => |list| try api.removeAlbums(self.client, list.items[self.selected].id),
            .playlists => |list| try api.unfollowPlaylist(self.client, list.items[self.selected].id),
        }
    }

    fn imageUrl(self: Table) ?[]const u8 {
        const images = switch (self.list) {
            .tracks => |list| list.items[self.selected].album.images,
            inline else => |list| list.items[self.selected].images,
        };
        // const perfect_size = term.width_pixels * 20 / 100;
        return switch (images.len) {
            0 => null,
            1 => images[0].url,
            else => blk: {
                // we should pick the best one based on the terminal size but
                // this is faster (lol) and it's the best one in most cases
                break :blk images[1].url;
            },
        };
    }

    pub fn len(self: Table) usize {
        switch (self.list) {
            inline else => |list| return list.items.len,
        }
    }

    pub fn selectedItem(self: Table) Item {
        switch (self.list) {
            .tracks => |list| return .{ .track = &list.items[self.selected] },
            .artists => |list| return .{ .artist = &list.items[self.selected] },
            .albums => |list| return .{ .album = &list.items[self.selected] },
            .playlists => |list| return .{ .playlist = &list.items[self.selected] },
        }
    }
};

const Column = struct {
    header_name: []const u8,
    field: @Type(.enum_literal),
    size: usize, // in %
};

fn makeDrawFn(
    comptime T: type,
    comptime title: []const u8,
    comptime columns: []const Column,
    comptime writeField: fn (
        comptime field: @Type(.enum_literal),
        item: T,
        writer: anytype,
    ) anyerror!void,
    comptime hasImage: bool,
) fn ([]const T, *spoon.Term.RenderContext, usize, usize, if (hasImage) ?[]const u8 else void) anyerror!void {
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
            image_url: if (hasImage) ?[]const u8 else void,
        ) !void {
            var row: usize = first_row;

            row += try drawHeaders(rc, row);

            const sel_row = selected_row + row - first_row;
            try drawEntries(items, rc, row, sel_row);

            if (comptime !hasImage) {
                return;
            }

            if (enable_image) {
                const col = term.width * 80 / 100 - 1;
                const size = term.width * 20 / 100 + 2;
                if (image_url) |url| {
                    if (drawImage(rc, url, row, col, size)) {
                        return;
                    } else |err| switch (err) {
                        error.FailedToReadImage => {}, // write "No image"
                        error.UnsupportedImageFormat => {}, // write "No image"
                        else => return err,
                    }
                }

                try rc.moveCursorTo(row, col);
                var rpw = rc.restrictedPaddingWriter(size);
                if (row == sel_row) {
                    try rc.setAttribute(.{ .reverse = true, .fg = .none });
                } else {
                    try rc.setAttribute(.{ .fg = .none });
                }
                try rpw.writer().writeAll("No image");
                try rpw.finish();
            }
        }

        fn drawHeaders(rc: *spoon.Term.RenderContext, row: usize) !usize {
            try rc.setAttribute(.{ .fg = .none, .bold = true });

            try rc.moveCursorTo(row, 0);
            var rpw = rc.restrictedPaddingWriter(term.width);
            const writer = rpw.writer();
            try writer.writeAll(title);
            try rpw.finish();

            var pos: usize = 0;
            const width_divider = widthDivider();
            inline for (columns) |col| {
                try rc.moveCursorTo(row + 1, pos);
                const size = term.width * col.size / width_divider;
                rpw.len_left = size - 1;
                try writer.writeAll(col.header_name);
                pos += size;
            }

            if (comptime hasImage) {
                if (enable_image) {
                    try rc.moveCursorTo(row + 1, pos);
                    const size = term.width * 20 / 100;
                    rpw = rc.restrictedPaddingWriter(size);
                    try writer.writeAll("Image");
                    try rpw.finish();
                }
            }

            return 2;
        }

        fn drawEntries(
            items: []const T,
            rc: *spoon.Term.RenderContext,
            first_row: usize,
            selected_row: usize,
        ) !void {
            const width_divider = widthDivider();
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
                    const size = term.width * col.size / width_divider;
                    rpw.len_left = size - 1;
                    try writeField(col.field, item, writer);
                    pos += size;
                    try rpw.finish();
                }
            }
        }

        fn drawImage(
            rc: *spoon.Term.RenderContext,
            url: []const u8,
            start_x: usize,
            y: usize,
            size: usize,
        ) !void {
            // TODO: allocator
            var image = try fetchImage(std.heap.c_allocator, url);
            defer image.deinit();

            const cell_width = term.width_pixels / term.width;
            const cell_height = term.height_pixels / term.height;
            const font_ratio = @as(f64, @floatFromInt(cell_width)) / @as(f64, @floatFromInt(cell_height));
            var w: c.gint = @intCast(size);
            var h: c.gint = @intCast(size);
            c.chafa_calc_canvas_geometry(
                @intCast(image.width),
                @intCast(image.height),
                &w,
                &h,
                @floatCast(font_ratio),
                @intFromBool(false),
                @intFromBool(false),
            );

            c.chafa_canvas_config_set_cell_geometry(
                chafa_config,
                @intCast(cell_width),
                @intCast(cell_height),
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
            const gs = c.chafa_canvas_print(canvas, term_info);
            defer _ = c.g_string_free(gs, @intFromBool(true));

            var iter = std.mem.tokenizeScalar(u8, gs.*.str[0..gs.*.len], '\n');
            var x: usize = start_x;
            while (iter.next()) |line| : (x += 1) {
                try rc.moveCursorTo(x, y);
                try rc.buffer.writer().writeAll(line);
            }
        }

        fn widthDivider() usize {
            if (comptime !hasImage) {
                return 100;
            }
            // 80% for headers, 20% for image or 100% for headers
            return if (enable_image) 125 else 100;
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
            comptime field: @Type(.enum_literal),
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
    true,
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
            comptime field: @Type(.enum_literal),
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
    true,
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
            comptime field: @Type(.enum_literal),
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
    true,
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
            comptime field: @Type(.enum_literal),
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
    true,
);

pub const drawDevices = makeDrawFn(
    api.Device,
    "Devices",
    &[_]Column{
        .{ .header_name = "Name", .field = .name, .size = 40 },
        .{ .header_name = "ID", .field = .id, .size = 40 },
        .{ .header_name = "Type", .field = .type, .size = 10 },
        .{ .header_name = "Volume", .field = .volume_percent, .size = 10 },
    },
    struct {
        fn writeField(
            comptime field: @Type(.enum_literal),
            item: api.Device,
            writer: anytype,
        ) anyerror!void {
            switch (field) {
                .id => try writer.print("{?s}", .{item.id}),
                .volume_percent => try writer.print("{?d}%", .{item.volume_percent}),
                else => try writer.writeAll(@field(item, @tagName(field))),
            }
        }
    }.writeField,
    false,
);
