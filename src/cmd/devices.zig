const std = @import("std");
const api = @import("zpotify");
const Context = @import("../Context.zig");

pub const description = "List all available devices";
pub const usage =
    \\Usage: zpotify devices
    \\
    \\Description: List all available devices
    \\
;

pub fn exec(ctx: *Context) !void {
    const devices = try api.player.getDevices(ctx.client);

    if (devices.len == 0) {
        std.log.err("No device found", .{});
        std.process.exit(1);
    }

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(ctx.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    if (ctx.args.next()) |arg| {
        // used on auto-completion for `transfer`
        if (std.mem.eql(u8, arg, "_name")) {
            for (devices) |device| {
                try stdout.print("'{s}' ", .{device.name});
            }
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
}
