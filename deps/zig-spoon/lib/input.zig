// This file is part of zig-spoon, a TUI library for the zig language.
//
// Copyright © 2021 - 2022 Leon Henrik Plickat
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

const std = @import("std");
const ascii = std.ascii;
const fmt = std.fmt;
const unicode = std.unicode;
const meta = std.meta;

// Kitty supports a few more modifiers, but these are the ones that actually
// make sense. Ok, super probably does not make a lot of sense, but complex
// terminal applications commonly support it, so let's just follow their lead.
// Why not shift? Because it is not always trivial to detect and because it is
// not entirely clear how some things should be handled. Should 'A' be parsed
// into a lowercase 'a' with the Shift modifier or an uppercase 'A' with the
// Shift modifier or an uppercase 'A' without Shift? No idea. So let's just
// avoid it for now.
const kitty_alt = 0b10;
const kitty_ctrl = 0b100;
const kitty_super = 0b1000;

pub const Input = struct {
    pub const fromDescription = @import("input_description.zig").parseInputDescription;

    /// Checks whether the Input equals an input description. Description must
    /// be comptime known.
    pub fn eqlDescription(self: Input, comptime descr: []const u8) bool {
        const description_input = comptime Input.fromDescription(descr) catch @compileError("zig-spoon: Bad input descriptor.");
        return meta.eql(self, description_input);
    }

    mod_alt: bool = false,
    mod_ctrl: bool = false,
    mod_super: bool = false,
    content: InputContent,

    pub fn format(
        self: Input,
        comptime fmt_str: []const u8,
        _: fmt.FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        if (fmt_str.len != 0) {
            fmt.invalidFmtError(fmt, self);
        }

        if (self.mod_super) {
            try writer.writeAll("S-");
        }
        if (self.mod_ctrl) {
            try writer.writeAll("C-");
        }
        if (self.mod_alt) {
            try writer.writeAll("A-");
        }

        try writer.print("{}", .{self.content});
    }
};

pub const InputContent = union(enum) {
    unknown: void,
    escape: void,
    arrow_up: void,
    arrow_down: void,
    arrow_left: void,
    arrow_right: void,
    begin: void,
    end: void,
    home: void,
    page_up: void,
    page_down: void,
    delete: void,
    insert: void,
    print: void,
    scroll_lock: void,
    pause: void,
    function: u8,
    codepoint: u21,

    mouse: struct { x: usize, y: usize, button: MouseButton },

    pub fn format(
        self: InputContent,
        comptime fmt_str: []const u8,
        _: fmt.FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        if (fmt_str.len != 0) {
            fmt.invalidFmtError(fmt, self);
        }

        switch (self) {
            .unknown => try writer.writeAll("unknown"),
            .escape => try writer.writeAll("escape"),
            .arrow_up => try writer.writeAll("arrow-up"),
            .arrow_down => try writer.writeAll("arrow-down"),
            .arrow_left => try writer.writeAll("arrow-left"),
            .arrow_right => try writer.writeAll("arrow-right"),
            .begin => try writer.writeAll("begin"),
            .end => try writer.writeAll("end"),
            .home => try writer.writeAll("home"),
            .page_up => try writer.writeAll("page-up"),
            .page_down => try writer.writeAll("page-down"),
            .delete => try writer.writeAll("delete"),
            .insert => try writer.writeAll("insert"),
            .print => try writer.writeAll("print"),
            .scroll_lock => try writer.writeAll("scroll-lock"),
            .pause => try writer.writeAll("pause"),
            .function => |n| try writer.print("F{d}", .{n}),
            .codepoint => |codepoint| {
                if (codepoint == ' ') {
                    try writer.writeAll("space");
                } else if (codepoint == 127) {
                    try writer.writeAll("backspace");
                } else if (codepoint == '\n') {
                    try writer.writeAll("enter");
                } else {
                    try writer.print("{u}", .{codepoint});
                }
            },
            .mouse => |mouse| try writer.print("mouse({}, {}, {s})", .{
                mouse.x,
                mouse.y,
                @tagName(mouse.button),
            }),
        }
    }
};

pub const MouseButton = enum { btn1, btn2, btn3, release, scroll_up, scroll_down };

const InputParser = struct {
    // Types of escape sequences this parser can detect:
    // 1) Legacy alt escape sequences, example: "\x1Ba"
    // 2) Single letter escape sequences, example: "\x1B[H", "\x1BOF"
    // 3) Single integer escape sequences, optionally with kitty modifier, example: "\x1B[2~", "\x1B[2;3~"
    // 4) Kitty unicode sequences, optionally with modifier, example: "\x1B[127u", "\x1B[127;5u"
    // 5) Kitty modified version of 2, example: "\x1B[1;5H"
    // 6) Mouse input related escape sequences (legacy, not SGR yet)

    const Self = @This();

    bytes: ?[]const u8,

    pub fn next(self: *Self) ?Input {
        if (self.bytes == null) return null;
        if (self.bytes.?.len == 0) {
            self.bytes = null;
            return null;
        }

        if (self.bytes.?[0] == '\x1B') {
            return self.maybeEscapeSequence();
        } else {
            return self.utf8();
        }
    }

    fn utf8(self: *Self) Input {
        var advance: usize = 1;
        defer self.advanceBufferBy(advance);

        // Check for legacy control characters.
        switch (self.bytes.?[0]) {
            'a' & '\x1F' => return Input{ .content = .{ .codepoint = 'a' }, .mod_ctrl = true },
            'b' & '\x1F' => return Input{ .content = .{ .codepoint = 'b' }, .mod_ctrl = true },
            'c' & '\x1F' => return Input{ .content = .{ .codepoint = 'c' }, .mod_ctrl = true },
            'd' & '\x1F' => return Input{ .content = .{ .codepoint = 'd' }, .mod_ctrl = true },
            'e' & '\x1F' => return Input{ .content = .{ .codepoint = 'e' }, .mod_ctrl = true },
            'f' & '\x1F' => return Input{ .content = .{ .codepoint = 'f' }, .mod_ctrl = true },
            'g' & '\x1F' => return Input{ .content = .{ .codepoint = 'g' }, .mod_ctrl = true },
            'h' & '\x1F' => return Input{ .content = .{ .codepoint = 'h' }, .mod_ctrl = true },
            'i' & '\x1F' => return Input{ .content = .{ .codepoint = '\t' } },
            'j' & '\x1F' => return Input{ .content = .{ .codepoint = '\n' } }, // Carriage return, which we convert to newline.
            'k' & '\x1F' => return Input{ .content = .{ .codepoint = 'k' }, .mod_ctrl = true },
            'l' & '\x1F' => return Input{ .content = .{ .codepoint = 'l' }, .mod_ctrl = true },
            'm' & '\x1F' => return Input{ .content = .{ .codepoint = '\n' } },
            'n' & '\x1F' => return Input{ .content = .{ .codepoint = 'n' }, .mod_ctrl = true },
            'o' & '\x1F' => return Input{ .content = .{ .codepoint = 'o' }, .mod_ctrl = true },
            'p' & '\x1F' => return Input{ .content = .{ .codepoint = 'p' }, .mod_ctrl = true },
            'q' & '\x1F' => return Input{ .content = .{ .codepoint = 'q' }, .mod_ctrl = true },
            'r' & '\x1F' => return Input{ .content = .{ .codepoint = 'r' }, .mod_ctrl = true },
            's' & '\x1F' => return Input{ .content = .{ .codepoint = 's' }, .mod_ctrl = true },
            't' & '\x1F' => return Input{ .content = .{ .codepoint = 't' }, .mod_ctrl = true },
            'u' & '\x1F' => return Input{ .content = .{ .codepoint = 'u' }, .mod_ctrl = true },
            'v' & '\x1F' => return Input{ .content = .{ .codepoint = 'v' }, .mod_ctrl = true },
            'w' & '\x1F' => return Input{ .content = .{ .codepoint = 'w' }, .mod_ctrl = true },
            'x' & '\x1F' => return Input{ .content = .{ .codepoint = 'x' }, .mod_ctrl = true },
            'y' & '\x1F' => return Input{ .content = .{ .codepoint = 'y' }, .mod_ctrl = true },
            'z' & '\x1F' => return Input{ .content = .{ .codepoint = 'z' }, .mod_ctrl = true },
            else => {
                // The terminal sends us input encoded as utf8.
                advance = unicode.utf8ByteSequenceLength(self.bytes.?[0]) catch return Input{ .content = .unknown };
                // TODO check if buffer is long enough
                const codepoint = unicode.utf8Decode(self.bytes.?[0..advance]) catch return Input{ .content = .unknown };
                return Input{ .content = .{ .codepoint = codepoint } };
            },
        }
    }

    fn maybeEscapeSequence(self: *Self) Input {
        // If \x1B is the last/only byte, it can be safely interpreted as the
        // escape key.
        if (self.bytes.?.len == 1) {
            self.bytes = null;
            return Input{ .content = .escape };
        }

        // Pretty much all common escape sequences begin with '['. All of them
        // are at least three bytes long, so if we have less, this likely is
        // just a press of the scape key followed by a press of the '[' key.
        if (self.bytes.?[1] == '[' and self.bytes.?.len > 2) {
            // There are two types of '[' escape sequences.
            if (ascii.isDigit(self.bytes.?[2])) {
                return self.numericEscapeSequence();
            } else if (self.bytes.?[2] == 'M') {
                return self.legacyMouseEscapeSequence();
            } else {
                return self.singleLetterEscapeSequence();
            }
        }

        // This may be either a M-[a-z] code, or we accidentally received an
        // escape key press and a letter key press together. There is literally
        // no way to differentiate. However the second case is less likely.
        if (ascii.isAlphabetic(self.bytes.?[1]) and ascii.isLower(self.bytes.?[1])) {
            defer self.advanceBufferBy("\x1Ba".len);
            return Input{ .content = .{ .codepoint = self.bytes.?[1] }, .mod_alt = true };
        }

        // There are weird and redundant escape sequences beginning with 'O'
        // that are different for the sake of being different. Or the escape
        // character followed by the letter 'O'. Who knows! Let the heuristics
        // begin.
        if (self.bytes.?[1] == 'O' and self.bytes.?.len > 2) {
            return self.singleLetterEscapeSequence();
        }

        // If this point is reached, this is not an escape sequence, at least
        // not one that follows any common standard I am aware of. So let's just
        // pretend this is an escape key press and then treat all following
        // bytes separately.
        defer self.advanceBufferBy(1);
        return Input{ .content = .escape };
    }

    fn singleLetterEscapeSequence(self: *Self) Input {
        const ev = singleLetterSpecialInput(self.bytes.?[2]) orelse {
            // Oh, turns out this is not an escape sequence. Well
            // this is awkward... Let's hope / pretend that the next
            // few bytes can be interpreted on their own. Well, it
            // might actually be an escape sequence after all, just
            // one that we don't know yet. Would be pretty nice to
            // just skip it. But we have literally no idea how long
            // this sequence is supposed to be, so it's safer to
            // just treat it as separate content pressed.
            self.advanceBufferBy(1);
            return Input{ .content = .escape };
        };
        self.advanceBufferBy("\x1B[A".len);
        return ev;
    }

    fn singleLetterSpecialInput(byte: u8) ?Input {
        return Input{
            .content = switch (byte) {
                'A' => .arrow_up,
                'B' => .arrow_down,
                'C' => .arrow_right,
                'D' => .arrow_left,
                'E' => .begin,
                'F' => .end,
                'H' => .home,
                'P' => .{ .function = 1 },
                'Q' => .{ .function = 2 },
                'R' => .{ .function = 3 },
                'S' => .{ .function = 4 },
                else => return null,
            },
        };
    }

    fn numericEscapeSequence(self: *Self) Input {
        // When this function is called, we already know that:
        // 1) the sequence starts with '\x1B[' (well... duh)
        // 2) self.bytes.?[3] is an ascii numeric caracter
        if (self.bytes.?.len > 3) {
            for (self.bytes.?[3..], 0..) |byte, i| {
                if (!ascii.isDigit(byte)) {
                    const first_num_bytes = self.bytes.?[2 .. i + 3];
                    switch (byte) {
                        '~' => return self.numericTildeEscapeSequence(first_num_bytes, null),
                        'u' => return self.kittyEscapeSequence(first_num_bytes, null),
                        ';' => return self.doubleNumericEscapeSequence(first_num_bytes),
                        else => break, // Unexpected, but not impossible.
                    }
                }
            }
        }

        // It most definitely is an escape sequence, just one we don't know.
        // Since there is a good chance we can guess it's length based on the
        // buffer length, let's  just swallow it.
        self.bytes = null;
        return Input{ .content = .unknown };
    }

    fn legacyMouseEscapeSequence(self: *Self) Input {
        // This parses legacy mouse sequences like "\x1B[M" followed by three bytes.
        // https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h2-Mouse-Tracking
        // TODO also support SGR(1006) sequences.
        if (self.bytes.?.len < "\x1B[Mabc".len) {
            self.advanceBufferBy(1);
            return Input{ .content = .unknown };
        }
        const a = self.bytes.?[3];
        const b = self.bytes.?[4];
        const c = self.bytes.?[5];

        // The first two bits of a encode the button.
        var ret = Input{ .content = .{ .mouse = undefined } };
        if (a & 0b01000000 > 0) {
            ret.content.mouse.button = if (a & 0b00000001 > 0) .scroll_down else .scroll_up;
        } else {
            ret.content.mouse.button = switch (a & 0b00000011) {
                0 => .btn1,
                1 => .btn2,
                2 => .btn3,
                3 => .release,
                else => unreachable,
            };
        }

        // The next three bits of a encode the modifiers.
        const META: u8 = 0b00001000;
        const CTRL: u8 = 0b00010000;
        if (a & META > 0) ret.mod_alt = true;
        if (a & CTRL > 0) ret.mod_ctrl = true;

        // b and c are the x and y coordinates.
        // <rant>
        //   32 is always added to the coordinates to ensure that they are
        //   printable chars. This hack dates back to X10. Yes. Also they are
        //   indexed starting at 1. In zig-spoon we (try to) enforce sane 0
        //   based indexing so that also needs to go. And yet again we uncover
        //   abominations that allow us to laugh in the face of anyone who
        //   claims backwards compatability is a good idea. This is what people
        //   have to deal with if you are too afraid to just break your shitty
        //   API and do it right. And no, bolting a new /optional/ API on top
        //   does not count.
        // </rant>
        ret.content.mouse.x = b -| (32 + 1);
        ret.content.mouse.y = c -| (32 + 1);

        self.advanceBufferBy("\x1b[Mabc".len);
        return ret;
    }

    fn doubleNumericEscapeSequence(self: *Self, first_num_bytes: []const u8) Input {
        const semicolon_index = "\x1B[".len + first_num_bytes.len;
        if (self.bytes.?.len > semicolon_index + 1) {
            for (self.bytes.?[semicolon_index + 1 ..], 0..) |byte, i| {
                if (!ascii.isDigit(byte)) {
                    const second_num_bytes = self.bytes.?[semicolon_index + 1 .. i + semicolon_index + 1];
                    switch (byte) {
                        '~' => return self.numericTildeEscapeSequence(first_num_bytes, second_num_bytes),
                        'u' => return self.kittyEscapeSequence(first_num_bytes, second_num_bytes),
                        'A', 'B', 'C', 'D', 'E', 'F', 'H', 'P', 'Q', 'R', 'S' => {
                            defer self.advanceBufferBy("\x1B[".len + first_num_bytes.len + ";".len + second_num_bytes.len + "A".len);
                            var ev = singleLetterSpecialInput(byte) orelse unreachable;
                            const modifiers = (fmt.parseInt(u16, second_num_bytes, 10) catch return Input{ .content = .unknown }) - @as(u16, 1);
                            ev.mod_alt = (modifiers & kitty_alt) > 0;
                            ev.mod_ctrl = (modifiers & kitty_ctrl) > 0;
                            ev.mod_super = (modifiers & kitty_super) > 0;
                            return ev;
                        },
                        else => break,
                    }
                }
            }
        }

        self.advanceBufferBy(1);
        return Input{ .content = .escape };
    }

    fn numericTildeEscapeSequence(self: *Self, num: []const u8, modifiers_str: ?[]const u8) Input {
        defer {
            var len = "\x1B[~".len + num.len;
            if (modifiers_str) |_| len += modifiers_str.?.len + ";".len;
            self.advanceBufferBy(len);
        }
        const sequences = std.StaticStringMap(Input).initComptime(.{
            .{ "1", .{ .content = .home } },
            .{ "2", .{ .content = .insert } },
            .{ "3", .{ .content = .delete } },
            .{ "4", .{ .content = .home } },
            .{ "5", .{ .content = .page_up } },
            .{ "6", .{ .content = .page_down } },
            .{ "7", .{ .content = .home } },
            .{ "8", .{ .content = .home } },
            .{ "15", .{ .content = .{ .function = 5 } } },
            .{ "17", .{ .content = .{ .function = 6 } } },
            .{ "18", .{ .content = .{ .function = 7 } } },
            .{ "19", .{ .content = .{ .function = 8 } } },
            .{ "20", .{ .content = .{ .function = 9 } } },
            .{ "21", .{ .content = .{ .function = 10 } } },
            .{ "23", .{ .content = .{ .function = 11 } } },
            .{ "24", .{ .content = .{ .function = 12 } } },
        });
        var ev = sequences.get(num) orelse return Input{ .content = .unknown };
        const modifiers = if (modifiers_str) |md| ((fmt.parseInt(u16, md, 10) catch return Input{ .content = .unknown }) - @as(u16, 1)) else undefined;
        ev.mod_alt = if (modifiers_str) |_| ((modifiers & kitty_alt) > 0) else false;
        ev.mod_ctrl = if (modifiers_str) |_| ((modifiers & kitty_ctrl) > 0) else false;
        ev.mod_super = if (modifiers_str) |_| ((modifiers & kitty_super) > 0) else false;
        return ev;
    }

    fn kittyEscapeSequence(self: *Self, codepoint_str: []const u8, modifiers_str: ?[]const u8) Input {
        defer {
            var len = "\x1b[".len + codepoint_str.len + "u".len;
            if (modifiers_str) |_| len += modifiers_str.?.len + ";".len;
            self.advanceBufferBy(len);
        }
        const codepoint = fmt.parseInt(u21, codepoint_str, 10) catch return Input{ .content = .unknown };
        const modifiers = if (modifiers_str) |md| ((fmt.parseInt(u16, md, 10) catch return Input{ .content = .unknown }) - @as(u16, 1)) else undefined;
        return Input{
            .content = switch (codepoint) {
                9 => .{ .codepoint = '\t' },
                57414, 10, 13 => .{ .codepoint = '\n' }, // Both newline and carriage return will return a newline.
                27 => .escape,
                57359 => .scroll_lock,
                57361 => .print,
                57362 => .pause,
                57409 => .{ .codepoint = ',' },
                57410 => .{ .codepoint = '/' },
                57411 => .{ .codepoint = '*' },
                57412 => .{ .codepoint = '-' },
                57413 => .{ .codepoint = '+' },
                57415 => .{ .codepoint = '=' },
                57417 => .arrow_left,
                57418 => .arrow_right,
                57419 => .arrow_up,
                57420 => .arrow_down,
                57421 => .page_up,
                57422 => .page_down,
                57423 => .home,
                57424 => .end,
                57425 => .insert,
                57426 => .delete,
                else => .{ .codepoint = codepoint },
            },
            .mod_alt = if (modifiers_str) |_| ((modifiers & kitty_alt) > 0) else false,
            .mod_ctrl = if (modifiers_str) |_| ((modifiers & kitty_ctrl) > 0) else false,
            .mod_super = if (modifiers_str) |_| ((modifiers & kitty_super) > 0) else false,
        };
    }

    fn advanceBufferBy(self: *Self, amount: usize) void {
        self.bytes = if (self.bytes.?.len > amount) self.bytes.?[amount..] else null;
    }
};

pub fn inputParser(bytes: []const u8) InputParser {
    return .{ .bytes = bytes };
}

test "input parser: Mulitple bytes, legacy escape sequence embedded within" {
    const testing = std.testing;
    var parser = inputParser("abc\x1B[Ad");
    try testing.expectEqual(Input{ .content = .{ .codepoint = 'a' } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = 'b' } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = 'c' } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .arrow_up }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = 'd' } }, parser.next().?);
    try testing.expect(parser.next() == null);
}

test "input parser: Newline, carriage return, enter" {
    const testing = std.testing;
    var parser = inputParser("\r\n\x1B[10;1u\x1B[13;1u");
    try testing.expectEqual(Input{ .content = .{ .codepoint = '\n' } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = '\n' } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = '\n' } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = '\n' } }, parser.next().?);
    try testing.expect(parser.next() == null);
}

test "input parser: Mulitple legacy escape sequences and legacy control characters" {
    const testing = std.testing;
    var parser = inputParser("\x1Ba\x1B[2~\x1B[H" ++ [_]u8{'b' & '\x1F'} ++ [_]u8{'m' & '\x1F'} ++ [_]u8{'i' & '\x1F'});
    try testing.expectEqual(Input{ .content = .{ .codepoint = 'a' }, .mod_alt = true }, parser.next().?);
    try testing.expectEqual(Input{ .content = .insert }, parser.next().?);
    try testing.expectEqual(Input{ .content = .home }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = 'b' }, .mod_ctrl = true }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = '\n' } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = '\t' } }, parser.next().?);
    try testing.expect(parser.next() == null);
}

test "input parser: kitty" {
    const testing = std.testing;
    var parser = inputParser("\x1B[1;7A\x1B[27u\x1B[2;3~");
    try testing.expectEqual(Input{ .content = .arrow_up, .mod_alt = true, .mod_ctrl = true }, parser.next().?);
    try testing.expectEqual(Input{ .content = .escape }, parser.next().?);
    try testing.expectEqual(Input{ .content = .insert, .mod_alt = true }, parser.next().?);
    try testing.expect(parser.next() == null);
}

test "input parser: Mixed legacy terminal utf8 and kitty u21 codepoint" {
    const testing = std.testing;
    var parser = inputParser("µ\x1B[181;1u");
    try testing.expectEqual(Input{ .content = .{ .codepoint = '\xB5' } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = '\xB5' } }, parser.next().?);
    try testing.expect(parser.next() == null);
}

test "input parser: Some random weird edge cases" {
    const testing = std.testing;
    var parser = inputParser("\x1B\x1BO\x1Ba");
    try testing.expectEqual(Input{ .content = .escape }, parser.next().?);
    try testing.expectEqual(Input{ .content = .escape }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = 'O' } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = 'a' }, .mod_alt = true }, parser.next().?);
    try testing.expect(parser.next() == null);
}

test "input parser: Unfinished numerical escape sequence" {
    const testing = std.testing;
    var parser = inputParser("\x1B[2;");
    try testing.expectEqual(Input{ .content = .escape }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = '[' } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = '2' } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = ';' } }, parser.next().?);
    try testing.expect(parser.next() == null);
}

test "input parser: Unfinished [ single letter escape sequence" {
    const testing = std.testing;
    var parser = inputParser("\x1B[");
    try testing.expectEqual(Input{ .content = .escape }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = '[' } }, parser.next().?);
    try testing.expect(parser.next() == null);
}

test "input parser: Unfinished O single letter escape sequence" {
    const testing = std.testing;
    var parser = inputParser("\x1BO");
    try testing.expectEqual(Input{ .content = .escape }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = 'O' } }, parser.next().?);
    try testing.expect(parser.next() == null);
}

test "input parser: Just escape" {
    const testing = std.testing;
    var parser = inputParser("\x1B");
    try testing.expectEqual(Input{ .content = .escape }, parser.next().?);
    try testing.expect(parser.next() == null);
}

test "input parser: Unrecognized single letter escape sequences" {
    const testing = std.testing;
    var parser = inputParser("\x1BOZ\x1B[Y");
    try testing.expectEqual(Input{ .content = .escape }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = 'O' } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = 'Z' } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .escape }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = '[' } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = 'Y' } }, parser.next().?);
    try testing.expect(parser.next() == null);
}

test "input parser: bad unicode" {
    const testing = std.testing;
    var parser = inputParser("\x1B[999999999999u");
    try testing.expectEqual(Input{ .content = .unknown }, parser.next().?);
    try testing.expect(parser.next() == null);
}

test "input parser: mixing plain ascii with multi-byte codepoints" {
    const testing = std.testing;
    var parser = inputParser("a↑b↓c");
    try testing.expectEqual(Input{ .content = .{ .codepoint = 'a' } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = 8593 } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = 'b' } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = 8595 } }, parser.next().?);
    try testing.expectEqual(Input{ .content = .{ .codepoint = 'c' } }, parser.next().?);
    try testing.expect(parser.next() == null);
}
