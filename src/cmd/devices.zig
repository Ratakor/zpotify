const std = @import("std");
const api = @import("zpotify").api;

pub const description = "List all available devices";
pub const usage =
    \\Usage: zpotify devices
    \\
    \\Description: List all available devices
    \\
;

pub fn exec(client: *api.Client, arg: ?[]const u8) !void {
    const devices = try api.player.getDevices(client);

    if (devices.len == 0) {
        std.log.err("No device found", .{});
        std.process.exit(1);
    }

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    if (arg) |a| {
        // used on auto-completion for `transfer`
        if (std.mem.eql(u8, a, "_name")) {
            for (devices) |device| {
                try stdout.print("'{s}' ", .{device.name});
            }
            try stdout.flush();
            return;
        }
    }

    for (devices, 0..) |device, i| {
        if (i != 0) {
            try stdout.writeAll("\n");
        }
        try stdout.print("Name: {s}\n", .{device.name});
        try stdout.print("Type: {s}\n", .{device.type});
        try stdout.print("ID: {?s}\n", .{device.id});
        if (device.volume_percent) |volume| {
            try stdout.print("Volume: {d}%\n", .{volume});
        }
        try stdout.print("Active: {}\n", .{device.is_active});
    }
    try stdout.flush();
}
