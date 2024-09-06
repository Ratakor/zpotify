const std = @import("std");
const Config = @import("../Config.zig");

pub const usage =
    \\Usage: {s} logout
    \\
    \\Description: Remove the stored credentials from the config file
    \\
;

pub fn exec(allocator: std.mem.Allocator) !void {
    const config_path = try Config.getPath(allocator);
    defer allocator.free(config_path);
    std.fs.deleteFileAbsolute(config_path) catch |err| {
        if (err != error.FileNotFound) {
            return err;
        }
    };
    std.log.info("You have been logged out.", .{});
}
