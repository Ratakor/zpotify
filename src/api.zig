//! https://developer.spotify.com/documentation/web-api/reference

const std = @import("std");
pub const Client = @import("Client.zig");

const api_url = "https://api.spotify.com/v1";

/// https://developer.spotify.com/documentation/web-api/concepts/scopes
pub const scopes = [_][]const u8{
    "user-read-playback-state",
    "user-modify-playback-state",
    "user-library-modify",
};

pub const Track = struct {
    album: Album,
    artists: []const Artist,
    available_markets: ?[]const []const u8 = null,
    disc_number: ?u64 = null,
    duration_ms: u64 = 0,
    explicit: ?bool = null,
    external_ids: ?struct {
        isrc: ?[]const u8 = null,
        ean: ?[]const u8 = null,
        upc: ?[]const u8 = null,
    } = null,
    external_urls: ExternalUrls = .{},
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

pub const Artist = struct {
    external_urls: ExternalUrls = .{},
    href: ?[]const u8 = null,
    id: ?[]const u8 = null,
    name: []const u8 = "artist_name",
    type: []const u8 = "artist",
    uri: ?[]const u8 = null,
};

pub const Album = struct {
    album_type: []const u8,
    total_tracks: u64,
    available_markets: []const []const u8,
    external_urls: ExternalUrls,
    href: []const u8,
    id: []const u8,
    images: []const Image,
    name: []const u8,
    release_date: []const u8,
    release_date_precision: []const u8,
    restrictions: ?struct {
        reason: ?[]const u8 = null,
    } = null,
    type: []const u8 = "album",
    uri: []const u8,
    artists: []const Artist,
};

pub const Playlist = struct {
    collaborative: ?bool = null,
    description: ?[]const u8 = null,
    external_urls: ExternalUrls = .{},
    href: ?[]const u8 = null,
    id: ?[]const u8 = null,
    images: []const Image = &[_]Image{},
    name: []const u8 = "playlist_name",
    owner: ?struct {
        external_urls: ExternalUrls = .{},
        followers: ?struct {
            href: ?[]const u8 = null, // nullable
            total: ?u64 = null,
        } = null,
        href: ?[]const u8 = null,
        id: ?[]const u8 = null,
        type: []const u8 = "user",
        uri: ?[]const u8 = null,
        display_name: ?[]const u8 = null, // nullable
    } = null,
    public: ?bool = null,
    snapshot_id: ?[]const u8 = null,
    tracks: ?struct {
        href: ?[]const u8 = null,
        total: ?u64 = null,
    } = null,
    type: []const u8 = "playlist",
    uri: ?[]const u8 = null,
};

pub const ExternalUrls = struct {
    spotify: []const u8 = "https://open.spotify.com",
};

pub const Image = struct {
    url: []const u8,
    height: ?u64,
    width: ?u64,
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
        external_urls: ExternalUrls = .{},
        uri: ?[]const u8 = null,
    } = null,
    timestamp: u64 = 0,
    progress_ms: u64 = 0,
    is_playing: bool = false,
    item: ?Track = null,
    currently_playing_type: ?[]const u8 = null,
    // actions...
};

/// https://developer.spotify.com/documentation/web-api/reference/search
pub const Search = struct {
    tracks: struct {
        href: []const u8,
        limit: u64,
        next: ?[]const u8,
        offset: u64,
        previous: ?[]const u8,
        total: u64,
        items: []const Track,
    },
    artists: struct {
        href: []const u8,
        limit: u64,
        next: ?[]const u8,
        offset: u64,
        previous: ?[]const u8,
        total: u64,
        items: []const Artist,
    },
    albums: struct {
        href: []const u8,
        limit: u64,
        next: ?[]const u8,
        offset: u64,
        previous: ?[]const u8,
        total: u64,
        items: []const Album,
    },
    playlists: struct {
        href: []const u8,
        limit: u64,
        next: ?[]const u8,
        offset: u64,
        previous: ?[]const u8,
        total: u64,
        items: []const Playlist,
    },
    // shows...
    // episodes...
    // audiobooks...
};

pub const Error = struct {
    @"error": struct {
        status: u64,
        message: []const u8,
        reason: ?[]const u8 = null,
    },
};

pub fn getPlaybackState(client: *Client) !std.json.Parsed(PlaybackState) {
    return client.sendRequest(PlaybackState, .GET, api_url ++ "/me/player", null);
}

// TODO: sanitize query
// TODO: sanitize types <- ask user a comma serparated list of type or ?
// TODO: limit, offset
pub fn search(client: *Client, query: []const u8, types: []const u8) !std.json.Parsed(Search) {
    const url = std.fmt.allocPrint(client.allocator, api_url ++ "/search?q={s}&type={s}", .{ query, types });
    defer client.allocator.free(url);
    return client.sendRequest(Search, .GET, url, null);
}

// TODO
/// https://developer.spotify.com/documentation/web-api/reference/start-a-users-playback
pub fn startPlayback(
    client: *Client,
) !void {
    const Body = struct {
        context_uri: ?[]const u8 = null,
        uris: ?[]const []const u8 = null,
        offset: ?struct {
            position: ?u64,
            uri: ?[]const u8,
        } = null,
        position_ms: ?u64 = null,
    };

    const body = try std.json.stringifyAlloc(
        client.allocator,
        Body{},
        .{ .emit_null_optional_fields = false },
    );
    defer client.allocator.free(body);

    return client.sendRequest(void, .PUT, api_url ++ "/me/player/play", body);
}

/// https://developer.spotify.com/documentation/web-api/reference/pause-a-users-playback
pub fn pausePlayback(client: *Client) !void {
    return client.sendRequest(void, .PUT, api_url ++ "/me/player/pause", "");
}

/// https://developer.spotify.com/documentation/web-api/reference/skip-users-playback-to-next-track
pub fn skipToNext(client: *Client) !void {
    return client.sendRequest(void, .POST, api_url ++ "/me/player/next", "");
}

/// https://developer.spotify.com/documentation/web-api/reference/skip-users-playback-to-previous-track
pub fn skipToPrevious(client: *Client) !void {
    return client.sendRequest(void, .POST, api_url ++ "/me/player/previous", "");
}

/// https://developer.spotify.com/documentation/web-api/reference/seek-to-position-in-currently-playing-track
pub fn seekToPosition(client: *Client, position_ms: u64) !void {
    var buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api_url ++ "/me/player/seek?position_ms={d}", .{position_ms});
    return client.sendRequest(void, .PUT, url, "");
}

/// https://developer.spotify.com/documentation/web-api/reference/set-repeat-mode-on-users-playback
pub fn setRepeatMode(client: *Client, state: []const u8) !void {
    var buf: [64]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api_url ++ "/me/player/repeat?state={s}", .{state});
    return client.sendRequest(void, .PUT, url, "");
}

/// https://developer.spotify.com/documentation/web-api/reference/set-volume-for-users-playback
pub fn setVolume(client: *Client, volume: u64) !void {
    var buf: [64]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api_url ++ "/me/player/volume?volume_percent={d}", .{volume});
    return client.sendRequest(void, .PUT, url, "");
}

/// https://developer.spotify.com/documentation/web-api/reference/toggle-shuffle-for-users-playback
pub fn toggleShuffle(client: *Client, state: bool) !void {
    var buf: [64]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api_url ++ "/me/player/shuffle?state={}", .{state});
    return client.sendRequest(void, .PUT, url, "");
}

/// https://developer.spotify.com/documentation/web-api/reference/save-tracks-user
pub fn saveTrack(client: *Client, id: []const u8) !void {
    var buf: [64]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api_url ++ "/me/tracks?ids={s}", .{id});
    return client.sendRequest(void, .PUT, url, "");
}
