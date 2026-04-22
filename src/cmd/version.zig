const std = @import("std");
const build_options = @import("build_options");
const cmd = @import("../cmd.zig");

pub const description = "Display program version";
pub const usage =
    \\Usage: zpotify version
    \\
    \\Description: Display program version
    \\
;

pub fn exec(ctx: *cmd.Context) !void {
    var stdout_writer = std.Io.File.stdout().writer(ctx.io, &.{});
    const stdout = &stdout_writer.interface;
    try stdout.writeAll(build_options.version_string ++ "\n");
    try stdout.flush();
}
