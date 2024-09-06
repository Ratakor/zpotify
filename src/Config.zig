const std = @import("std");

const Config = @This();

authorization: []const u8,
refresh_token: []const u8,
allocator: std.mem.Allocator,

const redirect_uri = "http://localhost:9999/callback";

/// https://developer.spotify.com/documentation/web-api/concepts/scopes
const scopes = [_][]const u8{
    "user-read-playback-state",
    "user-modify-playback-state",
    "user-read-currently-playing",
};

const Json = struct {
    authorization: []const u8,
    refresh_token: []const u8,
};

pub fn init(allocator: std.mem.Allocator, client: *std.http.Client) !Config {
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
    try stdout.writeAll("Welcome to zpotify!\n");
    try stdout.writeAll("This is probably your first time running zpotify, so we need to authenticate with Spotify.\n");
    try stdout.writeAll("Go to https://developer.spotify.com/dashboard\n");
    try stdout.writeAll("Create a new app, name and description doesn't matter but redirect URI must be" ++ redirect_uri ++ "\n");
    try stdout.writeAll("Enter the following informations\n");
    const client_id = try getClientData("ID", allocator);
    defer allocator.free(client_id);
    const client_secret = try getClientData("Secret", allocator);
    defer allocator.free(client_secret);

    const auth_code = try oauth2(allocator, client_id);
    defer allocator.free(auth_code);

    const authorization = blk: {
        const source = try std.fmt.allocPrint(allocator, "{s}:{s}", .{
            client_id,
            client_secret,
        });
        defer allocator.free(source);
        var base64 = std.base64.standard.Encoder;
        const size = base64.calcSize(source.len);
        const buffer = try allocator.alloc(u8, size);
        break :blk base64.encode(buffer, source);
    };
    errdefer allocator.free(authorization);

    // TODO: cache access token (from getRefreshToken()) in this struct
    const refresh_token = try getRefreshToken(allocator, client, auth_code, authorization);
    defer allocator.free(refresh_token);

    const config_json: Config.Json = .{
        .authorization = authorization,
        .refresh_token = refresh_token,
    };

    try config_file.seekTo(0);
    var ws = std.json.writeStream(config_file.writer(), .{});
    defer ws.deinit();
    try ws.write(config_json);

    std.log.info("Your information has been saved to '{s}'.", .{config_path});

    // TODO: crash if trying to get the access token with a too recent refresh token
    std.process.exit(0);

    return .{
        .authorization = authorization,
        .refresh_token = refresh_token,
        .allocator = allocator,
    };
}

pub fn deinit(self: Config) void {
    self.allocator.free(self.authorization);
    self.allocator.free(self.refresh_token);
}

// TODO: windows
pub fn getPath(allocator: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg_config| {
        return std.fmt.allocPrint(allocator, "{s}/zpotify/config.json", .{xdg_config});
    } else if (std.posix.getenv("HOME")) |home| {
        return std.fmt.allocPrint(allocator, "{s}/.config/zpotify/config.json", .{home});
    } else {
        return error.EnvironmentVariableNotFound;
    }
}

fn getClientData(name: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const max_retries = 5;
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    outer: for (0..max_retries) |_| {
        try stdout.print("Client {s}: ", .{name});
        const data = stdin.readUntilDelimiterAlloc(allocator, '\n', 64) catch |err| switch (err) {
            error.StreamTooLong => {
                std.log.warn("The client {s} must be 32 bytes long.", .{name});
                continue;
            },
            else => return err,
        };
        if (data.len != 32) {
            std.log.warn("The client {s} must be 32 bytes long.", .{name});
            allocator.free(data);
            continue;
        }
        for (data) |byte| {
            if (!std.ascii.isHex(byte)) {
                std.log.warn("The client {s} must be a hex string.", .{name});
                allocator.free(data);
                continue :outer;
            }
        }
        return data;
    }
    return error.TooManyRetries;
}

// TODO: windows
fn oauth2(allocator: std.mem.Allocator, client_id: []const u8) ![]const u8 {
    const scope = comptime blk: {
        const separator = "+";
        var buf: [4096]u8 = undefined;
        @memcpy(buf[0..scopes[0].len], scopes[0]);
        var size: usize = scopes[0].len;
        for (scopes[1..]) |scope| {
            @memcpy(buf[size .. size + separator.len], separator);
            size += separator.len;
            @memcpy(buf[size .. size + scope.len], scope);
            size += scope.len;
        }
        break :blk buf[0..size];
    };

    const escaped_redirect_uri = comptime blk: {
        var buffer: [4096]u8 = undefined;
        const size = std.mem.replacementSize(u8, redirect_uri, "/", "%2F");
        _ = std.mem.replace(u8, redirect_uri, "/", "%2F", &buffer);
        break :blk buffer[0..size];
    };

    // TODO: returns INVALID_CLIENT: Invalid client
    // const state = blk: {
    //     var source: [16]u8 = undefined;
    //     var prng = std.Random.DefaultPrng.init(@bitCast(std.time.microTimestamp()));
    //     prng.fill(&source);
    //     var base64 = std.base64.url_safe_no_pad.Encoder;
    //     const size = base64.calcSize(source.len);
    //     const buffer = try allocator.alloc(u8, size);
    //     break :blk base64.encode(buffer, &source);
    // };
    // defer allocator.free(state);

    const url = try std.fmt.allocPrint(
        allocator,
        "https://accounts.spotify.com/authorize?client_id={s}&" ++ //state={s}&" ++
            "response_type=code&redirect_uri=" ++ escaped_redirect_uri ++ "&scope=" ++ scope,
        .{client_id},
    );
    defer allocator.free(url);

    const localhost = try std.net.Address.parseIp4("127.0.0.1", 9999);
    var server = try localhost.listen(.{});
    defer server.deinit();

    const fork_pid = try std.posix.fork();
    if (fork_pid == 0) {
        std.process.execv(allocator, &[_][]const u8{ "xdg-open", url }) catch unreachable;
    }

    std.log.info("Opened {s} in your browser, close the window if it is lagging.", .{url});
    var client = try server.accept();
    defer client.stream.close();
    const response = try client.stream.reader().readAllAlloc(allocator, 4096);
    defer allocator.free(response);
    const start = std.mem.indexOf(u8, response, "code=").? + "code=".len;
    const end = std.mem.indexOfScalar(u8, response[start..], ' ').? + start;

    return allocator.dupe(u8, response[start..end]);
}

fn getRefreshToken(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    auth_code: []const u8,
    auth: []const u8,
) ![]const u8 {
    const uri = try std.Uri.parse("https://accounts.spotify.com/api/token");

    const body = try std.fmt.allocPrint(
        allocator,
        "grant_type=authorization_code&code={s}&redirect_uri=" ++ redirect_uri,
        .{auth_code},
    );
    defer allocator.free(body);

    const auth_header = try std.fmt.allocPrint(allocator, "Basic {s}", .{auth});
    defer allocator.free(auth_header);

    var header_buf: [4096]u8 = undefined;
    var req = try client.open(.POST, uri, .{
        .server_header_buffer = &header_buf,
        .headers = .{
            .authorization = .{ .override = auth_header },
            .content_type = .{ .override = "application/x-www-form-urlencoded" },
        },
    });
    defer req.deinit();
    req.transfer_encoding = .{ .content_length = body.len };
    try req.send();
    try req.writeAll(body);
    try req.finish();
    try req.wait();

    std.log.debug("getRefreshToken(): Response status: {s} ({d})", .{
        @tagName(req.response.status),
        @intFromEnum(req.response.status),
    });

    if (req.response.status != .ok) {
        return error.BadResponse;
    }

    const response = try req.reader().readAllAlloc(allocator, 4096);
    defer allocator.free(response);

    const Response = struct {
        access_token: []const u8,
        token_type: []const u8,
        expires_in: u64,
        scope: []const u8,
        refresh_token: []const u8,
    };

    const json = try std.json.parseFromSlice(Response, allocator, response, .{});
    defer json.deinit();

    return allocator.dupe(u8, json.value.refresh_token);
}
