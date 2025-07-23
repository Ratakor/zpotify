const std = @import("std");
const main = @import("../main.zig");
const cmd = @import("../cmd.zig");

const usage =
    \\Usage: {s} help [command]
    \\
    \\Description: Display information about a command
    \\
;

pub fn exec(command: ?[]const u8) void {
    const stderr = std.io.getStdErr().writer();
    if (command) |com| {
        if (std.mem.eql(u8, com, "print")) {
            stderr.print(cmd.print.usage, .{main.progname}) catch unreachable;
        } else if (std.mem.eql(u8, com, "search")) {
            stderr.print(cmd.search.usage, .{main.progname}) catch unreachable;
        } else if (std.mem.eql(u8, com, "play")) {
            stderr.print(cmd.play.usage, .{main.progname}) catch unreachable;
        } else if (std.mem.eql(u8, com, "pause")) {
            stderr.print(cmd.pause.usage, .{main.progname}) catch unreachable;
        } else if (std.mem.eql(u8, com, "prev")) {
            stderr.print(cmd.prev.usage, .{main.progname}) catch unreachable;
        } else if (std.mem.eql(u8, com, "next")) {
            stderr.print(cmd.next.usage, .{main.progname}) catch unreachable;
        } else if (std.mem.eql(u8, com, "repeat")) {
            stderr.print(cmd.repeat.usage, .{main.progname}) catch unreachable;
        } else if (std.mem.eql(u8, com, "shuffle")) {
            stderr.print(cmd.shuffle.usage, .{main.progname}) catch unreachable;
        } else if (std.mem.eql(u8, com, "seek")) {
            stderr.print(cmd.seek.usage, .{main.progname}) catch unreachable;
        } else if (std.mem.eql(u8, com, "vol") or std.mem.eql(u8, com, "volume")) {
            stderr.print(cmd.vol.usage, .{main.progname}) catch unreachable;
        } else if (std.mem.eql(u8, com, "like")) {
            stderr.print(cmd.like.usage, .{main.progname}) catch unreachable;
        } else if (std.mem.eql(u8, com, "devices")) {
            stderr.print(cmd.devices.usage, .{main.progname}) catch unreachable;
        } else if (std.mem.eql(u8, com, "transfer")) {
            stderr.print(cmd.transfer.usage, .{main.progname}) catch unreachable;
        } else if (std.mem.eql(u8, com, "waybar")) {
            stderr.print(cmd.waybar.usage, .{main.progname}) catch unreachable;
        } else if (std.mem.eql(u8, com, "logout")) {
            stderr.print(cmd.logout.usage, .{main.progname}) catch unreachable;
        } else if (std.mem.eql(u8, com, "help")) {
            stderr.print(cmd.help.usage, .{main.progname}) catch unreachable;
        } else if (std.mem.eql(u8, com, "version")) {
            stderr.print(cmd.version.usage, .{main.progname}) catch unreachable;
        } else {
            std.log.warn("Unknown command: '{s}'", .{com});
            stderr.print(main.usage, .{main.progname}) catch unreachable;
        }
    } else {
        stderr.print(main.usage, .{main.progname}) catch unreachable;
    }
}
