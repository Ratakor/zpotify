const std = @import("std");
const main = @import("../main.zig");

pub const usage =
    \\Usage: {s} version
    \\
    \\Description: Display program version
    \\
;

pub fn exec() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s} " ++ main.version ++ "\n", .{main.progname});
}
