const std = @import("std");
const main = @import("../main.zig");

pub const usage =
    \\Usage: zpotify version
    \\
    \\Description: Display program version
    \\
;

pub fn exec() !void {
    try std.fs.File.stdout().writeAll(main.version ++ "\n");
}
