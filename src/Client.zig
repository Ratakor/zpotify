const std = @import("std");
const api = @import("api.zig");

const Client = @This();

basic_auth: []const u8,
refresh_token: []const u8,
access_token: []const u8,
expiration: i64,
http_client: std.http.Client,
arena: std.heap.ArenaAllocator,

const redirect_uri = "http://127.0.0.1:9999/callback";
const save_filename = "config.json";

const Save = struct {
    basic_auth: []const u8,
    refresh_token: []const u8,
    access_token: []const u8,
    expiration: i64,
};

pub fn init(
    http_client_allocator: std.mem.Allocator,
    arena_child_allocator: std.mem.Allocator,
) !Client {
    var fba_buffer: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&fba_buffer);
    const fba_allocator = fba.allocator();
    var arena = std.heap.ArenaAllocator.init(arena_child_allocator);
    const arena_allocator = arena.allocator();

    const save_path = try getSavePath(fba_allocator);
    defer fba_allocator.free(save_path);
    const cwd = std.fs.cwd();
    const save_file = if (cwd.openFile(save_path, .{ .mode = .read_write })) |save_file| blk: {
        defer save_file.close();
        var save_file_buffer: [1024]u8 = undefined;
        var save_file_reader = save_file.reader(&save_file_buffer);
        var json_reader: std.json.Reader = .init(fba_allocator, &save_file_reader.interface);
        defer json_reader.deinit();
        if (std.json.parseFromTokenSourceLeaky(Save, arena_allocator, &json_reader, .{})) |save_json| {
            return .{
                .basic_auth = save_json.basic_auth,
                .refresh_token = save_json.refresh_token,
                .access_token = save_json.access_token,
                .expiration = save_json.expiration,
                .http_client = .{ .allocator = http_client_allocator },
                .arena = arena,
            };
        } else |err| {
            std.log.warn("Failed to parse the save file: {}", .{err});
            break :blk try cwd.createFile(save_path, .{ .mode = 0o600 });
        }
    } else |err| blk: {
        if (err != error.FileNotFound) {
            return err;
        }
        try cwd.makePath(save_path[0 .. save_path.len - save_filename.len]);
        break :blk try cwd.createFile(save_path, .{ .mode = 0o600 });
    };
    errdefer cwd.deleteFile(save_path) catch {};
    defer save_file.close();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll("Welcome to zpotify!\n");
    try stdout.writeAll("This is probably your first time running zpotify, so we need to authenticate with Spotify.\n");
    try stdout.writeAll("Go to https://developer.spotify.com/dashboard.\n");
    try stdout.writeAll("Create a new app, name and description doesn't matter but redirect URI must be '" ++ redirect_uri ++ "'.\n");
    try stdout.writeAll("Enter the following informations:\n");
    try stdout.flush();
    const client_id = try getClientData("ID", fba_allocator);
    defer fba_allocator.free(client_id);
    const client_secret = try getClientData("Secret", fba_allocator);
    defer fba_allocator.free(client_secret);

    const auth_code = try oauth2(fba_allocator, client_id);
    defer fba_allocator.free(auth_code);

    const basic_auth = blk: {
        var buf: [32 + 1 + 32]u8 = undefined;
        const source = try std.fmt.bufPrint(&buf, "{s}:{s}", .{ client_id, client_secret });
        var base64 = std.base64.standard.Encoder;
        const size = base64.calcSize(source.len);
        const dest = try arena_allocator.alloc(u8, size);
        break :blk base64.encode(dest, source);
    };

    var client: Client = .{
        .basic_auth = basic_auth,
        .refresh_token = undefined,
        .access_token = undefined,
        .expiration = undefined,
        .http_client = .{ .allocator = http_client_allocator },
        .arena = arena,
    };
    const body = try std.fmt.allocPrint(
        fba_allocator,
        "grant_type=authorization_code&code={s}&redirect_uri=" ++ redirect_uri,
        .{auth_code},
    );
    defer fba_allocator.free(body);
    client.refresh_token = (try client.getToken(body)).?;

    try client.updateSaveFile(save_file);
    std.log.info("Your informations have been saved to '{s}'.", .{save_path});

    return client;
}

pub fn deinit(self: *Client) void {
    self.http_client.deinit();
    self.arena.deinit();
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

// don't be dumb and use `std.http.Client.fetch` directly instead of building your own wrapper
// though it is bugged on zig 0.15.1 https://github.com/ziglang/zig/pull/24926
pub inline fn sendRequest(
    self: *Client,
    comptime T: type,
    comptime method: std.http.Method,
    url: []const u8,
    body: ?[]const u8,
) !T {
    return self.sendRequestOwned(T, method, url, body, self.arena.allocator());
}

pub fn sendRequestOwned(
    self: *Client,
    comptime T: type,
    comptime method: std.http.Method,
    url: []const u8,
    payload: ?[]const u8,
    arena_allocator: std.mem.Allocator,
) !T {
    const uri = try std.Uri.parse(url);
    var fba_buffer: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&fba_buffer);
    const auth_header = try self.getAuthHeader(fba.allocator());
    var req = try self.http_client.request(method, uri, .{
        .headers = .{ .authorization = .{ .override = auth_header } },
    });
    defer req.deinit();

    if (payload) |pl| {
        // smh sendBodyComplete requires a []u8 not []const u8
        // try req.sendBodyComplete(pl);
        req.transfer_encoding = .{ .content_length = pl.len };
        var body = try req.sendBodyUnflushed(&.{});
        try body.writer.writeAll(pl);
        try body.end();
        try req.connection.?.flush();
    } else {
        try req.sendBodiless();
    }

    // redirect_buffer is not needed if we have a payload but oh well
    var redirect_buffer: [8 * 1024]u8 = undefined;
    var response = try req.receiveHead(&redirect_buffer);

    std.log.debug(
        "sendRequest({}, {s}): Response status: {t} ({d})",
        .{ method, url, response.head.status, @intFromEnum(response.head.status) },
    );

    // usually compressed with gzip
    var decompress_buffer: [8 * std.compress.flate.max_window_len]u8 = undefined;
    var transfer_buffer: [64]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const reader = response.readerDecompressing(&transfer_buffer, &decompress, &decompress_buffer);
    // const reader = response.reader(&transfer_buffer);

    // debug raw response
    if (false) {
        var stdout_writer = std.fs.File.stdout().writer(&.{});
        const stdout = &stdout_writer.interface;
        const written = reader.streamRemaining(stdout) catch |err| switch (err) {
            error.ReadFailed => return response.bodyErr().?,
            else => |e| return e,
        };
        std.log.debug("written: {}", .{written});
        if (written > 0) {
            std.process.exit(0);
        }
    }

    var json_reader: std.json.Reader = .init(fba.allocator(), reader);
    defer json_reader.deinit();

    switch (response.head.status) {
        .ok => {
            if (T != void) {
                return std.json.parseFromTokenSourceLeaky(T, arena_allocator, &json_reader, .{
                    .allocate = .alloc_always,
                    .ignore_unknown_fields = true,
                });
            }
        },
        .no_content, .created, .accepted => {
            if (T != void) {
                return error.PlaybackNotAvailable;
            }
        },
        .not_found => return error.NoActiveDevice,
        else => {
            const Error = struct {
                @"error": struct {
                    status: u64,
                    message: []const u8,
                    reason: ?[]const u8 = null,
                },
            };
            if (std.json.parseFromTokenSourceLeaky(
                Error,
                fba.allocator(),
                &json_reader,
                .{},
            )) |json| {
                std.log.err("{s} ({d})", .{ json.@"error".message, json.@"error".status });
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
    // try file.seekTo(0);
    // var writer = file.writerStreaming(&.{});
    var writer = file.writer(&.{});
    try writer.interface.print("{f}", .{std.json.fmt(save, .{})});
}

fn getClientData(name: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var stdin_buffer: [64]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;
    var stdout_writer = std.fs.File.stdout().writer(&.{});
    const stdout = &stdout_writer.interface;

    const max_retries = 5;
    outer: for (0..max_retries) |_| {
        try stdout.print("Client {s}: ", .{name});
        const data = stdin.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                std.log.warn("The client {s} must be 32 bytes long", .{name});
                continue;
            },
            else => return err,
        };
        if (data.len != 32) {
            std.log.warn("The client {s} must be 32 bytes long", .{name});
            continue;
        }
        for (data) |byte| {
            if (!std.ascii.isHex(byte)) {
                std.log.warn("The client {s} must be a hex string", .{name});
                continue :outer;
            }
        }
        return allocator.dupe(u8, data);
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
    var reader = client.stream.reader(&.{});
    const size = try reader.interface().readSliceShort(&buffer);
    const response = buffer[0..size];
    const start = std.mem.indexOf(u8, response, "code=").? + "code=".len;
    const end = std.mem.indexOfScalar(u8, response[start..], ' ').? + start;

    return allocator.dupe(u8, response[start..end]);
}

fn getToken(self: *Client, payload: []const u8) !?[]const u8 {
    const uri = comptime try std.Uri.parse("https://accounts.spotify.com/api/token");
    var fba_buffer: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&fba_buffer);
    const auth_header = try std.fmt.allocPrint(fba.allocator(), "Basic {s}", .{self.basic_auth});
    var req = try self.http_client.request(.POST, uri, .{
        .redirect_behavior = .unhandled,
        .headers = .{
            .authorization = .{ .override = auth_header },
            .content_type = .{ .override = "application/x-www-form-urlencoded" },
        },
    });
    defer req.deinit();

    req.transfer_encoding = .{ .content_length = payload.len };
    var body = try req.sendBodyUnflushed(&.{});
    try body.writer.writeAll(payload);
    try body.end();
    try req.connection.?.flush();

    var response = try req.receiveHead(&.{});

    std.log.debug("getToken(): Response status: {t} ({d})", .{
        response.head.status,
        @intFromEnum(response.head.status),
    });

    // usually compressed with gzip
    var decompress_buffer: [std.compress.flate.max_window_len]u8 = undefined;
    var transfer_buffer: [64]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const reader = response.readerDecompressing(&transfer_buffer, &decompress, &decompress_buffer);

    var json_reader: std.json.Reader = .init(fba.allocator(), reader);
    defer json_reader.deinit();

    if (response.head.status != .ok) {
        const AuthError = struct {
            @"error": []const u8,
            error_description: ?[]const u8 = null,
        };
        if (std.json.parseFromTokenSourceLeaky(
            AuthError,
            fba.allocator(),
            &json_reader,
            .{},
        )) |json| {
            std.log.err("{?s} ({s})", .{ json.error_description, json.@"error" });
            if (std.mem.eql(u8, json.@"error", "invalid_grant")) {
                std.log.info("Please try again and if the problem persists run `zpotify logout`", .{});
            }
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
        const json = try std.json.parseFromTokenSourceLeaky(
            Response,
            self.arena.allocator(),
            &json_reader,
            .{},
        );
        self.access_token = json.access_token;
        self.expiration = std.time.timestamp() + @as(i64, @intCast(json.expires_in));
        if (json.refresh_token) |refresh_token| {
            return refresh_token;
        } else {
            return null;
        }
    }
}

fn getAuthHeader(self: *Client, allocator: std.mem.Allocator) ![]const u8 {
    if (self.expiration <= std.time.timestamp()) {
        const body = try std.fmt.allocPrint(
            allocator,
            "grant_type=refresh_token&refresh_token={s}",
            .{self.refresh_token},
        );
        defer allocator.free(body);
        if (try self.getToken(body)) |new_refresh_token| {
            self.refresh_token = new_refresh_token;
        }
        const save_path = try getSavePath(allocator);
        defer allocator.free(save_path);
        const save_file = try std.fs.openFileAbsolute(save_path, .{ .mode = .write_only });
        defer save_file.close();
        try self.updateSaveFile(save_file);
    }
    return std.fmt.allocPrint(allocator, "Bearer {s}", .{self.access_token});
}
