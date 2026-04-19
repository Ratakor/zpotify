const std = @import("std");
const api = @import("zpotify");
const cmd = @import("../cmd.zig");
const help = cmd.help;

pub const description = "Transfer playback to another device";
pub const usage =
    \\Usage: zpotify transfer <device>
    \\
    \\Description: Transfer playback to another device
    \\             <device> can be the name or ID of an available device
    \\
;

pub fn exec(ctx: *cmd.Context) !void {
    if (ctx.args.next()) |dev| {
        const devices = try api.player.getDevices(ctx.client);
        for (devices) |device| {
            if (device.id) |id| {
                if (std.mem.eql(u8, device.name, dev) or std.mem.eql(u8, id, dev)) {
                    std.log.info("Transferring playback to {s}", .{device.name});
                    try api.player.transferPlayback(ctx.client, id);
                    return;
                }
            }
        }
        std.log.err("No device found for '{s}'", .{dev});
        std.process.exit(1);
    } else {
        std.log.err("Missing device name/ID", .{});
        try help.exec(ctx, "transfer");
        std.process.exit(1);
    }
}
