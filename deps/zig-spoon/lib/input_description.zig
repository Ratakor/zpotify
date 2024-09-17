// This file is part of zig-spoon, a TUI library for the zig language.
//
// Copyright © 2022 Leon Henrik Plickat
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
const fmt = std.fmt;
const mem = std.mem;
const unicode = std.unicode;

const Input = @import("input.zig").Input;

/// A parser to convert human readable/writable utf8 plain-text input
/// descriptions into Input structs.
/// Examples:
///   "M-x" -> Input{ .content = .{ .codepoint = 'x' }, .mod_alt = true }
///   "C-a" -> Input{ .content = .{ .codepoint = 'a' }, .mod_ctrl = true }
pub fn parseInputDescription(str: []const u8) !Input {
    // TODO specifying the same mod more than once is an error
    var ret = Input{ .content = .unknown };

    var buf: []const u8 = str;
    while (true) {
        if (buf.len == 0) {
            return error.UnkownBadDescription;
        } else if (mem.startsWith(u8, buf, "M-")) {
            try addMod(&ret, .alt);
            buf = buf["M-".len..];
        } else if (mem.startsWith(u8, buf, "A-")) {
            try addMod(&ret, .alt);
            buf = buf["A-".len..];
        } else if (mem.startsWith(u8, buf, "Alt-")) {
            try addMod(&ret, .alt);
            buf = buf["Alt-".len..];
        } else if (mem.startsWith(u8, buf, "C-")) {
            try addMod(&ret, .control);
            buf = buf["C-".len..];
        } else if (mem.startsWith(u8, buf, "Ctrl-")) {
            try addMod(&ret, .control);
            buf = buf["Ctrl-".len..];
        } else if (mem.startsWith(u8, buf, "S-")) {
            try addMod(&ret, .super);
            buf = buf["S-".len..];
        } else if (mem.startsWith(u8, buf, "Super-")) {
            buf = buf["Super-".len..];
            try addMod(&ret, .super);
        } else if (mem.eql(u8, buf, "escape")) {
            ret.content = .escape;
            break;
        } else if (mem.eql(u8, buf, "arrow-up")) {
            ret.content = .arrow_up;
            break;
        } else if (mem.eql(u8, buf, "arrow-down")) {
            ret.content = .arrow_down;
            break;
        } else if (mem.eql(u8, buf, "arrow-left")) {
            ret.content = .arrow_left;
            break;
        } else if (mem.eql(u8, buf, "arrow-right")) {
            ret.content = .arrow_right;
            break;
        } else if (mem.eql(u8, buf, "end")) {
            ret.content = .end;
            break;
        } else if (mem.eql(u8, buf, "home")) {
            ret.content = .home;
            break;
        } else if (mem.eql(u8, buf, "page-up")) {
            ret.content = .page_up;
            break;
        } else if (mem.eql(u8, buf, "page-down")) {
            ret.content = .page_down;
            break;
        } else if (mem.eql(u8, buf, "delete")) {
            ret.content = .delete;
            break;
        } else if (mem.eql(u8, buf, "insert")) {
            ret.content = .insert;
            break;
        } else if (mem.eql(u8, buf, "space")) {
            ret.content = .{ .codepoint = ' ' };
            break;
        } else if (mem.eql(u8, buf, "backspace")) {
            ret.content = .{ .codepoint = 127 };
            break;
        } else if (mem.eql(u8, buf, "enter") or mem.eql(u8, buf, "return")) {
            ret.content = .{ .codepoint = '\n' };
            break;
        } else if (mem.eql(u8, buf, "print")) {
            ret.content = .print;
            break;
        } else if (mem.eql(u8, buf, "scroll-lock")) {
            ret.content = .scroll_lock;
            break;
        } else if (mem.eql(u8, buf, "pause")) {
            ret.content = .pause;
            break;
        } else if (mem.eql(u8, buf, "begin")) {
            ret.content = .begin;
            break;
        } else if (buf[0] == 'F') {
            ret.content = .{ .function = fmt.parseInt(u8, buf[1..], 10) catch return error.UnkownBadDescription };
            break;
        } else {
            const len = unicode.utf8ByteSequenceLength(buf[0]) catch return error.UnkownBadDescription;
            if (buf.len != len) return error.UnkownBadDescription;
            ret.content = .{ .codepoint = unicode.utf8Decode(buf) catch return error.UnkownBadDescription };
            break;
        }
    }

    if (ret.content == .unknown) {
        return error.UnkownBadDescription;
    } else {
        return ret;
    }
}

const Mod = enum { alt, control, super };

fn addMod(in: *Input, mod: Mod) !void {
    switch (mod) {
        .alt => {
            if (in.mod_alt) return error.DuplicateMod;
            in.mod_alt = true;
        },
        .control => {
            if (in.mod_ctrl) return error.DuplicateMod;
            in.mod_ctrl = true;
        },
        .super => {
            if (in.mod_super) return error.DuplicateMod;
            in.mod_super = true;
        },
    }
}

test "input description parser: good input" {
    const testing = std.testing;
    try testing.expectEqual(
        Input{ .content = .{ .codepoint = 'a' } },
        try parseInputDescription("a"),
    );
    try testing.expectEqual(
        Input{ .content = .{ .codepoint = 'b' }, .mod_ctrl = true },
        try parseInputDescription("C-b"),
    );
    try testing.expectEqual(
        Input{ .content = .{ .codepoint = 'c' }, .mod_ctrl = true },
        try parseInputDescription("Ctrl-c"),
    );
    try testing.expectEqual(
        Input{ .content = .{ .codepoint = 'd' }, .mod_alt = true },
        try parseInputDescription("M-d"),
    );
    try testing.expectEqual(
        Input{ .content = .{ .codepoint = 'D' }, .mod_alt = true },
        try parseInputDescription("A-D"),
    );
    try testing.expectEqual(
        Input{ .content = .{ .codepoint = 'e' }, .mod_alt = true },
        try parseInputDescription("Alt-e"),
    );
    try testing.expectEqual(
        Input{ .content = .{ .codepoint = 'f' }, .mod_ctrl = true, .mod_alt = true },
        try parseInputDescription("C-M-f"),
    );
    try testing.expectEqual(
        Input{ .content = .{ .codepoint = 'g' }, .mod_ctrl = true, .mod_alt = true },
        try parseInputDescription("M-C-g"),
    );
    try testing.expectEqual(
        Input{ .content = .{ .codepoint = 'h' }, .mod_ctrl = true, .mod_alt = true },
        try parseInputDescription("M-Ctrl-h"),
    );
    try testing.expectEqual(
        Input{ .content = .{ .function = 1 } },
        try parseInputDescription("F1"),
    );
    try testing.expectEqual(
        Input{ .content = .{ .function = 10 }, .mod_alt = true },
        try parseInputDescription("M-F10"),
    );
    try testing.expectEqual(
        Input{ .content = .{ .codepoint = ' ' } },
        try parseInputDescription("space"),
    );
    try testing.expectEqual(
        Input{ .content = .escape },
        try parseInputDescription("escape"),
    );
    try testing.expectEqual(
        Input{ .content = .escape, .mod_super = true },
        try parseInputDescription("S-escape"),
    );
    try testing.expectEqual(
        Input{ .content = .escape, .mod_super = true, .mod_alt = true },
        try parseInputDescription("M-S-escape"),
    );
    try testing.expectEqual(
        Input{ .content = .{ .codepoint = '\n' } },
        try parseInputDescription("return"),
    );
    try testing.expectEqual(
        Input{ .content = .{ .codepoint = '\n' }, .mod_super = true },
        try parseInputDescription("S-return"),
    );
    try testing.expectEqual(
        Input{ .content = .{ .codepoint = 127 } },
        try parseInputDescription("backspace"),
    );
    try testing.expectEqual(
        Input{ .content = .{ .codepoint = '\xB5' } },
        try parseInputDescription("µ"),
    );
    try testing.expectEqual(
        Input{ .content = .{ .codepoint = '\xB5' }, .mod_ctrl = true },
        try parseInputDescription("Ctrl-µ"),
    );
}

test "input description parser: bad input" {
    const testing = std.testing;
    try testing.expectError(error.DuplicateMod, parseInputDescription("M-M-escape"));
    try testing.expectError(error.DuplicateMod, parseInputDescription("M-Alt-escape"));
    try testing.expectError(error.UnkownBadDescription, parseInputDescription("M-"));
    try testing.expectError(error.UnkownBadDescription, parseInputDescription("M-S-"));
    try testing.expectError(error.UnkownBadDescription, parseInputDescription("aa"));
    try testing.expectError(error.UnkownBadDescription, parseInputDescription("a-a"));
    try testing.expectError(error.UnkownBadDescription, parseInputDescription("escap"));
    try testing.expectError(error.UnkownBadDescription, parseInputDescription("\xB5"));
}
