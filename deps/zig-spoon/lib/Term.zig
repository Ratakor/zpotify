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

const builtin = @import("builtin");
const std = @import("std");
const ascii = std.ascii;
const io = std.io;
const mem = std.mem;
const os = std.posix.system;
const WriteError = std.posix.WriteError;
const OpenError = std.posix.OpenError;
const unicode = std.unicode;
const debug = std.debug;
const math = std.math;

const Attribute = @import("Attribute.zig");
const spells = @import("spells.zig");
const rpw = @import("restricted_padding_writer.zig");

const Self = @This();

const AltScreenConfig = struct {
    request_kitty_keyboard_protocol: bool = true,
    request_mouse_tracking: bool = false,
};

const TermConfig = struct {
    tty_name: []const u8 = "/dev/tty",
};

/// Are we in raw or cooked mode?
cooked: bool = true,

/// The original termios configuration saved when entering raw mode.
cooked_termios: os.termios = undefined,

/// Size of the terminal, updated fetchSize() is called.
width: usize = undefined,
height: usize = undefined,

/// Are we currently rendering?
currently_rendering: bool = false,

/// Descriptor of opened file.
tty: ?os.fd_t = null,

/// Dumb writer. Don't use.
const Writer = io.Writer(os.fd_t, WriteError, std.posix.write);
fn writer(self: Self) Writer {
    return .{ .context = self.tty.? };
}

/// Buffered writer. Use.
const BufferedWriter = io.BufferedWriter(4096, Writer);
fn bufferedWriter(self: Self) BufferedWriter {
    return io.bufferedWriter(self.writer());
}

pub fn init(self: *Self, term_config: TermConfig) !void {
    // Only allow a single successful call to init.
    debug.assert(self.tty == null);
    const flags = os.O{ .ACCMODE = std.posix.ACCMODE.RDWR };
    self.* = .{
        .tty = try std.posix.open(term_config.tty_name, flags, 0),
    };
}

pub fn deinit(self: *Self) !void {
    debug.assert(!self.currently_rendering);

    // Allow multiple calls to deinit, even if init never succeeded. This makes
    // application logic slightly simpler.
    if (self.tty == null) return;

    // It's probably a good idea to cook the terminal on exit.
    if (!self.cooked) self.cook() catch {};

    std.posix.close(self.tty.?);
    self.tty = null;
}

pub fn readInput(self: *Self, buffer: []u8) !usize {
    debug.assert(self.tty != null);
    debug.assert(!self.currently_rendering);
    debug.assert(!self.cooked);
    return try std.posix.read(self.tty.?, buffer);
}

/// Enter raw mode.
pub fn uncook(self: *Self, config: AltScreenConfig) !void {
    debug.assert(self.tty != null);

    if (!self.cooked) return;
    self.cooked = false;

    // The information on the various flags and escape sequences is pieced
    // together from various sources, including termios(3) and
    // https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html.
    // TODO: IUTF8 ?

    self.cooked_termios = try std.posix.tcgetattr(self.tty.?);
    errdefer self.cook() catch {};

    var raw = self.cooked_termios;

    raw.lflag = os.tc_lflag_t{
        // Stop the terminal from displaying pressed keys.
        .ECHO = false,

        // Disable canonical ("cooked") mode. Allows us to read inputs
        // byte-wise instead of line-wise.
        .ICANON = false,

        // Disable signals for Ctrl-C (SIGINT) and Ctrl-Z (SIGTSTP),
        // so we can handle them as normal escape sequences.
        .ISIG = false,

        // Disable input preprocessing. This allows us to handle
        // Ctrl-V, which would otherwise be intercepted by some
        // terminals.
        .IEXTEN = false,
    };

    raw.iflag = os.tc_iflag_t{
        // Disable software control flow. This allows us to handle
        // Ctrl-S and Ctrl-Q.
        .IXON = false,

        // Disable converting carriage returns to newlines. Allows us
        // to handle Ctrl-J and Ctrl-M.
        .ICRNL = false,

        // Disable converting sending SIGINT on break
        // conditions. Likely has no effect on anything remotely
        // modern.
        .BRKINT = false,

        // Disable parity checking. Likely has no effect on anything
        // remotely modern.
        .INPCK = false,

        // Disable stripping the 8th bit of characters. Likely has no
        // effect on anything remotely modern.
        .ISTRIP = false,
    };

    // Disable output processing. Common output processing includes
    // prefixing newline with a carriage return.
    raw.oflag = os.tc_oflag_t{
        .OPOST = false,
    };

    // Set the character size to 8 bits per byte. Likely has no
    // efffect on anything remotely modern.
    raw.cflag = os.tc_cflag_t{
        .CSIZE = os.CSIZE.CS8,
    };

    // With these settings, the read syscall will immediately return
    // when it can't get any bytes. This allows poll to drive our
    // loop.
    raw.cc[5] = 0; // os.V.TIME
    raw.cc[6] = 0; // os.V.MIN

    try std.posix.tcsetattr(self.tty.?, .FLUSH, raw);

    var bufwriter = self.bufferedWriter();
    const wrtr = bufwriter.writer();
    try wrtr.writeAll(
        spells.save_cursor_position ++
            spells.save_cursor_position ++
            spells.enter_alt_buffer ++
            spells.overwrite_mode ++
            spells.reset_auto_wrap ++
            spells.reset_auto_repeat ++
            spells.reset_auto_interlace ++
            spells.hide_cursor,
    );
    if (config.request_kitty_keyboard_protocol) {
        try wrtr.writeAll(spells.enable_kitty_keyboard);
    }
    if (config.request_mouse_tracking) {
        try wrtr.writeAll(spells.enable_mouse_tracking);
    }
    try bufwriter.flush();
}

/// Enter cooked mode.
pub fn cook(self: *Self) !void {
    debug.assert(self.tty != null);

    if (self.cooked) return;
    self.cooked = true;

    var bufwriter = self.bufferedWriter();
    const wrtr = bufwriter.writer();
    try wrtr.writeAll(
        // Even if we did not request the kitty keyboard protocol or mouse
        // tracking, asking the terminal to disable it should have no effect.
        spells.disable_kitty_keyboard ++
            spells.disable_mouse_tracking ++
            spells.clear ++
            spells.leave_alt_buffer ++
            spells.restore_screen ++
            spells.restore_cursor_position ++
            spells.show_cursor ++
            spells.reset_attributes ++
            spells.reset_attributes,
    );
    try bufwriter.flush();

    try std.posix.tcsetattr(self.tty.?, .FLUSH, self.cooked_termios);
}

pub fn fetchSize(self: *Self) !void {
    debug.assert(self.tty != null);

    if (self.cooked) return;
    var size = mem.zeroes(os.winsize);
    const err = os.ioctl(self.tty.?, os.T.IOCGWINSZ, @intFromPtr(&size));
    if (std.posix.errno(err) != .SUCCESS) {
        return std.posix.unexpectedErrno(@as(os.E, @enumFromInt(err)));
    }
    self.height = size.ws_row;
    self.width = size.ws_col;
}

/// Set window title using OSC 2. Shall not be called while rendering.
pub fn setWindowTitle(self: *Self, comptime fmt: []const u8, args: anytype) !void {
    debug.assert(self.tty != null);
    debug.assert(!self.currently_rendering);
    const wrtr = self.writer();
    try wrtr.print("\x1b]2;" ++ fmt ++ "\x1b\\", args);
}

pub fn getRenderContextSafe(self: *Self) !?RenderContext {
    debug.assert(self.tty != null);
    if (self.currently_rendering) return null;
    if (self.cooked) return null;

    self.currently_rendering = true;
    errdefer self.currently_rendering = false;

    var rc = RenderContext{
        .term = self,
        .buffer = self.bufferedWriter(),
    };

    const wrtr = rc.buffer.writer();
    try wrtr.writeAll(spells.start_sync);
    try wrtr.writeAll(spells.reset_attributes);

    return rc;
}

pub fn getRenderContext(self: *Self) !RenderContext {
    debug.assert(self.tty != null);
    debug.assert(!self.currently_rendering);
    debug.assert(!self.cooked);
    return (try self.getRenderContextSafe()) orelse unreachable;
}

pub const RenderContext = struct {
    term: *Self,
    buffer: BufferedWriter,

    const RestrictedPaddingWriter = rpw.RestrictedPaddingWriter(BufferedWriter.Writer);

    /// Finishes the render operation. The render context may not be used any
    /// further.
    pub fn done(rc: *RenderContext) !void {
        debug.assert(rc.term.currently_rendering);
        debug.assert(!rc.term.cooked);
        defer rc.term.currently_rendering = false;
        const wrtr = rc.buffer.writer();
        try wrtr.writeAll(spells.end_sync);
        try rc.buffer.flush();
    }

    /// Clears all content.
    pub fn clear(rc: *RenderContext) !void {
        debug.assert(rc.term.currently_rendering);
        const wrtr = rc.buffer.writer();
        try wrtr.writeAll(spells.clear);
    }

    /// Move the cursor to the specified cell.
    pub fn moveCursorTo(rc: *RenderContext, row: usize, col: usize) !void {
        debug.assert(rc.term.currently_rendering);
        const wrtr = rc.buffer.writer();
        try wrtr.print(spells.move_cursor_fmt, .{ row + 1, col + 1 });
    }

    /// Hide the cursor.
    pub fn hideCursor(rc: *RenderContext) !void {
        debug.assert(rc.term.currently_rendering);
        const wrtr = rc.buffer.writer();
        try wrtr.writeAll(spells.hide_cursor);
    }

    /// Show the cursor.
    pub fn showCursor(rc: *RenderContext) !void {
        debug.assert(rc.term.currently_rendering);
        const wrtr = rc.buffer.writer();
        try wrtr.writeAll(spells.show_cursor);
    }

    /// Set the text attributes for all following writes.
    pub fn setAttribute(rc: *RenderContext, attr: Attribute) !void {
        debug.assert(rc.term.currently_rendering);
        const wrtr = rc.buffer.writer();
        try attr.dump(wrtr);
    }

    pub fn restrictedPaddingWriter(rc: *RenderContext, len: usize) RestrictedPaddingWriter {
        debug.assert(rc.term.currently_rendering);
        return rpw.restrictedPaddingWriter(rc.buffer.writer(), len);
    }

    /// Write all bytes, wrapping at the end of the line.
    pub fn writeAllWrapping(rc: *RenderContext, bytes: []const u8) !void {
        debug.assert(rc.term.currently_rendering);
        const wrtr = rc.buffer.writer();
        try wrtr.writeAll(spells.enable_auto_wrap);
        try wrtr.writeAll(bytes);
        try wrtr.writeAll(spells.reset_auto_wrap);
    }
};
