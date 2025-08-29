const std = @import("std");
const api = @import("../api.zig");
const help = @import("../cmd.zig").help;

pub const usage =
    \\Usage: zpotify transfer [device]
    \\
    \\Description: Transfer playback to another device
    \\             [device] can be the name or ID of an available device
    \\
;

pub fn exec(client: *api.Client, arg: ?[]const u8) !void {
    if (arg) |dev| {
        const devices = try api.getDevices(client);
        for (devices) |device| {
            if (device.id) |id| {
                if (std.mem.eql(u8, device.name, dev) or std.mem.eql(u8, id, dev)) {
                    std.log.info("Transferring playback to {s}", .{device.name});
                    try api.transferPlayback(client, id);
                    return;
                }
            }
        }
        std.log.err("No device found for '{s}'", .{dev});
        std.process.exit(1);
    } else {
        std.log.err("Missing device name/ID", .{});
        try help.exec("transfer");
        std.process.exit(1);
    }
}
