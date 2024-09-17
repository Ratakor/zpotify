// This file is part of zig-spoon, a TUI library for the zig language.
//
// Copyright © 2021 Leon Henrik Plickat
// Copyright © 2022 Hugo Machet
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License version 3 as published
// by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

const Self = @This();

pub const Colour = union(enum) {
    pub const fromDescription = @import("colour_description.zig").parseColourDescription;

    // TODO since the default colours are also part of the 256 colour spec,
    //      maybe we should just use that. The dump function would then special
    //      case them and use legacy escape sequences.
    none,
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,

    @"256": u8,
    rgb: [3]u8,
};

fg: Colour = .white,
bg: Colour = .none,

bold: bool = false,
dimmed: bool = false,
italic: bool = false,
underline: bool = false,
blinking: bool = false,
reverse: bool = false,
hidden: bool = false,
overline: bool = false,
strikethrough: bool = false,

pub fn eql(self: Self, other: Self) bool {
    inline for (@typeInfo(Self).Struct.fields) |field| {
        if (@field(self, field.name) != @field(other, field.name)) return false;
    }
    return true;
}

pub fn dump(self: Self, writer: anytype) !void {
    try writer.writeAll("\x1B[0");
    if (self.bold) try writer.writeAll(";1");
    if (self.dimmed) try writer.writeAll(";2");
    if (self.italic) try writer.writeAll(";3");
    if (self.underline) try writer.writeAll(";4");
    if (self.blinking) try writer.writeAll(";5");
    if (self.reverse) try writer.writeAll(";7");
    if (self.hidden) try writer.writeAll(";8");
    if (self.overline) try writer.writeAll(";53");
    if (self.strikethrough) try writer.writeAll(";9");
    switch (self.fg) {
        .none => {},
        .black => try writer.writeAll(";30"),
        .red => try writer.writeAll(";31"),
        .green => try writer.writeAll(";32"),
        .yellow => try writer.writeAll(";33"),
        .blue => try writer.writeAll(";34"),
        .magenta => try writer.writeAll(";35"),
        .cyan => try writer.writeAll(";36"),
        .white => try writer.writeAll(";37"),
        .bright_black => try writer.writeAll(";90"),
        .bright_red => try writer.writeAll(";91"),
        .bright_green => try writer.writeAll(";92"),
        .bright_yellow => try writer.writeAll(";93"),
        .bright_blue => try writer.writeAll(";94"),
        .bright_magenta => try writer.writeAll(";95"),
        .bright_cyan => try writer.writeAll(";96"),
        .bright_white => try writer.writeAll(";97"),
        .@"256" => {
            try writer.writeAll(";38;5");
            try writer.print(";{d}", .{self.fg.@"256"});
        },
        .rgb => {
            try writer.writeAll(";38;2");
            try writer.print(";{d};{d};{d}", .{
                self.fg.rgb[0],
                self.fg.rgb[1],
                self.fg.rgb[2],
            });
        },
    }
    switch (self.bg) {
        .none => {},
        .black => try writer.writeAll(";40"),
        .red => try writer.writeAll(";41"),
        .green => try writer.writeAll(";42"),
        .yellow => try writer.writeAll(";43"),
        .blue => try writer.writeAll(";44"),
        .magenta => try writer.writeAll(";45"),
        .cyan => try writer.writeAll(";46"),
        .white => try writer.writeAll(";74"),
        .bright_black => try writer.writeAll(";100"),
        .bright_red => try writer.writeAll(";101"),
        .bright_green => try writer.writeAll(";102"),
        .bright_yellow => try writer.writeAll(";103"),
        .bright_blue => try writer.writeAll(";104"),
        .bright_magenta => try writer.writeAll(";105"),
        .bright_cyan => try writer.writeAll(";106"),
        .bright_white => try writer.writeAll(";107"),
        .@"256" => {
            try writer.writeAll(";48;5");
            try writer.print(";{d}", .{self.bg.@"256"});
        },
        .rgb => {
            try writer.writeAll(";48;2");
            try writer.print(";{d};{d};{d}", .{
                self.bg.rgb[0],
                self.bg.rgb[1],
                self.bg.rgb[2],
            });
        },
    }
    try writer.writeAll("m");
}
