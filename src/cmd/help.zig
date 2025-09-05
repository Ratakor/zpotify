const std = @import("std");
const main = @import("../main.zig");
const cmd = @import("../cmd.zig");

pub const description = "Display information about a command";
pub const usage =
    \\Usage: zpotify help [command]
    \\
    \\Description: Display information about a command
    \\
;

pub fn exec(command: ?[]const u8) !void {
    var stderr_writer = std.fs.File.stderr().writer(&.{});
    const stderr = &stderr_writer.interface;
    if (command) |com| {
        inline for (comptime std.meta.declarations(cmd)) |decl| {
            if (std.mem.eql(u8, com, decl.name)) {
                try stderr.writeAll(@field(cmd, decl.name).usage);
                return;
            }
        } else if (std.mem.eql(u8, com, "vol")) {
            // backward compatibility when volume used to be "vol"
            try stderr.writeAll(cmd.volume.usage);
        } else {
            std.log.warn("Unknown command: '{s}'", .{com});
            try stderr.writeAll(main.usage);
        }
    } else {
        try stderr.writeAll(main.usage);
    }
}
