const std = @import("std");
const builtin = @import("builtin");
const Config = @import("Config.zig");
const cmd = @import("cmd.zig");

pub const std_options: std.Options = .{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = coloredLog,
};

pub const version = "0.0.0";
pub var progname: []const u8 = undefined;

pub const usage =
    \\Usage: {s} [command] [option]
    \\
    \\Commands:
    \\  print      | Display current track info in a specific format
    // TODO
    // \\  play       | Play top result for specified artist, album, playlist, track, or uri
    // \\  playlists  | Display a list of your playlists (e.g. for use with play and dmenu)
    \\  pause      | Toggle pause state
    \\  prev       | Skip to previous track
    \\  next       | Skip to next track
    \\  repeat     | Get/Set repeat mode
    \\  shuffle    | Toggle shuffle mode
    \\  seek       | Skip to a specific time (seconds) of the current track
    \\  vol        | Get/Set volume
    \\  like       | Add the current track to your liked songs
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

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print(level_txt ++ scope_prefix ++ format ++ "\n", args) catch return;
        bw.flush() catch return;
    }
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    progname = args.next().?;
    const command = args.next() orelse "help";

    if (std.mem.eql(u8, command, "logout")) {
        return cmd.logout.exec(allocator);
    } else if (std.mem.eql(u8, command, "help")) {
        return cmd.help.exec(args.next());
    } else if (std.mem.eql(u8, command, "version")) {
        return cmd.version.exec();
    }

    const config = try Config.init(allocator, &client);
    defer config.deinit();

    if (std.mem.eql(u8, command, "print")) {
        return cmd.print.exec(allocator, &args, &client, config.access_token);
    } else if (std.mem.eql(u8, command, "pause")) {
        return cmd.pause.exec(allocator, &client, config.access_token);
    } else if (std.mem.eql(u8, command, "prev")) {
        return cmd.prev.exec(allocator, &client, config.access_token);
    } else if (std.mem.eql(u8, command, "next")) {
        return cmd.next.exec(allocator, &client, config.access_token);
    } else if (std.mem.eql(u8, command, "repeat")) {
        return cmd.repeat.exec(allocator, args.next(), &client, config.access_token);
    } else if (std.mem.eql(u8, command, "shuffle")) {
        return cmd.shuffle.exec(allocator, &client, config.access_token);
    } else if (std.mem.eql(u8, command, "seek")) {
        return cmd.seek.exec(allocator, args.next(), &client, config.access_token);
    } else if (std.mem.eql(u8, command, "vol")) {
        return cmd.vol.exec(allocator, args.next(), &client, config.access_token);
    } else if (std.mem.eql(u8, command, "like")) {
        return cmd.like.exec(allocator, &client, config.access_token);
    } else {
        std.log.err("Unknown command: '{s}'", .{command});
        cmd.help.exec(null);
        std.process.exit(1);
    }
}
