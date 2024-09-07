const std = @import("std");
const api = @import("api.zig");

const Config = @This();

authorization: []const u8,
refresh_token: []const u8,
access_token: []const u8,
expiration: i64,
allocator: std.mem.Allocator,

const redirect_uri = "http://localhost:9999/callback";

const Json = struct {
    authorization: []const u8,
    refresh_token: []const u8,
    access_token: []const u8,
    expiration: i64,
};

pub fn init(allocator: std.mem.Allocator, client: *std.http.Client) !Config {
    const config_path = try Config.getPath(allocator);
    defer allocator.free(config_path);
    const cwd = std.fs.cwd();
    const config_file = if (cwd.openFile(config_path, .{ .mode = .read_write })) |config_file| blk: {
        defer config_file.close();
        const content = try config_file.readToEndAlloc(allocator, 4096);
        defer allocator.free(content);
        if (std.json.parseFromSlice(Config.Json, allocator, content, .{})) |config_json| {
            defer config_json.deinit();

            // if (isExpired)
            if (config_json.value.expiration <= std.time.timestamp()) {
                var config: Config = .{
                    .authorization = try allocator.dupe(u8, config_json.value.authorization),
                    .refresh_token = try allocator.dupe(u8, config_json.value.refresh_token),
                    .access_token = undefined,
                    .expiration = undefined,
                    .allocator = allocator,
                };
                const payload = try std.fmt.allocPrint(
                    allocator,
                    "grant_type=refresh_token&refresh_token={s}",
                    .{config.refresh_token},
                );
                defer allocator.free(payload);
                if (try config.getToken(client, payload)) |new_refresh_token| {
                    allocator.free(config.refresh_token);
                    config.refresh_token = new_refresh_token;
                }
                try config.updateConfigFile(config_file);
                return config;
            } else {
                return .{
                    .authorization = try allocator.dupe(u8, config_json.value.authorization),
                    .refresh_token = try allocator.dupe(u8, config_json.value.refresh_token),
                    .access_token = try allocator.dupe(u8, config_json.value.access_token),
                    .expiration = config_json.value.expiration,
                    .allocator = allocator,
                };
            }
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
    defer config_file.close();

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

    var config: Config = .{
        .authorization = authorization,
        .refresh_token = undefined,
        .access_token = undefined,
        .expiration = undefined,
        .allocator = allocator,
    };
    const payload = try std.fmt.allocPrint(
        allocator,
        "grant_type=authorization_code&code={s}&redirect_uri=" ++ redirect_uri,
        .{auth_code},
    );
    defer allocator.free(payload);
    config.refresh_token = (try config.getToken(client, payload)).?;

    try config.updateConfigFile(config_file);
    std.log.info("Your information has been saved to '{s}'.", .{config_path});

    return config;
}

pub fn deinit(self: Config) void {
    self.allocator.free(self.authorization);
    self.allocator.free(self.refresh_token);
    self.allocator.free(self.access_token);
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

fn updateConfigFile(self: Config, file: std.fs.File) !void {
    const config_json: Config.Json = .{
        .authorization = self.authorization,
        .refresh_token = self.refresh_token,
        .access_token = self.access_token,
        .expiration = self.expiration,
    };
    try file.seekTo(0);
    try std.json.stringify(config_json, .{}, file.writer());
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
        @memcpy(buf[0..api.scopes[0].len], api.scopes[0]);
        var size: usize = api.scopes[0].len;
        for (api.scopes[1..]) |scope| {
            @memcpy(buf[size .. size + separator.len], separator);
            size += separator.len;
            @memcpy(buf[size .. size + scope.len], scope);
            size += scope.len;
        }
        break :blk buf[0..size];
    };

    // useless
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

fn getToken(self: *Config, client: *std.http.Client, payload: []const u8) !?[]const u8 {
    const uri = try std.Uri.parse("https://accounts.spotify.com/api/token");
    const auth_header = try std.fmt.allocPrint(self.allocator, "Basic {s}", .{self.authorization});
    defer self.allocator.free(auth_header);

    var header_buf: [4096]u8 = undefined;
    var req = try client.open(.POST, uri, .{
        .server_header_buffer = &header_buf,
        .headers = .{
            .authorization = .{ .override = auth_header },
            .content_type = .{ .override = "application/x-www-form-urlencoded" },
        },
    });
    defer req.deinit();
    req.transfer_encoding = .{ .content_length = payload.len };
    try req.send();
    try req.writeAll(payload);
    try req.finish();
    try req.wait();

    std.log.debug("getToken(): Response status: {s} ({d})", .{
        @tagName(req.response.status),
        @intFromEnum(req.response.status),
    });

    const response = try req.reader().readAllAlloc(self.allocator, 4096);
    defer self.allocator.free(response);

    if (req.response.status != .ok) {
        const Response = struct {
            @"error": ?[]const u8 = null,
            error_description: ?[]const u8 = null,
        };
        const json = try std.json.parseFromSlice(Response, self.allocator, response, .{});
        defer json.deinit();
        std.log.err("{?s} ({?s})", .{ json.value.error_description, json.value.@"error" });
        return error.BadResponse;
    } else {
        const Response = struct {
            access_token: []const u8,
            token_type: []const u8,
            expires_in: u64,
            scope: []const u8,
            refresh_token: ?[]const u8 = null,
        };
        const json = try std.json.parseFromSlice(Response, self.allocator, response, .{});
        defer json.deinit();

        self.access_token = try self.allocator.dupe(u8, json.value.access_token);
        self.expiration = std.time.timestamp() + @as(i64, @intCast(json.value.expires_in));
        if (json.value.refresh_token) |refresh_token| {
            return try self.allocator.dupe(u8, refresh_token);
        } else {
            return null;
        }
    }
}
