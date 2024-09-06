const std = @import("std");
const api = @import("../api.zig");
const help = @import("../cmd.zig").help;

pub const usage =
    \\Usage: {s} repeat [track|context|off]
    \\
    \\Description: Get/Set repeat mode
    \\
;

pub fn exec(
    allocator: std.mem.Allocator,
    arg: ?[]const u8,
    client: *std.http.Client,
    access_token: []const u8,
) !void {
    if (arg) |state| {
        if (!std.mem.eql(u8, state, "track") and
            !std.mem.eql(u8, state, "context") and
            !std.mem.eql(u8, state, "off"))
        {
            std.log.err("Invalid repeat mode: {s}", .{state});
            help.exec("repeat");
            std.process.exit(1);
        }
        std.log.info("Setting repeat mode to {s}", .{state});
        try api.put(.repeat, allocator, client, access_token, .{state});
    } else {
        const playback_state = api.get(
            .playback_state,
            allocator,
            client,
            access_token,
        ) catch |err| switch (err) {
            error.NotPlaying => return,
            else => return err,
        };
        defer playback_state.deinit();
        std.log.info("Repeat mode is currently set to {s}", .{playback_state.value.repeat_state});
    }
}
