//! https://developer.spotify.com/documentation/web-api/reference
// TODO: refactor

const std = @import("std");

const api_url = "https://api.spotify.com/v1";

/// https://developer.spotify.com/documentation/web-api/concepts/scopes
pub const scopes = [_][]const u8{
    "user-read-playback-state",
    "user-modify-playback-state",
    "user-library-modify",
};

pub const Request = enum {
    // GET
    playback_state,

    // PUT
    play,
    pause,
    repeat,
    seek,
    shuffle,
    volume,
    like,

    // POST
    next,
    prev,

    pub fn method(comptime self: Request) std.http.Method {
        return comptime switch (self) {
            .playback_state => .GET,
            .play, .pause, .repeat, .seek, .shuffle, .volume, .like => .PUT,
            .next, .prev => .POST,
        };
    }

    pub fn ResponseType(comptime self: Request) type {
        return comptime switch (self) {
            .playback_state => PlaybackState,
            .play => Play,
            .pause => Pause,
            .repeat => Repeat,
            .seek => Seek,
            .shuffle => Shuffle,
            .volume => Volume,
            .like => Like,
            .next => Next,
            .prev => Prev,
        };
    }
};

pub const Track = struct {
    album: ?Album = null,
    artists: []const Artist = &[_]Artist{},
    available_markets: ?[]const []const u8 = null,
    disc_number: ?u64 = null,
    duration_ms: u64 = 0,
    explicit: ?bool = null,
    external_ids: ?struct {
        isrc: ?[]const u8 = null,
        ean: ?[]const u8 = null,
        upc: ?[]const u8 = null,
    } = null,
    external_urls: ExternalUrl = .{},
    href: ?[]const u8 = null,
    id: []const u8,
    is_playable: ?bool = null,
    linked_from: ?struct {} = null,
    restrictions: ?struct {
        reason: ?[]const u8 = null,
    } = null,
    name: []const u8 = "track_name",
    popularity: ?u64 = null,
    preview_url: ?[]const u8 = null, // nullable
    track_number: ?u64 = null,
    type: []const u8 = "track",
    uri: ?[]const u8 = null,
    is_local: bool = false,
};

pub const Album = struct {
    album_type: []const u8,
    total_tracks: u64,
    available_markets: []const []const u8,
    external_urls: ExternalUrl,
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
    artists: []const Artist,
};

pub const Artist = struct {
    external_urls: ExternalUrl = .{},
    href: ?[]const u8 = null,
    id: ?[]const u8 = null,
    name: []const u8 = "artist_name",
    type: []const u8 = "artist",
    uri: ?[]const u8 = null,
};

pub const ExternalUrl = struct {
    spotify: []const u8 = "https://open.spotify.com",
};

/// https://developer.spotify.com/documentation/web-api/reference/get-information-about-the-users-current-playback
pub const PlaybackState = struct {
    device: ?struct {
        id: ?[]const u8 = null, // nullable
        is_active: ?bool = null,
        is_private_session: ?bool = null,
        is_restricted: ?bool = null,
        name: []const u8 = "device_name",
        type: ?[]const u8 = null,
        volume_percent: ?u64 = null, // nullable
        supports_volume: bool = false,
    } = null,
    repeat_state: []const u8 = "off",
    shuffle_state: bool = false,
    context: ?struct {
        type: ?[]const u8 = null,
        href: ?[]const u8 = null,
        external_urls: ExternalUrl = .{},
        uri: ?[]const u8 = null,
    } = null,
    timestamp: u64 = 0,
    progress_ms: u64 = 0,
    is_playing: bool = false,
    item: ?Track = null,
    currently_playing_type: ?[]const u8 = null,
    // actions...

    const request = "/me/player";
};

/// https://developer.spotify.com/documentation/web-api/reference/start-a-users-playback
const Play = struct {
    const request = "/me/player/play" ++ "?context_url={?s}";
};

/// https://developer.spotify.com/documentation/web-api/reference/pause-a-users-playback
const Pause = struct {
    const request = "/me/player/pause";
};

/// https://developer.spotify.com/documentation/web-api/reference/set-repeat-mode-on-users-playback
const Repeat = struct {
    const request = "/me/player/repeat" ++ "?state={s}";
};

/// https://developer.spotify.com/documentation/web-api/reference/seek-to-position-in-currently-playing-track
const Seek = struct {
    const request = "/me/player/seek" ++ "?position_ms={d}";
};

/// https://developer.spotify.com/documentation/web-api/reference/toggle-shuffle-for-users-playback
const Shuffle = struct {
    const request = "/me/player/shuffle" ++ "?state={}";
};

/// https://developer.spotify.com/documentation/web-api/reference/set-volume-for-users-playback
const Volume = struct {
    const request = "/me/player/volume" ++ "?volume_percent={d}";
};

/// https://developer.spotify.com/documentation/web-api/reference/save-tracks-user
const Like = struct {
    const request = "/me/tracks" ++ "?ids={s}";
};

/// https://developer.spotify.com/documentation/web-api/reference/skip-users-playback-to-next-track
const Next = struct {
    const request = "/me/player/next";
};

/// https://developer.spotify.com/documentation/web-api/reference/skip-users-playback-to-previous-track
const Prev = struct {
    const request = "/me/player/previous";
};

const Error = struct {
    @"error": struct {
        status: u64,
        message: []const u8,
        reason: ?[]const u8 = null,
    },
};

pub fn get(
    comptime request: Request,
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    access_token: []const u8,
) !std.json.Parsed(request.ResponseType()) {
    comptime std.debug.assert(request.method() == .GET);
    const T = request.ResponseType();

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

    std.log.debug("{s}({s}): Response status: {s} ({d})", .{
        @tagName(request.method()),
        @tagName(request),
        @tagName(req.response.status),
        @intFromEnum(req.response.status),
    });

    const response = try req.reader().readAllAlloc(allocator, 8192);
    defer allocator.free(response);

    switch (req.response.status) {
        .ok => return std.json.parseFromSlice(T, allocator, response, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        }),
        .no_content => {
            std.log.warn("Playback not available or active (204)", .{});
            return error.NotPlaying;
        },
        else => {
            const json = try std.json.parseFromSlice(Error, allocator, response, .{});
            defer json.deinit();
            std.log.err("{s} ({d})", .{ json.value.@"error".message, json.value.@"error".status });
            return error.BadResponse;
        },
    }
}

pub fn put(
    comptime request: Request,
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    access_token: []const u8,
    data: anytype,
) !void {
    const url = try std.fmt.allocPrint(allocator, api_url ++ request.ResponseType().request, data);
    defer allocator.free(url);
    const uri = try std.Uri.parse(url);
    const authorization = try std.fmt.allocPrint(allocator, "Bearer {s}", .{access_token});
    defer allocator.free(authorization);

    var header_buf: [4096]u8 = undefined;
    var req = try client.open(request.method(), uri, .{
        .server_header_buffer = &header_buf,
        .headers = .{ .authorization = .{ .override = authorization } },
    });
    defer req.deinit();
    req.transfer_encoding = .{ .content_length = 0 };
    try req.send();
    try req.finish();
    try req.wait();

    std.log.debug("{s}({s}): Response status: {s} ({d})", .{
        @tagName(request.method()),
        @tagName(request),
        @tagName(req.response.status),
        @intFromEnum(req.response.status),
    });

    switch (req.response.status) {
        .ok => return,
        .no_content => {
            std.log.warn("Playback not available or active (204)", .{});
            return; // TODO: error.NotPlaying;
        },
        else => {
            const response = try req.reader().readAllAlloc(allocator, 4096);
            defer allocator.free(response);
            const json = try std.json.parseFromSlice(Error, allocator, response, .{});
            defer json.deinit();
            std.log.err("{s} ({d})", .{ json.value.@"error".message, json.value.@"error".status });
            return error.BadResponse;
        },
    }
}

pub const post = put;
