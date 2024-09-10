const std = @import("std");
const api = @import("api.zig");

const Client = @This();

basic_auth: []const u8,
refresh_token: []const u8,
access_token: []const u8,
expiration: i64,
http_client: std.http.Client,
allocator: std.mem.Allocator,

const redirect_uri = "http://localhost:9999/callback";
const save_filename = "config.json";

const Save = struct {
    basic_auth: []const u8,
    refresh_token: []const u8,
    access_token: []const u8,
    expiration: i64,
};

pub fn init(allocator: std.mem.Allocator) !Client {
    const save_path = try getSavePath(allocator);
    defer allocator.free(save_path);
    const cwd = std.fs.cwd();
    const save_file = if (cwd.openFile(save_path, .{ .mode = .read_write })) |save_file| blk: {
        defer save_file.close();
        var json_reader = std.json.reader(allocator, save_file.reader());
        defer json_reader.deinit();
        if (std.json.parseFromTokenSource(Save, allocator, &json_reader, .{})) |save_json| {
            defer save_json.deinit();
            return .{
                .basic_auth = try allocator.dupe(u8, save_json.value.basic_auth),
                .refresh_token = try allocator.dupe(u8, save_json.value.refresh_token),
                .access_token = try allocator.dupe(u8, save_json.value.access_token),
                .expiration = save_json.value.expiration,
                .http_client = .{ .allocator = allocator },
                .allocator = allocator,
            };
        } else |err| {
            std.log.warn("Failed to parse the save file: {}", .{err});
            break :blk try cwd.createFile(save_path, .{});
        }
    } else |err| blk: {
        if (err != error.FileNotFound) {
            return err;
        }
        try cwd.makePath(save_path[0 .. save_path.len - save_filename.len]);
        break :blk try cwd.createFile(save_path, .{});
    };
    errdefer cwd.deleteFile(save_path) catch {};
    defer save_file.close();

    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("Welcome to zpotify!\n");
    try stdout.writeAll("This is probably your first time running zpotify, so we need to authenticate with Spotify.\n");
    try stdout.writeAll("Go to https://developer.spotify.com/dashboard.\n");
    try stdout.writeAll("Create a new app, name and description doesn't matter but redirect URI must be '" ++ redirect_uri ++ "'.\n");
    try stdout.writeAll("Enter the following informations:\n");
    const client_id = try getClientData("ID", allocator);
    defer allocator.free(client_id);
    const client_secret = try getClientData("Secret", allocator);
    defer allocator.free(client_secret);

    const auth_code = try oauth2(allocator, client_id);
    defer allocator.free(auth_code);

    const basic_auth = blk: {
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
    errdefer allocator.free(basic_auth);

    var client: Client = .{
        .basic_auth = basic_auth,
        .refresh_token = undefined,
        .access_token = undefined,
        .expiration = undefined,
        .http_client = .{ .allocator = allocator },
        .allocator = allocator,
    };
    const body = try std.fmt.allocPrint(
        allocator,
        "grant_type=authorization_code&code={s}&redirect_uri=" ++ redirect_uri,
        .{auth_code},
    );
    defer allocator.free(body);
    client.refresh_token = (try client.getToken(body)).?;

    try client.updateSaveFile(save_file);
    std.log.info("Your informations have been saved to '{s}'.", .{save_path});

    return client;
}

pub fn deinit(self: *Client) void {
    self.allocator.free(self.basic_auth);
    self.allocator.free(self.refresh_token);
    self.allocator.free(self.access_token);
    self.http_client.deinit();
}

pub fn getSavePath(allocator: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("XDG_DATA_HOME")) |xdg_data| {
        return std.fmt.allocPrint(allocator, "{s}/zpotify/" ++ save_filename, .{xdg_data});
    } else if (std.posix.getenv("HOME")) |home| {
        return std.fmt.allocPrint(allocator, "{s}/.local/share/zpotify/" ++ save_filename, .{home});
    } else {
        return error.EnvironmentVariableNotFound;
    }
}

pub fn sendRequest(
    self: *Client,
    comptime T: type,
    comptime method: std.http.Method,
    url: []const u8,
    body: ?[]const u8,
) !if (T == void) void else std.json.Parsed(T) {
    if (T == void) {
        return self.sendRequestLeaky(T, method, url, body, undefined);
    }

    var parsed = std.json.Parsed(T){
        .arena = try self.allocator.create(std.heap.ArenaAllocator),
        .value = undefined,
    };
    errdefer self.allocator.destroy(parsed.arena);
    parsed.arena.* = std.heap.ArenaAllocator.init(self.allocator);
    errdefer parsed.arena.deinit();

    parsed.value = try self.sendRequestLeaky(T, method, url, body, parsed.arena.allocator());

    return parsed;
}

pub fn sendRequestLeaky(
    self: *Client,
    comptime T: type,
    comptime method: std.http.Method,
    url: []const u8,
    body: ?[]const u8,
    arena: std.mem.Allocator,
) !T {
    const uri = try std.Uri.parse(url);
    const auth_header = try self.getAuthHeader();
    defer self.allocator.free(auth_header);
    var header_buf: [4096]u8 = undefined;
    var req = try self.http_client.open(method, uri, .{
        .server_header_buffer = &header_buf,
        .headers = .{ .authorization = .{ .override = auth_header } },
    });
    defer req.deinit();
    if (body) |b| {
        req.transfer_encoding = .{ .content_length = b.len };
    }
    try req.send();
    if (body) |b| {
        try req.writeAll(b);
        try req.finish();
    }
    try req.wait();

    std.log.debug("sendRequest({}, {s}): Response status: {s} ({d})", .{
        method,
        url,
        @tagName(req.response.status),
        @intFromEnum(req.response.status),
    });

    switch (req.response.status) {
        .ok => {
            if (T != void) {
                var json_reader = std.json.reader(self.allocator, req.reader());
                defer json_reader.deinit();
                return std.json.parseFromTokenSourceLeaky(T, arena, &json_reader, .{
                    .allocate = .alloc_always,
                    .ignore_unknown_fields = true,
                });
            }
        },
        .no_content, .created, .accepted => {
            if (T != void) {
                std.log.warn("Playback not available or active ({d})", .{
                    @intFromEnum(req.response.status),
                });
                return error.NotPlaying;
            }
        },
        .not_found => {
            std.log.warn("No active device found ({d})", .{@intFromEnum(req.response.status)});
            return error.NoActiveDevice;
        },
        else => {
            const Error = struct {
                @"error": struct {
                    status: u64,
                    message: []const u8,
                    reason: ?[]const u8 = null,
                },
            };
            var json_reader = std.json.reader(self.allocator, req.reader());
            defer json_reader.deinit();
            if (std.json.parseFromTokenSource(Error, self.allocator, &json_reader, .{})) |json| {
                std.log.err("{s} ({d})", .{ json.value.@"error".message, json.value.@"error".status });
                json.deinit();
            } else |err| {
                std.log.err("Failed to parse the error response: {}", .{err});
            }
            return error.BadResponse;
        },
    }
}

fn updateSaveFile(self: Client, file: std.fs.File) !void {
    const save: Save = .{
        .basic_auth = self.basic_auth,
        .refresh_token = self.refresh_token,
        .access_token = self.access_token,
        .expiration = self.expiration,
    };
    try file.seekTo(0);
    try std.json.stringify(save, .{}, file.writer());
}

fn getClientData(name: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const max_retries = 5;
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    outer: for (0..max_retries) |_| {
        try stdout.print("Client {s}: ", .{name});
        const data = stdin.readUntilDelimiterAlloc(allocator, '\n', 64) catch |err| switch (err) {
            error.StreamTooLong => {
                std.log.warn("The client {s} must be 32 bytes long", .{name});
                continue;
            },
            else => return err,
        };
        if (data.len != 32) {
            std.log.warn("The client {s} must be 32 bytes long", .{name});
            allocator.free(data);
            continue;
        }
        for (data) |byte| {
            if (!std.ascii.isHex(byte)) {
                std.log.warn("The client {s} must be a hex string", .{name});
                allocator.free(data);
                continue :outer;
            }
        }
        return data;
    }
    std.log.err("Too many retries", .{});
    std.process.exit(1);
}

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

    // TODO: returns INVALID_CLIENT: Invalid client
    // const state = blk: {
    //     var source: [16]u8 = undefined;
    //     var prng = std.Random.DefaultPrng.init(@bitCast(std.time.microTimestamp()));
    //     prng.fill(&source);
    //     var base64 = std.base64.url_safe_no_pad.Encoder;
    //     const size = base64.calcSize(source.len);
    //     const buffer = try allocator.alloc(u8, size); // use the static buffer below
    //     break :blk base64.encode(buffer, &source);
    // };
    // defer allocator.free(state);

    var buffer: [4096]u8 = undefined; // will be reutilized
    const url = try std.fmt.bufPrint(
        &buffer,
        "https://accounts.spotify.com/authorize?client_id={s}&" ++ //state={s}&" ++
            "response_type=code&redirect_uri=" ++ redirect_uri ++ "&scope=" ++ scope,
        .{client_id},
    );

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
    const size = try client.stream.readAll(&buffer);
    const response = buffer[0..size];
    const start = std.mem.indexOf(u8, response, "code=").? + "code=".len;
    const end = std.mem.indexOfScalar(u8, response[start..], ' ').? + start;

    return allocator.dupe(u8, response[start..end]);
}

fn getToken(self: *Client, body: []const u8) !?[]const u8 {
    const uri = try std.Uri.parse("https://accounts.spotify.com/api/token");
    var auth_buf: [128]u8 = undefined;
    const auth_header = try std.fmt.bufPrint(&auth_buf, "Basic {s}", .{self.basic_auth});

    var header_buf: [4096]u8 = undefined;
    var req = try self.http_client.open(.POST, uri, .{
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

    std.log.debug("getToken(): Response status: {s} ({d})", .{
        @tagName(req.response.status),
        @intFromEnum(req.response.status),
    });

    var json_reader = std.json.reader(self.allocator, req.reader());
    defer json_reader.deinit();

    if (req.response.status != .ok) {
        const AuthError = struct {
            @"error": []const u8,
            error_description: ?[]const u8 = null,
        };
        if (std.json.parseFromTokenSource(AuthError, self.allocator, &json_reader, .{})) |json| {
            std.log.err("{?s} ({s})", .{ json.value.error_description, json.value.@"error" });
            json.deinit();
        } else |err| {
            std.log.err("Failed to parse the error response: {}", .{err});
        }
        return error.BadResponse;
    } else {
        const Response = struct {
            access_token: []const u8,
            token_type: []const u8,
            expires_in: u64,
            scope: []const u8,
            refresh_token: ?[]const u8 = null,
        };
        const json = try std.json.parseFromTokenSource(Response, self.allocator, &json_reader, .{});
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

fn getAuthHeader(self: *Client) ![]const u8 {
    if (self.expiration <= std.time.timestamp()) {
        var buffer: [256]u8 = undefined;
        const body = try std.fmt.bufPrint(
            &buffer,
            "grant_type=refresh_token&refresh_token={s}",
            .{self.refresh_token},
        );
        self.allocator.free(self.access_token);
        if (try self.getToken(body)) |new_refresh_token| {
            self.allocator.free(self.refresh_token);
            self.refresh_token = new_refresh_token;
        }
        const save_path = try getSavePath(self.allocator);
        defer self.allocator.free(save_path);
        const save_file = try std.fs.openFileAbsolute(save_path, .{ .mode = .write_only });
        defer save_file.close();
        try self.updateSaveFile(save_file);
    }
    return std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.access_token});
}
