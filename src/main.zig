const std = @import("std");
const builtin = @import("builtin");
const Client = @import("Client.zig");
const cmd = @import("cmd.zig");

pub const std_options: std.Options = .{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = coloredLog,
};

pub const version = "0.1.0";
pub var progname: []const u8 = undefined;

pub const usage =
    \\Usage: {s} [command] [options]
    \\
    \\Commands:
    \\  print      | Display current track info in a specific format
    \\  play       | Play a track, playlist, album, or artist
    \\  pause      | Toggle pause state
    \\  prev       | Skip to previous track
    \\  next       | Skip to next track
    \\  repeat     | Get/Set repeat mode
    \\  shuffle    | Toggle shuffle mode or force it to a specific state
    \\  seek       | Get/Set the position of the current track
    \\  vol        | Get/Set volume or increase/decrease volume by 10%
    \\  like       | Add the current track to your liked songs
    \\  waybar     | Display infos about the current playback for a waybar module
    \\  logout     | Remove the stored credentials from the config file
    \\  help       | Display information about a command
    \\  version    | Display program version
    \\
;

const Color = enum(u8) {
    black = 30,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    default,
    bright_black = 90,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,

    const csi = "\x1b[";
    const reset = csi ++ "0m";
    const bold = csi ++ "1m";

    fn toSeq(comptime fg: Color) []const u8 {
        return comptime csi ++ std.fmt.digits2(@intFromEnum(fg)) ++ "m";
    }
};

fn coloredLog(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime switch (message_level) {
        .err => Color.bold ++ Color.red.toSeq() ++ "error" ++ Color.reset,
        .warn => Color.bold ++ Color.yellow.toSeq() ++ "warning" ++ Color.reset,
        .info => Color.bold ++ Color.blue.toSeq() ++ "info" ++ Color.reset,
        .debug => Color.bold ++ Color.cyan.toSeq() ++ "debug" ++ Color.reset,
    };
    const scope_prefix = (if (scope != .default) "@" ++ @tagName(scope) else "") ++ ": ";
    var bw = std.io.bufferedWriter(comptime switch (message_level) {
        .err, .warn, .debug => std.io.getStdErr().writer(),
        .info => std.io.getStdOut().writer(),
    });
    const writer = bw.writer();
    writer.print(level_txt ++ scope_prefix ++ format ++ "\n", args) catch return;
    bw.flush() catch return;
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var args = std.process.args();
    progname = args.next().?;
    const command = args.next() orelse {
        cmd.help.exec(null);
        std.process.exit(1);
    };

    if (std.mem.eql(u8, command, "logout")) {
        return cmd.logout.exec(allocator);
    } else if (std.mem.eql(u8, command, "help")) {
        return cmd.help.exec(args.next());
    } else if (std.mem.eql(u8, command, "version")) {
        return cmd.version.exec();
    }

    var client = try Client.init(allocator);
    defer client.deinit();

    if (std.mem.eql(u8, command, "print")) {
        return cmd.print.exec(&client, &args);
    } else if (std.mem.eql(u8, command, "play")) {
        return cmd.play.exec(&client, &args);
    } else if (std.mem.eql(u8, command, "pause")) {
        return cmd.pause.exec(&client);
    } else if (std.mem.eql(u8, command, "prev")) {
        return cmd.prev.exec(&client);
    } else if (std.mem.eql(u8, command, "next")) {
        return cmd.next.exec(&client);
    } else if (std.mem.eql(u8, command, "repeat")) {
        return cmd.repeat.exec(&client, args.next());
    } else if (std.mem.eql(u8, command, "shuffle")) {
        return cmd.shuffle.exec(&client, args.next());
    } else if (std.mem.eql(u8, command, "seek")) {
        return cmd.seek.exec(&client, args.next());
    } else if (std.mem.eql(u8, command, "vol")) {
        return cmd.vol.exec(&client, args.next());
    } else if (std.mem.eql(u8, command, "like")) {
        return cmd.like.exec(&client);
    } else if (std.mem.eql(u8, command, "waybar")) {
        return cmd.waybar.exec(&client, allocator);
    } else {
        std.log.err("Unknown command: '{s}'", .{command});
        cmd.help.exec(null);
        std.process.exit(1);
    }
}
