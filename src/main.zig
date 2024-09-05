const std = @import("std");
const builtin = @import("builtin");

pub const std_options: std.Options = .{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = coloredLog,
};

const version = "0.0.0";

const protocol = "https";
const token_url = protocol ++ "://accounts.spotify.com/api/token";
const api_url = protocol ++ "://api.spotify.com/v1";

/// https://developer.spotify.com/documentation/web-api/reference/get-the-users-currently-playing-track
const NowPlayingResponse = struct {
    device: ?struct {
        id: ?[]const u8 = null,
        is_active: ?bool = null,
        is_private_session: ?bool = null,
        is_restricted: ?bool = null,
        name: ?[]const u8 = null,
        type: ?[]const u8 = null,
        volume_percent: ?u64 = null,
        supports_volume: ?bool = null,
    } = null,
    repeat_state: ?[]const u8 = null,
    shuffle_state: ?bool = null,
    context: ?struct {
        type: ?[]const u8 = null,
        href: ?[]const u8 = null,
        external_urls: ?struct {
            spotify: ?[]const u8 = null,
        } = null,
        uri: ?[]const u8 = null,
    } = null,
    timestamp: ?u64 = null,
    progress_ms: ?u64 = null,
    is_playing: ?bool = null,
    // TODO: Implement for EpisodeObject
    item: ?struct {
        album: ?struct {
            album_type: []const u8,
            total_tracks: u64,
            available_markets: []const []const u8,
            external_urls: struct {
                spotify: ?[]const u8 = null,
            },
            href: []const u8,
            id: []const u8,
            images: []const struct {
                url: []const u8,
                height: ?u64 = null,
                width: ?u64 = null,
            },
            name: []const u8,
            release_date: []const u8,
            release_date_precision: []const u8,
            restrictions: ?struct {
                reason: ?[]const u8 = null,
            } = null,
            type: []const u8,
            uri: []const u8,
            artists: []const struct {
                external_urls: ?struct {
                    spotify: ?[]const u8 = null,
                } = null,
                href: ?[]const u8 = null,
                id: ?[]const u8 = null,
                name: ?[]const u8 = null,
                type: ?[]const u8 = null,
                uri: ?[]const u8 = null,
            },
        } = null,
        artists: ?[]const struct {
            external_urls: ?struct {
                spotify: ?[]const u8 = null,
            } = null,
            href: ?[]const u8 = null,
            id: ?[]const u8 = null,
            name: ?[]const u8 = null,
            type: ?[]const u8 = null,
            uri: ?[]const u8 = null,
        } = null,
        available_markets: ?[]const []const u8 = null,
        disc_number: ?u64 = null,
        duration_ms: ?u64 = null,
        explicit: ?bool = null,
        external_ids: ?struct {
            isrc: ?[]const u8 = null,
            ean: ?[]const u8 = null,
            upc: ?[]const u8 = null,
        } = null,
        external_urls: ?struct {
            spotify: ?[]const u8 = null,
        } = null,
        href: ?[]const u8 = null,
        id: ?[]const u8 = null,
        is_playable: ?bool = null,
        linked_from: ?struct {} = null,
        restrictions: ?struct {
            reason: ?[]const u8 = null,
        } = null,
        name: ?[]const u8 = null,
        popularity: ?u64 = null,
        preview_url: ?[]const u8,
        track_number: ?u64 = null,
        type: ?[]const u8 = null,
        uri: ?[]const u8 = null,
        is_local: ?bool = null,
    } = null,
    currently_playing_type: ?[]const u8 = null,
    actions: ?struct {
        interrupting_playback: ?bool = null,
        pausing: ?bool = null,
        resuming: ?bool = null,
        seeking: ?bool = null,
        skipping_next: ?bool = null,
        skipping_prev: ?bool = null,
        toggling_repeat_context: ?bool = null,
        toggling_shuffle: ?bool = null,
        toggling_repeat_track: ?bool = null,
        transferring_playback: ?bool = null,
    } = null,
};

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

const Config = struct {
    authorization: []const u8,
    refresh_token: []const u8,
    allocator: std.mem.Allocator,

    const Json = struct {
        authorization: []const u8,
        refresh_token: []const u8,
    };

    // TODO: help people that don't have client_id, client_secret, and refresh_token
    // TODO: make sure the info are correct
    // TODO: encrypt the config file
    fn init(allocator: std.mem.Allocator) !Config {
        const config_path = try Config.getPath(allocator);
        defer allocator.free(config_path);
        const cwd = std.fs.cwd();
        const config_file = if (cwd.openFile(config_path, .{})) |config_file| blk: {
            const content = try config_file.readToEndAlloc(allocator, 4096);
            defer allocator.free(content);
            if (std.json.parseFromSlice(Config.Json, allocator, content, .{})) |config_json| {
                defer config_json.deinit();
                return .{
                    .authorization = try allocator.dupe(u8, config_json.value.authorization),
                    .refresh_token = try allocator.dupe(u8, config_json.value.refresh_token),
                    .allocator = allocator,
                };
            } else |err| {
                std.log.warn("Failed to parse the configuration file: {}", .{err});
                break :blk try cwd.createFile(config_path, .{});
            }
        } else |err| blk: {
            if (err != error.FileNotFound) {
                return err;
            }
            try cwd.makePath(config_path[0 .. config_path.len - "config.json".len]);
            break :blk try cwd.createFile(config_path, .{});
        };

        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll("Please enter the following information to authenticate with Spotify.");
        try stdout.writeAll("\nClient ID: ");
        const client_id = try readDataFromUser(allocator, 64, false);
        defer allocator.free(client_id);
        try stdout.writeAll("Client Secret: ");
        const client_secret = try readDataFromUser(allocator, 64, true);
        defer allocator.free(client_secret);
        try stdout.writeAll("Refresh Token: ");
        const refresh_token = try readDataFromUser(allocator, 256, true);
        errdefer allocator.free(refresh_token);

        const authorization = blk: {
            const source = try std.fmt.allocPrint(allocator, "{s}:{s}", .{
                client_id,
                client_secret,
            });
            defer allocator.free(source);
            var base64_encoder = std.base64.standard.Encoder;
            const size = base64_encoder.calcSize(source.len);
            const buffer = try allocator.alloc(u8, size);
            break :blk base64_encoder.encode(buffer, source);
        };
        errdefer allocator.free(authorization);

        const config_json: Config.Json = .{
            .authorization = authorization,
            .refresh_token = refresh_token,
        };

        try config_file.seekTo(0);
        var ws = std.json.writeStream(config_file.writer(), .{});
        defer ws.deinit();
        try ws.write(config_json);

        std.log.info("Your information has been saved to '{s}'.", .{config_path});

        return .{
            .authorization = authorization,
            .refresh_token = refresh_token,
            .allocator = allocator,
        };
    }

    fn deinit(self: Config) void {
        self.allocator.free(self.authorization);
        self.allocator.free(self.refresh_token);
    }

    // TODO: windows
    fn getPath(allocator: std.mem.Allocator) ![]const u8 {
        if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg_config| {
            return std.fmt.allocPrint(allocator, "{s}/zpotify/config.json", .{xdg_config});
        } else if (std.posix.getenv("HOME")) |home| {
            return std.fmt.allocPrint(allocator, "{s}/.config/zpotify/config.json", .{home});
        } else {
            return error.EnvironmentVariableNotFound;
        }
    }
};

fn readDataFromUser(allocator: std.mem.Allocator, max_size: usize, hide: bool) ![]const u8 {
    const handle = std.os.linux.STDIN_FILENO;
    var original: std.os.linux.termios = undefined;
    var hidden: std.os.linux.termios = undefined;
    if (hide) {
        _ = std.os.linux.tcgetattr(handle, &original);
        hidden = original;
        hidden.lflag.ICANON = false;
        hidden.lflag.ECHO = false;
        _ = std.os.linux.tcsetattr(handle, .NOW, &hidden);
    }
    defer if (hide) {
        _ = std.os.linux.tcsetattr(handle, .NOW, &original);
    };

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    var array_list = std.ArrayList(u8).init(allocator);
    defer array_list.deinit();
    var size: usize = 0;
    while (true) {
        if (size == max_size) {
            return error.StreamTooLong;
        }
        const byte = try stdin.readByte();
        switch (byte) {
            '\n' => break,
            '\x7f' => {
                if (hide and size > 0) {
                    size -= 1;
                    try stdout.writeAll("\x08 \x08");
                }
                continue;
            },
            else => {},
        }
        size += 1;
        try array_list.append(byte);
        if (hide) {
            try stdout.writeAll("*");
        }
    }
    if (hide) {
        try stdout.writeAll("\n");
    }

    return array_list.toOwnedSlice();
}

/// Returns the access token, allocated with client.allocator.
fn getAccessToken(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    config: Config,
) ![]const u8 {
    const uri = try std.Uri.parse(token_url);
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
        std.log.err("{?s} ({s})", .{
            json.value.error_description,
            json.value.@"error".?,
        });
        return error.BadResponse;
    }
}

fn getNowPlaying(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    access_token: []const u8,
) !std.json.Parsed(NowPlayingResponse) {
    const url = try std.fmt.allocPrint(allocator, "{s}/me/player/currently-playing", .{api_url});
    defer allocator.free(url);
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
    try req.finish();
    try req.wait();

    std.log.debug("getNowPlaying(): Response status: {s} ({d})", .{
        @tagName(req.response.status),
        @intFromEnum(req.response.status),
    });

    const response = try req.reader().readAllAlloc(allocator, 8192);
    defer allocator.free(response);

    // std.log.debug("Response: {s}", .{response});

    switch (req.response.status) {
        .ok => return std.json.parseFromSlice(NowPlayingResponse, allocator, response, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        }),
        .unauthorized, .forbidden, .too_many_requests => {
            const Response = struct {
                @"error": struct {
                    status: u64,
                    message: []const u8,
                },
            };
            const json = try std.json.parseFromSlice(Response, allocator, response, .{});
            defer json.deinit();
            std.log.err("{s} ({d})", .{ json.value.@"error".message, json.value.@"error".status });
            return error.BadResponse;
        },
        else => return error.BadResponse,
    }

    return std.json.parseFromSlice(NowPlayingResponse, allocator, response, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
}

fn logout(allocator: std.mem.Allocator) void {
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

    const config = try Config.init(allocator);
    defer config.deinit();
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    const access_token = try getAccessToken(allocator, &client, config);
    defer allocator.free(access_token);

    const now_playing = try getNowPlaying(allocator, &client, access_token);
    defer now_playing.deinit();

    //     if (now_playing.value.item) |track| {
    //         const is_playing = now_playing.value.is_playing.?;
    //         const title = track.name.?;
    //         const artists = blk: {
    //             var list: std.ArrayListUnmanaged(u8) = .{};
    //             for (track.artists.?, 0..) |artist, i| {
    //                 if (i != 0) {
    //                     try list.appendSlice(allocator, ", ");
    //                 }
    //                 try list.appendSlice(allocator, artist.name.?);
    //             }
    //             break :blk try list.toOwnedSlice(allocator);
    //         };
    //         defer allocator.free(artists);
    //         const album = track.album.?.name;
    //         const album_image_url = track.album.?.images[0].url;
    //         const duration = track.duration_ms.?;
    //         const progress = now_playing.value.progress_ms.?;

    //         std.debug.print("Is playing: {}\n", .{is_playing});
    //         std.debug.print("Title: {s}\n", .{title});
    //         std.debug.print("Artists: {s}\n", .{artists});
    //         std.debug.print("Album: {s}\n", .{album});
    //         std.debug.print("Album image URL: {s}\n", .{album_image_url});
    //         std.debug.print("Duration: {d}\n", .{duration});
    //         std.debug.print("Progress: {d}\n", .{progress});
    //     }

    const is_playing = now_playing.value.is_playing.?;
    const artist = now_playing.value.item.?.artists.?[0].name.?;
    const title = now_playing.value.item.?.name.?;

    if (is_playing) {
        std.debug.print(" ${s} - ${s}", .{ artist, title });
    } else {
        std.debug.print(" ${s} - ${s}", .{ artist, title });
    }
}
