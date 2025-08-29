const std = @import("std");
const build_options = @import("build_options");

pub const usage =
    \\Usage: zpotify version
    \\
    \\Description: Display program version
    \\
;

pub fn exec() !void {
    try std.fs.File.stdout().writeAll(build_options.version_string ++ "\n");
}
