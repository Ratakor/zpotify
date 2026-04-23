const std = @import("std");
const Context = @import("../Context.zig");
const save = @import("../save.zig");

pub const description = "Remove the stored credentials from the config file";
pub const usage =
    \\Usage: zpotify logout
    \\
    \\Description: Remove the stored credentials from the config file
    \\
;

pub fn exec(ctx: *Context) !void {
    const save_path = try save.getPath(ctx.allocator, ctx.env_map);
    defer ctx.allocator.free(save_path);
    std.Io.Dir.deleteFileAbsolute(ctx.io, save_path) catch |err| {
        if (err != error.FileNotFound) {
            return err;
        }
    };
    std.log.info("You have been logged out.", .{});
}
