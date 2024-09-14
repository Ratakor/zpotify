const std = @import("std");
const api = @import("../api.zig");

pub const usage =
    \\Usage: {s} devices
    \\
    \\Description: List all available devices
    \\
;

pub fn exec(client: *api.Client) !void {
    const devices = try api.getDevices(client);

    if (devices.len == 0) {
        std.log.err("No device found", .{});
        std.process.exit(1);
    }

    const stdout = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout);
    const writer = bw.writer();

    for (devices, 0..) |device, i| {
        if (i != 0) {
            try writer.writeAll("\n");
        }
        try writer.print("Name: {s}\n", .{device.name});
        try writer.print("Type: {s}\n", .{device.type});
        try writer.print("ID: {?s}\n", .{device.id});
        if (device.volume_percent) |volume| {
            try writer.print("Volume: {d}%\n", .{volume});
        }
        try writer.print("Active: {}\n", .{device.is_active});
    }
    try bw.flush();
}
