const std = @import("std");
const builtin = @import("builtin");
const Config = @import("Config.zig");
const resp = @import("response.zig");

pub const std_options: std.Options = .{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = coloredLog,
};

const version = "0.0.0";
const api_url = "https://api.spotify.com/v1";
var progname: []const u8 = undefined;

const usage =
    \\Usage: {s} [command] [option]
    \\
    \\Commands:
    \\  pause       | Toggle spotify pause state
    // \\  play        | Play top result for specified artist, album, playlist, track, or uri
    // \\  stop        | Stop playback
    \\  prev        | Skip to previous track
    \\  next        | Skip to next track
    \\  repeat      | Get/Set repeat mode
    \\  shuffle     | Toggle shuffle on/off
    \\  replay      | Replay current track from the beginning
    \\  like        | Add the current track to your liked songs
    \\  seek        | Skip to a specific time (seconds) of the current track
    \\  share       | Get URI and URL for current track
    \\  status      | Show information about the current track
    // \\  image       | Display the album art for the current track
    \\  vol         | Get/Set volume
    // \\  progress    | Display a progress bar for the current track
    \\  bar         | Display info about the current track for use in a status bar
    \\  logout      | Remove the stored credentials from the config file
    \\  help        | Display information about a command
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
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print(level_txt ++ scope_prefix ++ format ++ "\n", args) catch return;
        bw.flush() catch return;
    }
}

fn getAccessToken(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    config: Config,
) ![]const u8 {
    const uri = try std.Uri.parse("https://accounts.spotify.com/api/token");
    const authorization = try std.fmt.allocPrint(allocator, "Basic {s}", .{config.authorization});
    defer allocator.free(authorization);

    const body = try std.fmt.allocPrint(
        allocator,
        "grant_type=refresh_token&refresh_token={s}",
        .{config.refresh_token},
    );
    defer allocator.free(body);

    var header_buf: [4096]u8 = undefined;
    var req = try client.open(.POST, uri, .{
        .server_header_buffer = &header_buf,
        .headers = .{
            .authorization = .{ .override = authorization },
            .content_type = .{ .override = "application/x-www-form-urlencoded" },
        },
    });
    defer req.deinit();
    req.transfer_encoding = .{ .content_length = body.len };
    try req.send();
    try req.writeAll(body);
    try req.finish();
    try req.wait();

    std.log.debug("getAccessToken(): Response status: {s} ({d})", .{
        @tagName(req.response.status),
        @intFromEnum(req.response.status),
    });

    const response = try req.reader().readAllAlloc(allocator, 4096);
    defer allocator.free(response);

    const Response = struct {
        @"error": ?[]const u8 = null,
        error_description: ?[]const u8 = null,
        access_token: ?[]const u8 = null,
        token_type: ?[]const u8 = null,
        expires_in: ?u64 = null,
        scope: ?[]const u8 = null,
    };

    const json = try std.json.parseFromSlice(Response, allocator, response, .{});
    defer json.deinit();

    if (json.value.access_token) |token| {
        return allocator.dupe(u8, token);
    } else {
        std.log.err("{?s} ({?s})", .{
            json.value.error_description,
            json.value.@"error",
        });
        return error.BadResponse;
    }
}

fn get(
    comptime T: type,
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    access_token: []const u8,
) !std.json.Parsed(T) {
    const url = api_url ++ T.request;
    const uri = try std.Uri.parse(url);
    const authorization = try std.fmt.allocPrint(allocator, "Bearer {s}", .{access_token});
    defer allocator.free(authorization);

    var header_buf: [4096]u8 = undefined;
    var req = try client.open(.GET, uri, .{
        .server_header_buffer = &header_buf,
        .headers = .{ .authorization = .{ .override = authorization } },
    });
    defer req.deinit();
    try req.send();
    try req.wait();

    std.log.debug("get({s}): Response status: {s} ({d})", .{
        T.request,
        @tagName(req.response.status),
        @intFromEnum(req.response.status),
    });

    const response = try req.reader().readAllAlloc(allocator, 8192);
    defer allocator.free(response);

    // std.log.debug("get({s}): Response: {s}", .{ T.request, response });

    switch (req.response.status) {
        .ok => return std.json.parseFromSlice(T, allocator, response, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        }),
        .no_content => return error.NotPlaying,
        .unauthorized, .forbidden, .too_many_requests => {
            const json = try std.json.parseFromSlice(resp.GetError, allocator, response, .{});
            defer json.deinit();
            std.log.err("{s} ({d})", .{ json.value.@"error".message, json.value.@"error".status });
            return error.BadResponse;
        },
        else => return error.UnknownResponse,
    }
}

fn logout(allocator: std.mem.Allocator) !void {
    const config_path = try Config.getPath(allocator);
    defer allocator.free(config_path);
    std.fs.deleteFileAbsolute(config_path) catch |err| {
        if (err != error.FileNotFound) {
            return err;
        }
    };
    std.log.info("You have been logged out.", .{});
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
        return logout(allocator);
    }

    const config = try Config.init(allocator, &client);
    defer config.deinit();
    const access_token = try getAccessToken(allocator, &client, config);
    defer allocator.free(access_token);

    // const playback = try get(resp.PlaybackState, allocator, &client, access_token);
    // defer playback.deinit();

    // const now_playing = playback;
    // const now_playing = try get(resp.CurrentlyPlaying, allocator, &client, access_token);
    // defer now_playing.deinit();

    // try std.json.stringify(playback.value, .{
    //     .whitespace = .indent_4,
    //     .emit_null_optional_fields = false,
    // }, std.io.getStdOut().writer());
    // try std.io.getStdOut().writeAll("\n");

    // const artists = blk: {
    //     var list: std.ArrayListUnmanaged(u8) = .{};
    //     for (now_playing.value.item.?.artists.?, 0..) |artist, i| {
    //         if (i != 0) {
    //             try list.appendSlice(allocator, ", ");
    //         }
    //         try list.appendSlice(allocator, artist.name.?);
    //     }
    //     break :blk try list.toOwnedSlice(allocator);
    // };

    // const is_playing = now_playing.value.is_playing.?;
    // const artist = now_playing.value.item.?.artists.?[0].name.?;
    // const title = now_playing.value.item.?.name.?;
    // if (is_playing) {
    //     std.debug.print(" {s} - {s}", .{ artist, title });
    // } else {
    //     std.debug.print(" {s} - {s}", .{ artist, title });
    // }
}
