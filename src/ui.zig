const std = @import("std");
const spoon = @import("spoon");
const api = @import("api.zig");

pub var term: spoon.Term = undefined;

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
