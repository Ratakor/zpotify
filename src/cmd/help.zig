const std = @import("std");
const main = @import("../main.zig");
const cmd = @import("../cmd.zig");

const usage =
    \\Usage: zpotify help [command]
    \\
    \\Description: Display information about a command
    \\
;

pub fn exec(command: ?[]const u8) !void {
    var stderr_writer = std.fs.File.stderr().writer(&.{});
    const stderr = &stderr_writer.interface;
    if (command) |com| {
        if (std.mem.eql(u8, com, "print")) {
            try stderr.writeAll(cmd.print.usage);
        } else if (std.mem.eql(u8, com, "search")) {
            try stderr.writeAll(cmd.search.usage);
        } else if (std.mem.eql(u8, com, "play")) {
            try stderr.writeAll(cmd.play.usage);
        } else if (std.mem.eql(u8, com, "pause")) {
            try stderr.writeAll(cmd.pause.usage);
        } else if (std.mem.eql(u8, com, "prev")) {
            try stderr.writeAll(cmd.prev.usage);
        } else if (std.mem.eql(u8, com, "next")) {
            try stderr.writeAll(cmd.next.usage);
        } else if (std.mem.eql(u8, com, "repeat")) {
            try stderr.writeAll(cmd.repeat.usage);
        } else if (std.mem.eql(u8, com, "shuffle")) {
            try stderr.writeAll(cmd.shuffle.usage);
        } else if (std.mem.eql(u8, com, "seek")) {
            try stderr.writeAll(cmd.seek.usage);
        } else if (std.mem.eql(u8, com, "vol") or std.mem.eql(u8, com, "volume")) {
            try stderr.writeAll(cmd.volume.usage);
        } else if (std.mem.eql(u8, com, "like")) {
            try stderr.writeAll(cmd.like.usage);
        } else if (std.mem.eql(u8, com, "queue")) {
            try stderr.writeAll(cmd.queue.usage);
        } else if (std.mem.eql(u8, com, "devices")) {
            try stderr.writeAll(cmd.devices.usage);
        } else if (std.mem.eql(u8, com, "transfer")) {
            try stderr.writeAll(cmd.transfer.usage);
        } else if (std.mem.eql(u8, com, "waybar")) {
            try stderr.writeAll(cmd.waybar.usage);
        } else if (std.mem.eql(u8, com, "logout")) {
            try stderr.writeAll(cmd.logout.usage);
        } else if (std.mem.eql(u8, com, "help")) {
            try stderr.writeAll(cmd.help.usage);
        } else if (std.mem.eql(u8, com, "version")) {
            try stderr.writeAll(cmd.version.usage);
        } else {
            std.log.warn("Unknown command: '{s}'", .{com});
            try stderr.writeAll(main.usage);
        }
    } else {
        try stderr.writeAll(main.usage);
    }
}
