const std = @import("std");
const Client = @import("../Client.zig");

pub const description = "Remove the stored credentials from the config file";
pub const usage =
    \\Usage: zpotify logout
    \\
    \\Description: Remove the stored credentials from the config file
    \\
;

pub fn exec(allocator: std.mem.Allocator) !void {
    const save_path = try Client.getSavePath(allocator);
    defer allocator.free(save_path);
    std.fs.deleteFileAbsolute(save_path) catch |err| {
        if (err != error.FileNotFound) {
            return err;
        }
    };
    std.log.info("You have been logged out.", .{});
}
