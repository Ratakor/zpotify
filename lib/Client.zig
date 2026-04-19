//! Client for the API
//! This is basically a helper to
//! - Do http request with correct authorization header
//! - Avoid leaking memory with json parsing
//! - Authenticate the user & save authentication info to a config file
//! All functions are opinionated feel free to open an issue or a PR to make it more generic

const std = @import("std");
const api = @import("api.zig");

const Client = @This();

basic_auth: []const u8,
refresh_token: []const u8,
access_token: []const u8,
expiration: i64,
http_client: std.http.Client,
arena: *std.heap.ArenaAllocator,
save_file: ?std.fs.File,

const Save = struct {
    basic_auth: []const u8,
    refresh_token: []const u8,
    access_token: []const u8,
    expiration: i64,
};

pub fn init(
    comptime redirect_uri: []const u8,
    comptime scopes: []const api.Scope,
    /// Used for all client allocations. Must be thread-safe.
    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    save_path_: ?[]const u8,
) !Client {
    const arena_allocator = arena.allocator();
    const cwd = std.fs.cwd();

    const save_file = if (save_path_) |save_path|
        if (cwd.openFile(save_path, .{ .mode = .read_write })) |save_file| blk: {
            var save_file_buffer: [1024]u8 = undefined;
            var save_file_reader = save_file.reader(&save_file_buffer);
            var json_reader: std.json.Reader = .init(allocator, &save_file_reader.interface);
            defer json_reader.deinit();
            if (std.json.parseFromTokenSourceLeaky(Save, arena_allocator, &json_reader, .{})) |save_json| {
                return .{
                    .basic_auth = save_json.basic_auth,
                    .refresh_token = save_json.refresh_token,
                    .access_token = save_json.access_token,
                    .expiration = save_json.expiration,
                    .http_client = .{ .allocator = allocator },
                    .arena = arena,
                    .save_file = save_file,
                };
            } else |_| {
                // std.log.warn("Failed to parse the save file: {}", .{err});
                break :blk try cwd.createFile(save_path, .{ .mode = 0o600 });
            }
        } else |err| blk: {
            if (err != error.FileNotFound) {
                return err;
            }
            try cwd.makePath(std.fs.path.dirname(save_path).?);
            break :blk try cwd.createFile(save_path, .{ .mode = 0o600 });
        }
    else
        null;
    errdefer if (save_path_) |save_path| {
        save_file.?.close();
        cwd.deleteFile(save_path) catch {};
    };

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    // TODO: remove that and only output url from oauth2?
    // This is part of the opinionated and intrusive part.
    try stdout.writeAll("Welcome to zpotify!\n");
    try stdout.writeAll("This is probably your first time running zpotify, so we need to authenticate with Spotify.\n");
    try stdout.writeAll("Go to https://developer.spotify.com/dashboard.\n");
    try stdout.writeAll("Create a new app, name and description doesn't matter but redirect URI must be '" ++ redirect_uri ++ "'.\n");
    try stdout.writeAll("Enter the following informations:\n");
    try stdout.flush();
    const client_id = try getClientData("ID", allocator);
    defer allocator.free(client_id);
    const client_secret = try getClientData("Secret", allocator);
    defer allocator.free(client_secret);

    const oauth2_result = try oauth2(redirect_uri, scopes, allocator, client_id);
    const auth_code = oauth2_result.auth_code;
    const code_verifier = oauth2_result.code_verifier;
    defer allocator.free(auth_code);
    defer allocator.free(code_verifier);

    const basic_auth = blk: {
        var buf: [32 + 1 + 32]u8 = undefined;
        const source = try std.fmt.bufPrint(&buf, "{s}:{s}", .{ client_id, client_secret });
        var base64 = std.base64.url_safe_no_pad.Encoder;
        const size = base64.calcSize(source.len);
        const dest = try arena_allocator.alloc(u8, size);
        break :blk base64.encode(dest, source);
    };

    var client: Client = .{
        .basic_auth = basic_auth,
        .refresh_token = undefined,
        .access_token = undefined,
        .expiration = undefined,
        .http_client = .{ .allocator = allocator },
        .arena = arena,
        .save_file = save_file,
    };
    const body = try std.fmt.allocPrint(
        allocator,
        "client_id={s}&grant_type=authorization_code&code={s}&redirect_uri=" ++
            redirect_uri ++ "&code_verifier={s}",
        .{ client_id, auth_code, code_verifier },
    );
    defer allocator.free(body);
    client.refresh_token = (try client.getToken(body)).?;

    try client.updateSaveFile();

    return client;
}

/// Release all associated resources with the client.
/// WARN: The given arena is expected to be managed externally.
pub fn deinit(self: *Client) void {
    self.http_client.deinit();
    if (self.save_file) |save_file| {
        save_file.close();
    }
}

// rename all these to fetch, fetchOwned, ...(?)
pub inline fn sendRequest(
    self: *Client,
    comptime T: type,
    method: std.http.Method,
    url: []const u8,
    payload: ?[]const u8,
) !T {
    return self.sendRequestOwned(T, method, url, payload, self.arena.allocator());
}

pub fn sendRequestOwned(
    self: *Client,
    comptime T: type,
    method: std.http.Method,
    url: []const u8,
    payload: ?[]const u8,
    arena_allocator: std.mem.Allocator,
) !T {
    var fba_buffer: [4096]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&fba_buffer);

    // debug raw response
    if (false) {
        var stdout = std.fs.File.stdout().writer(&.{});
        _ = try self.sendRequestWriter(method, url, payload, &stdout.interface);
    }

    const result = try self.sendRequestRaw(method, url, payload, arena_allocator);

    var fixed_reader: std.Io.Reader = .fixed(result.buffer);
    const reader = &fixed_reader;
    var json_reader: std.json.Reader = .init(fba.allocator(), reader);
    defer json_reader.deinit();

    switch (result.status) {
        .ok => {
            if (T != void) {
                return std.json.parseFromTokenSourceLeaky(T, arena_allocator, &json_reader, .{
                    .allocate = .alloc_if_needed,
                    // This **must** be set to false even though it's tempting no to.
                    // I'd rather have some crash when spotify silently change its API than
                    // some error spawning out of nowhere after a few months.
                    // update: I gave up, spotify API is way too undocumented.
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

pub const SendRequestRawResult = struct {
    buffer: []u8,
    status: std.http.Status,
};

pub fn sendRequestRaw(
    self: *Client,
    method: std.http.Method,
    url: []const u8,
    payload: ?[]const u8,
    allocator: std.mem.Allocator,
) !SendRequestRawResult {
    var response: std.Io.Writer.Allocating = .init(allocator);
    defer response.deinit();

    const result = try self.sendRequestWriter(method, url, payload, &response.writer);

    return .{
        .buffer = try response.toOwnedSlice(),
        .status = result.status,
    };
}

pub fn sendRequestWriter(
    self: *Client,
    method: std.http.Method,
    url: []const u8,
    payload: ?[]const u8,
    response_writer: ?*std.Io.Writer,
) !std.http.Client.FetchResult {
    var fba_buffer: [4096]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&fba_buffer);
    const auth_header = try self.getAuthHeader(fba.allocator());

    // usually compressed with gzip
    var decompress_buffer: [32 * std.compress.flate.max_window_len]u8 = undefined;

    const result = try self.http_client.fetch(.{
        .decompress_buffer = &decompress_buffer,
        .response_writer = response_writer,
        .location = .{ .url = url },
        .method = method,
        .payload = payload,
        .headers = .{
            .authorization = .{ .override = auth_header },
        },
    });

    // std.log.debug(
    //     "zpotify: sendRequest({}, {s}): Response status: {t} ({d})",
    //     .{ method, url, result.status, @intFromEnum(result.status) },
    // );

    return result;
}

fn updateSaveFile(self: Client) !void {
    if (self.save_file) |file| {
        const save: Save = .{
            .basic_auth = self.basic_auth,
            .refresh_token = self.refresh_token,
            .access_token = self.access_token,
            .expiration = self.expiration,
        };
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        try writer.interface.print("{f}", .{std.json.fmt(save, .{})});
        try writer.end();
    }
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
    return error.TooManyRetries;
}

// The PKCE authorization flow starts with the creation of a code verifier.
// According to the PKCE standard, a code verifier is a high-entropy
// cryptographic random string with a length between 43 and 128 characters
// (the longer the better). It can contain letters, digits, underscores,
// periods, hyphens, or tildes.
fn generateRandomString(allocator: std.mem.Allocator) ![]const u8 {
    const possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-~";
    var prng: std.Random.DefaultPrng = .init(@bitCast(std.time.microTimestamp()));
    const rand = prng.random();

    // that could be constant, like 64
    const len = rand.intRangeAtMost(usize, 43, 128);
    const buf = try allocator.alloc(u8, len);

    for (buf) |*c| {
        c.* = possible[rand.intRangeLessThan(usize, 0, possible.len)];
    }

    return buf;
}

fn oauth2(
    comptime redirect_uri: []const u8,
    comptime scopes: []const api.Scope,
    allocator: std.mem.Allocator,
    client_id: []const u8,
) !struct {
    auth_code: []const u8,
    code_verifier: []const u8,
} {
    const scope = comptime blk: {
        var scopes_str: [scopes.len][]const u8 = undefined;
        for (scopes, &scopes_str) |scope, *scope_str| {
            scope_str.* = scope.toString();
        }
        var fba_buffer: [4096]u8 = undefined;
        var fba: std.heap.FixedBufferAllocator = .init(&fba_buffer);
        break :blk std.mem.join(fba.allocator(), "+", &scopes_str) catch unreachable;
    };

    const code_verifier = try generateRandomString(allocator);
    errdefer allocator.free(code_verifier);
    var hashed: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(code_verifier, &hashed, .{});
    const base64 = std.base64.url_safe_no_pad.Encoder;
    var base64_buf: [base64.calcSize(hashed.len)]u8 = undefined;
    const code_challenge = std.base64.url_safe_no_pad.Encoder.encode(&base64_buf, &hashed);

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
        "https://accounts.spotify.com/authorize?client_id={s}&" ++
            "response_type=code&redirect_uri=" ++ redirect_uri ++ //state={s}&" ++
            "&scope=" ++ scope ++ "&code_challenge_method=S256&code_challenge={s}",
        .{ client_id, code_challenge },
    );

    const localhost = comptime blk: {
        @setEvalBranchQuota(10_000);
        const uri = try std.Uri.parse(redirect_uri);
        const host = switch (uri.host.?) {
            .raw, .percent_encoded => |s| s,
        };
        break :blk try std.net.Address.parseIp4(host, uri.port.?);
    };
    var server = try localhost.listen(.{});
    defer server.deinit();

    const fork_pid = try std.posix.fork();
    if (fork_pid == 0) {
        return std.process.execv(allocator, &[_][]const u8{ "xdg-open", url });
    }
    std.log.info("Opened {s} in your browser, close the window if it is lagging.", .{url});

    var client = try server.accept();
    defer client.stream.close();
    var reader = client.stream.reader(&.{});
    const size = try reader.interface().readSliceShort(&buffer);
    const response = buffer[0..size];
    const start = std.mem.indexOf(u8, response, "code=").? + "code=".len;
    const end = std.mem.indexOfScalar(u8, response[start..], ' ').? + start;

    return .{
        .code_verifier = code_verifier,
        .auth_code = try allocator.dupe(u8, response[start..end]),
    };
}

// most of this is basically std.http.Client.fetch + JSON parsing
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
        try self.updateSaveFile();
    }
    return std.fmt.allocPrint(allocator, "Bearer {s}", .{self.access_token});
}
