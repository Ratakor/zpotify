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
const ascii = std.ascii;
const fs = std.fs;
const Io = std.Io;
const mem = std.mem;
const os = std.os;
const unicode = std.unicode;
const debug = std.debug;

const CodepointStagingArea = struct {
    const Self = @This();

    len: usize,
    left: usize,
    buf: [4]u8 = undefined,

    pub fn new(first_byte: u8, len: usize) Self {
        var ret = Self{
            .len = len,
            .left = len - 1,
        };
        ret.buf[0] = first_byte;
        return ret;
    }

    /// Add a byte to the staging area. Returns true if the codepoint has been
    /// completed by that byte, otherwise false.
    pub fn addByte(self: *Self, b: u8) bool {
        debug.assert(self.left > 0);
        self.buf[self.len - self.left] = b;
        self.left -= 1;
        return self.left == 0;
    }

    pub fn bytes(self: *Self) []const u8 {
        return self.buf[0..self.len];
    }
};

/// A writer that writes at most N terminal cells. If the caller tries to write
/// more, "…" is written and the remaining bytes will be silently discarded.
/// Can optionally pad the remaining size with whitespace or return it.
/// Needs to be finished with either pad(), getRemaining() or finish() to
/// function correctly.
///
/// TODO graphemes, emoji, double wide characters and similar pain :(
pub const RestrictedPaddingWriter = struct {
    // this is probably not how we're supposed to deal with the new interface :P
    underlying_writer: *Io.Writer,
    interface: Io.Writer,

    // This counts terminal cells, not bytes or codepoints!
    // TODO ok, right now it does count codepoints, see previous TODO comment...
    len_left: usize,

    codepoint_staging_area: ?CodepointStagingArea = null,
    codepoint_holding_area: ?CodepointStagingArea = null,

    pub fn init(underlying_writer: *Io.Writer, len: usize) RestrictedPaddingWriter {
        return .{
            .underlying_writer = underlying_writer,
            .interface = .{
                .buffer = &.{},
                .vtable = &.{ .drain = drain },
            },
            .len_left = len,
        };
    }

    pub fn finish(self: *RestrictedPaddingWriter) Io.Writer.Error!void {
        // TODO what should happen if the codepoint in the holding area is
        //      incomplete or bad?
        if (self.codepoint_holding_area) |_| {
            try self.underlying_writer.writeAll(self.codepoint_holding_area.?.bytes());
            self.codepoint_holding_area = null;
            self.len_left -= 1;
        }
    }

    pub fn pad(self: *RestrictedPaddingWriter) Io.Writer.Error!void {
        try self.finish();
        try self.underlying_writer.splatByteAll(' ', self.len_left);
        self.len_left = 0;
    }

    pub fn getRemaining(self: *RestrictedPaddingWriter) Io.Writer.Error!usize {
        try self.finish();
        return self.len_left;
    }

    fn drain(w: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
        _ = splat;
        const self: *RestrictedPaddingWriter = @alignCast(@fieldParentPtr("interface", w));
        return self.write(data[0]);
    }

    pub fn write(self: *RestrictedPaddingWriter, bytes: []const u8) Io.Writer.Error!usize {
        if (self.codepoint_holding_area) |_| {
            // The holding area is only for the last codepoint on our line,
            // which we hold because we only know whether to write it based
            // on whether any codepoints come after it. As such, it is only
            // active when we only have a single character left on the line.
            debug.assert(self.len_left == 1);

            // Since this function has been called, there come bytes after
            // the codepoint we currently hold. As such, it will not get
            // written, instead we write '…' and return.
            self.codepoint_holding_area = null;
            self.len_left = 0;
            try self.underlying_writer.writeAll("…");
            return bytes.len;
        }

        for (bytes, 0..) |c, i| {
            if (self.len_left == 0) break;

            // If we are building up a codepoint right now, just add the
            // byte, try to write and finally continue.
            if (self.codepoint_staging_area) |_| {
                if (self.codepoint_staging_area.?.addByte(c)) {
                    try self.maybeWriteCodepointStagingArea(bytes.len - i - 1);
                }
                continue;
            }

            // We do not want invalid unicode to end up in our output.
            const utf8len = unicode.utf8ByteSequenceLength(c) catch {
                try self.writeError(bytes.len - i - 1);
                continue;
            };

            // If the codepoint is only one byte long, we can try to print
            // it immediately. Otherwise we need to hold on to the byte and
            // build up the full codepoint over time.
            if (utf8len == 1) {
                try self.maybeWriteByte(c, bytes.len - i - 1);
            } else {
                self.codepoint_staging_area = CodepointStagingArea.new(c, utf8len);
            }
        }

        return bytes.len;
    }

    fn writeError(self: *RestrictedPaddingWriter, remaining_bytes_len: usize) Io.Writer.Error!void {
        debug.assert(self.len_left > 0);
        const err_symbol = "�";
        debug.assert(err_symbol.len == 3);
        if (self.len_left > 1) {
            try self.underlying_writer.writeAll(err_symbol);
            self.len_left -= 1;
        } else if (remaining_bytes_len > 0) {
            try self.underlying_writer.writeAll("…");
            self.len_left -= 1;
        } else {
            self.codepoint_staging_area = null;
            self.codepoint_holding_area = CodepointStagingArea.new(err_symbol[0], err_symbol.len);
            _ = self.codepoint_holding_area.?.addByte(err_symbol[1]);
            _ = self.codepoint_holding_area.?.addByte(err_symbol[2]);
        }
    }

    fn maybeWriteCodepointStagingArea(self: *RestrictedPaddingWriter, remaining_bytes_len: usize) Io.Writer.Error!void {
        debug.assert(self.len_left > 0);
        if (self.len_left > 1) {
            try self.underlying_writer.writeAll(self.codepoint_staging_area.?.bytes());
            self.codepoint_staging_area = null;
            self.len_left -= 1;
        } else if (remaining_bytes_len > 0) {
            try self.underlying_writer.writeAll("…");
            self.codepoint_staging_area = null;
            self.len_left -= 1;
        } else {
            self.codepoint_holding_area = self.codepoint_staging_area;
            self.codepoint_staging_area = null;
        }
    }

    fn maybeWriteByte(self: *RestrictedPaddingWriter, b: u8, remaining_bytes_len: usize) Io.Writer.Error!void {
        debug.assert(self.len_left > 0);

        // We do not want to end up with control characters in our output,
        // as they potentially can mess up what we try to write to the
        // terminal.
        if (ascii.isControl(b)) {
            try self.writeError(remaining_bytes_len);
            return;
        }

        const byte = if (b == '\n' or b == '\t' or b == '\r' or b == ' ') ' ' else b;
        if (self.len_left > 1) {
            try self.underlying_writer.writeByte(byte);
            self.len_left -= 1;
        } else if (remaining_bytes_len > 0) {
            try self.underlying_writer.writeAll("…");
            self.len_left -= 1;
        } else {
            self.codepoint_holding_area = CodepointStagingArea.new(byte, 1);
        }
    }
};

test "RestrictedPaddingWriter" {
    // Just some superficial test to make sure everything smells right. We are
    // not testing the actual contents, what is actually written, because it
    // should be fairly obvious to see when looking at the example programs.
    const testing = std.testing;
    {
        const bytes = "12345678";
        var counting_writer: Io.Writer.Discarding = .init(&.{});
        var rpw: RestrictedPaddingWriter = .init(&counting_writer.writer, bytes.len);
        try rpw.interface.writeAll(bytes);
        try rpw.finish();
        try testing.expect(counting_writer.fullCount() == bytes.len);
    }
    {
        const bytes = "12345678";
        var counting_writer: Io.Writer.Discarding = .init(&.{});
        var rpw: RestrictedPaddingWriter = .init(&counting_writer.writer, bytes.len - 1);
        try rpw.interface.writeAll(bytes);
        try rpw.finish();
        try testing.expect(counting_writer.fullCount() == bytes.len - 2 + "…".len);
    }
    {
        const bytes = "12345678";
        var counting_writer: Io.Writer.Discarding = .init(&.{});
        var rpw: RestrictedPaddingWriter = .init(&counting_writer.writer, 20);
        try rpw.interface.writeAll(bytes);
        try rpw.pad();
        try testing.expect(counting_writer.fullCount() == 20);
    }
}
