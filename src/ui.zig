const std = @import("std");
const spoon = @import("spoon");
const api = @import("api.zig");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("jpeglib.h");
    @cInclude("chafa/chafa.h");
});

pub var term: spoon.Term = undefined;
pub var cinfo: c.jpeg_decompress_struct = undefined;
pub var chafa_symbol_map: *c.ChafaSymbolMap = undefined;
pub var chafa_config: *c.ChafaCanvasConfig = undefined;

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

    chafa_symbol_map = c.chafa_symbol_map_new().?;
    c.chafa_symbol_map_add_by_tags(chafa_symbol_map, c.CHAFA_SYMBOL_TAG_ALL);
    chafa_config = c.chafa_canvas_config_new().?;
    c.chafa_canvas_config_set_geometry(chafa_config, 15, 15); // TODO + also update it based on term size (with sigwinch)
    try detectTerminal(chafa_config);
}

pub fn deinit() void {
    c.chafa_canvas_config_unref(chafa_config);
    c.chafa_symbol_map_unref(chafa_symbol_map);
    term.deinit() catch unreachable;
}

// TODO: move handleSigWinch, render, drawHeader and drawFooter here?

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

fn drawImage(rc: *spoon.Term.RenderContext) !void {
    // const url = current_table.imageUrl() orelse return;
    const url = "";

    // TODO: allocator
    var image = try fetchAlbumImage(std.heap.c_allocator, url);
    defer image.deinit();

    const symbol_map = c.chafa_symbol_map_new().?;
    defer c.chafa_symbol_map_unref(symbol_map);
    c.chafa_symbol_map_add_by_tags(symbol_map, c.CHAFA_SYMBOL_TAG_ALL);
    const config = c.chafa_canvas_config_new().?;
    defer c.chafa_canvas_config_unref(config);
    c.chafa_canvas_config_set_geometry(config, 15, 15); // TODO: size based on terminal size
    try detectTerminal(config);
    c.chafa_canvas_config_set_symbol_map(config, symbol_map);

    const canvas = c.chafa_canvas_new(config).?;
    defer c.chafa_canvas_unref(canvas);

    c.chafa_canvas_draw_all_pixels(
        canvas,
        c.CHAFA_PIXEL_RGB8,
        image.pixels.ptr,
        @intCast(image.width),
        @intCast(image.height),
        @intCast(image.width * Image.channel_count),
    );
    const gs = c.chafa_canvas_build_ansi(canvas);
    defer _ = c.g_string_free(gs, @intFromBool(true));

    var iter = std.mem.splitScalar(u8, gs.*.str[0..gs.*.len], '\n');
    var i: usize = 0;
    while (iter.next()) |line| : (i += 1) {
        try rc.moveCursorTo(i, 0);
        try rc.buffer.writer().writeAll(line);
    }
}

// do not use with an arena
pub fn fetchAlbumImage(allocator: std.mem.Allocator, url: []const u8) !Image {
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

    // TODO
    var err_mgr: c.jpeg_error_mgr = undefined;
    cinfo.err = c.jpeg_std_error(&err_mgr);

    c.jpeg_create_decompress(&cinfo);
    defer c.jpeg_destroy_decompress(&cinfo);
    c.jpeg_mem_src(&cinfo, response.items.ptr, response.items.len);
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

fn detectTerminal(config: *c.ChafaCanvasConfig) !void {
    const term_info = c.chafa_term_db_detect(c.chafa_term_db_get_default(), std.c.environ) orelse {
        return error.TermInfoNotFound;
    };

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
    } else if (c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_BEGIN_ITERM2_IMAGE) != 0 and
        c.chafa_term_info_have_seq(term_info, c.CHAFA_TERM_SEQ_END_ITERM2_IMAGE) != 0)
    {
        c.chafa_canvas_config_set_pixel_mode(config, c.CHAFA_PIXEL_MODE_ITERM2);
    } else {
        c.chafa_canvas_config_set_pixel_mode(config, c.CHAFA_PIXEL_MODE_SYMBOLS);
    }
}

pub const Column = struct {
    header_name: []const u8,
    field: @Type(.EnumLiteral),
    size: usize, // in %
};

pub fn Table(
    comptime T: type,
    comptime title: []const u8,
    comptime columns: []const Column,
    comptime writeField: fn (comptime field: @Type(.EnumLiteral), item: T, writer: anytype) anyerror!void,
) type {
    comptime {
        var size = 0;
        for (columns) |col| {
            size += col.size;
        }
        std.debug.assert(size == 100);
    }

    return struct {
        items: []const T,

        const Self = @This();

        pub fn draw(
            self: Self,
            rc: *spoon.Term.RenderContext,
            first_row: usize,
            selected_row: usize,
        ) !void {
            try Self.drawHeader(rc, first_row);
            try self.drawEntries(rc, first_row + 2, selected_row + 2);
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
            self: Self,
            rc: *spoon.Term.RenderContext,
            first_row: usize,
            selected_row: usize,
        ) !void {
            for (self.items, first_row..) |item, row| {
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
    };
}

pub const TrackTable = Table(
    api.Track,
    "Tracks",
    &[_]Column{
        .{ .header_name = "Name", .field = .name, .size = 40 },
        .{ .header_name = "Album", .field = .album, .size = 20 },
        .{ .header_name = "Artists", .field = .artists, .size = 30 },
        .{ .header_name = "Duration", .field = .duration_ms, .size = 10 },
    },
    struct {
        fn writeField(comptime field: @Type(.EnumLiteral), item: api.Track, writer: anytype) anyerror!void {
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

pub const ArtistTable = Table(
    api.Artist,
    "Artists",
    &[_]Column{
        .{ .header_name = "Name", .field = .name, .size = 30 },
        .{ .header_name = "Genres", .field = .genres, .size = 55 },
        .{ .header_name = "Followers", .field = .followers, .size = 15 },
    },
    struct {
        fn writeField(comptime field: @Type(.EnumLiteral), item: api.Artist, writer: anytype) anyerror!void {
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

pub const AlbumTable = Table(
    api.Album,
    "Albums",
    &[_]Column{
        .{ .header_name = "Name", .field = .name, .size = 40 },
        .{ .header_name = "Artists", .field = .artists, .size = 40 },
        .{ .header_name = "Release Date", .field = .release_date, .size = 20 },
    },
    struct {
        fn writeField(comptime field: @Type(.EnumLiteral), item: api.Album, writer: anytype) anyerror!void {
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

pub const PlaylistTable = Table(
    api.Playlist,
    "Playlists",
    &[_]Column{
        .{ .header_name = "Name", .field = .name, .size = 30 },
        .{ .header_name = "Description", .field = .description, .size = 50 },
        .{ .header_name = "Owner", .field = .owner, .size = 15 },
        .{ .header_name = "Tracks", .field = .tracks, .size = 5 },
    },
    struct {
        fn writeField(comptime field: @Type(.EnumLiteral), item: api.Playlist, writer: anytype) anyerror!void {
            switch (field) {
                .owner => try writer.print("{?s}", .{item.owner.display_name}),
                .tracks => try writer.print("{d}", .{item.tracks.total}),
                else => try writer.writeAll(@field(item, @tagName(field))),
            }
        }
    }.writeField,
);

// fn draw(
//     comptime T: type,
//     comptime title: []const u8,
//     comptime columns: []const Column,
//     comptime writeField: fn (comptime field: @Type(.EnumLiteral), item: T, writer: anytype) anyerror!void,
//     rc: *spoon.Term.RenderContext,
//     items: []const T,
//     first_row: usize,
// ) !void {
//     comptime {
//         var size = 0;
//         for (columns) |col| {
//             size += col.size;
//         }
//         std.debug.assert(size == 100);
//     }

//     // header
//     {
//         try rc.setAttribute(.{ .fg = .none, .bold = true });

//         try rc.moveCursorTo(first_row, 0);
//         var rpw = rc.restrictedPaddingWriter(term.width);
//         const writer = rpw.writer();
//         try writer.writeAll(title);
//         try rpw.finish();

//         var pos: usize = 0;
//         inline for (columns) |col| {
//             try rc.moveCursorTo(first_row + 1, pos);
//             const size = term.width * col.size / 100;
//             rpw.len_left = size - 1;
//             try writer.writeAll(col.header_name);
//             pos += size;
//         }
//         try rpw.finish();
//     }

//     // entries
//     for (items, first_row + 2..) |item, row| {
//         // std.log.debug("{d} {s}", .{row, item.name});
//         try rc.moveCursorTo(row, 0);
//         var rpw = rc.restrictedPaddingWriter(term.width);
//         const writer = rpw.writer();

//         if (row == selection + first_row + 1) {
//             try rc.setAttribute(.{ .reverse = true, .fg = .none });
//             try rpw.pad();
//         } else {
//             try rc.setAttribute(.{ .fg = .none });
//         }

//         var pos: usize = 0;
//         inline for (columns) |col| {
//             try rc.moveCursorTo(row, pos);
//             const size = term.width * col.size / 100;
//             rpw.len_left = size - 1;
//             try writeField(col.field, item, writer);
//             pos += size;
//             try rpw.finish();
//         }
//     }
// }
