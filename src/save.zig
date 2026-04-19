const std = @import("std");

pub const filename = "config.json";

// TODO: use known-folders lib for compatibility
pub fn getPath(allocator: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("XDG_DATA_HOME")) |xdg_data| {
        return std.fmt.allocPrint(allocator, "{s}/zpotify/" ++ filename, .{xdg_data});
    } else if (std.posix.getenv("HOME")) |home| {
        return std.fmt.allocPrint(allocator, "{s}/.local/share/zpotify/" ++ filename, .{home});
    } else {
        return error.EnvironmentVariableMissing;
    }
}
