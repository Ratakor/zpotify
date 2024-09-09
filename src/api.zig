//! https://developer.spotify.com/documentation/web-api/reference

const std = @import("std");
pub const Client = @import("Client.zig");

const api_url = "https://api.spotify.com/v1";

/// https://developer.spotify.com/documentation/web-api/concepts/scopes
pub const scopes = [_][]const u8{
    "user-read-playback-state",
    "user-modify-playback-state",
    "user-library-modify",
    "user-library-read",
    "user-follow-read",
    "playlist-read-private",
};

pub const Track = struct {
    album: Album,
    artists: []const SimplifiedArtist,
    available_markets: []const []const u8 = &[_][]const u8{},
    disc_number: u64 = 0,
    duration_ms: u64 = 0,
    explicit: bool = false,
    external_ids: struct {
        isrc: []const u8 = "",
        ean: []const u8 = "",
        upc: []const u8 = "",
    } = .{},
    external_urls: ExternalUrls = .{},
    href: []const u8 = "",
    id: []const u8 = "",
    is_playable: bool = false,
    linked_from: struct {} = .{},
    restrictions: struct {
        reason: []const u8 = "",
    } = .{},
    name: []const u8 = "",
    popularity: u64 = 0,
    preview_url: ?[]const u8 = null,
    track_number: u64 = 0,
    type: []const u8 = "track",
    uri: []const u8 = "",
    is_local: bool = false,
};

pub const SimplifiedArtist = struct {
    external_urls: ExternalUrls = .{},
    href: []const u8 = "",
    id: []const u8 = "",
    name: []const u8 = "",
    type: []const u8 = "artist",
    uri: []const u8 = "",
};

pub const Artist = struct {
    external_urls: ExternalUrls = .{},
    followers: struct {
        href: ?[]const u8 = null,
        total: u64 = 0,
    },
    genres: []const []const u8 = &[_][]const u8{},
    href: []const u8 = "",
    id: []const u8 = "",
    images: []const Image = &[_]Image{},
    name: []const u8 = "",
    popularity: u64 = 0,
    type: []const u8 = "artist",
    uri: []const u8 = "",
};

pub const Album = struct {
    album_type: []const u8 = "",
    total_tracks: u64 = 0,
    available_markets: []const []const u8 = &[_][]const u8{},
    external_urls: ExternalUrls = .{},
    href: []const u8 = "",
    id: []const u8 = "",
    images: []const Image = &[_]Image{},
    name: []const u8 = "",
    release_date: []const u8 = "",
    release_date_precision: []const u8 = "",
    restrictions: struct {
        reason: []const u8 = "",
    } = .{},
    type: []const u8 = "album",
    uri: []const u8 = "",
    artists: []const SimplifiedArtist = &[_]SimplifiedArtist{},
};

pub const Playlist = struct {
    collaborative: bool = false,
    description: []const u8 = "",
    external_urls: ExternalUrls = .{},
    href: []const u8 = "",
    id: []const u8 = "",
    images: []const Image = &[_]Image{},
    name: []const u8 = "",
    owner: struct {
        external_urls: ExternalUrls = .{},
        followers: struct {
            href: ?[]const u8 = null,
            total: u64 = 0,
        } = .{},
        href: []const u8 = "",
        id: []const u8 = "",
        type: []const u8 = "user",
        uri: []const u8 = "",
        display_name: ?[]const u8 = null,
    } = .{},
    public: bool = false,
    snapshot_id: []const u8 = "",
    tracks: struct {
        href: []const u8 = "",
        total: u64 = 0,
    } = .{},
    type: []const u8 = "playlist",
    uri: []const u8 = "",
};

pub const Device = struct {
    id: ?[]const u8 = null,
    is_active: bool = false,
    is_private_session: bool = false,
    is_restricted: bool = false,
    name: []const u8 = "",
    type: []const u8 = "",
    volume_percent: ?u64 = null,
    supports_volume: bool = false,
};

pub const ExternalUrls = struct {
    spotify: []const u8 = "https://open.spotify.com",
};

pub const Image = struct {
    url: []const u8 = "",
    height: ?u64 = null,
    width: ?u64 = null,
};

pub fn Tracks(comptime saved: bool) type {
    return struct {
        href: []const u8 = "",
        limit: u64 = 0,
        next: ?[]const u8 = null,
        offset: u64 = 0,
        previous: ?[]const u8 = null,
        total: u64 = 0,
        items: []const if (saved) struct {
            track: Track,
            added_at: []const u8,
        } else Track,
    };
}

pub const SimplifiedArtists = struct {
    href: []const u8 = "",
    limit: u64 = 0,
    next: ?[]const u8 = null,
    offset: u64 = 0,
    previous: ?[]const u8 = null,
    total: u64 = 0,
    items: []const SimplifiedArtist = &[_]SimplifiedArtist{},
};

// care the JSON is coated in another struct, get a look at getUserArtists()
pub const Artists = struct {
    href: []const u8 = "",
    limit: u64 = 0,
    next: ?[]const u8 = null,
    cursors: struct {
        after: ?[]const u8 = null,
        before: ?[]const u8 = null,
    } = .{},
    total: u64 = 0,
    items: []const Artist = &[_]Artist{},
};

pub fn Albums(comptime saved: bool) type {
    return struct {
        href: []const u8 = "",
        limit: u64 = 0,
        next: ?[]const u8 = null,
        offset: u64 = 0,
        previous: ?[]const u8 = null,
        total: u64 = 0,
        items: []const if (saved) struct {
            album: Album,
            added_at: []const u8,
        } else Album,
    };
}

pub const Playlists = struct {
    href: []const u8 = "",
    limit: u64 = 0,
    next: ?[]const u8 = null,
    offset: u64 = 0,
    previous: ?[]const u8 = null,
    total: u64 = 0,
    items: []const Playlist = &[_]Playlist{},
};

pub const Devices = struct {
    devices: []const Device = &[_]Device{},
};

pub const PlaybackState = struct {
    device: ?Device = null,
    repeat_state: []const u8 = "off",
    shuffle_state: bool = false,
    context: struct {
        type: []const u8 = "",
        href: []const u8 = "",
        external_urls: ExternalUrls = .{},
        uri: []const u8 = "",
    } = .{},
    timestamp: u64 = 0,
    progress_ms: u64 = 0,
    is_playing: bool = false,
    item: ?Track = null,
    currently_playing_type: []const u8 = "",
    // actions...
};

pub const Search = struct {
    tracks: ?Tracks(false) = null,
    artists: ?SimplifiedArtists = null,
    albums: ?Albums(false) = null,
    playlists: ?Playlists = null,
};

/// https://developer.spotify.com/documentation/web-api/reference/get-information-about-the-users-current-playback
pub fn getPlaybackState(client: *Client) !std.json.Parsed(PlaybackState) {
    return client.sendRequest(PlaybackState, .GET, api_url ++ "/me/player", null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-a-users-available-devices
pub fn getDevices(client: *Client) !std.json.Parsed(Devices) {
    return client.sendRequest(Devices, .GET, api_url ++ "/me/player/devices", null);
}

/// https://developer.spotify.com/documentation/web-api/reference/search
pub fn search(
    client: *Client,
    query: []const u8, // will be sanitized
    types: []const u8, // comma separated list of types
    limit: u64, // max num of results, 0-50 (default 20)
    offset: u64, // index of first result to return (default 0)
) !std.json.Parsed(Search) {
    const url = try std.fmt.allocPrint(
        client.allocator,
        api_url ++ "/search?q={query}&type={s}&limit={d}&offset={d}",
        .{ std.Uri.Component{ .raw = query }, types, limit, offset },
    );
    defer client.allocator.free(url);
    return client.sendRequest(Search, .GET, url, null);
}
/// https://developer.spotify.com/documentation/web-api/reference/start-a-users-playback
pub fn startPlayback(
    client: *Client,
    context_uri: ?[]const u8, // for album, artist or playlist
    uris: ?[]const []const u8, // for tracks
) !void {
    const Body = struct {
        context_uri: ?[]const u8,
        uris: ?[]const []const u8,
        offset: ?struct { // union
            position: ?u64,
            uri: ?[]const u8,
        } = null,
        position_ms: ?u64 = null,
    };

    const body = try std.json.stringifyAlloc(
        client.allocator,
        Body{ .context_uri = context_uri, .uris = uris },
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

/// https://developer.spotify.com/documentation/web-api/reference/get-a-list-of-current-users-playlists
pub fn getUserPlaylists(client: *Client, limit: u64, offset: u64) !std.json.Parsed(Playlists) {
    const url = try std.fmt.allocPrint(
        client.allocator,
        api_url ++ "/me/playlists?limit={d}&offset={d}",
        .{ limit, offset },
    );
    defer client.allocator.free(url);
    return client.sendRequest(Playlists, .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-users-saved-tracks
pub fn getUserTracks(client: *Client, limit: u64, offset: u64) !std.json.Parsed(Tracks(true)) {
    const url = try std.fmt.allocPrint(
        client.allocator,
        api_url ++ "/me/tracks?limit={d}&offset={d}",
        .{ limit, offset },
    );
    defer client.allocator.free(url);
    return client.sendRequest(Tracks(true), .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-users-saved-albums
pub fn getUserAlbums(client: *Client, limit: u64, offset: u64) !std.json.Parsed(Albums(true)) {
    const url = try std.fmt.allocPrint(
        client.allocator,
        api_url ++ "/me/albums?limit={d}&offset={d}",
        .{ limit, offset },
    );
    defer client.allocator.free(url);
    return client.sendRequest(Albums(true), .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-followed
pub fn getUserArtists(client: *Client, limit: u64, after: ?[]const u8) !std.json.Parsed(Artists) {
    const url = try if (after) |a| std.fmt.allocPrint(
        client.allocator,
        api_url ++ "/me/following?type=artist&limit={d}&after={s}",
        .{ limit, a },
    ) else std.fmt.allocPrint(
        client.allocator,
        api_url ++ "/me/following?type=artist&limit={d}",
        .{limit},
    );
    defer client.allocator.free(url);
    const parsed = try client.sendRequest(struct { artists: Artists = .{} }, .GET, url, null);
    return .{
        .value = parsed.value.artists,
        .arena = parsed.arena,
    };
}

/// https://developer.spotify.com/documentation/web-api/reference/save-tracks-user
pub fn saveTracks(client: *Client, ids: []const u8) !void {
    const url = try std.fmt.allocPrint(client.allocator, api_url ++ "/me/tracks?ids={s}", .{ids});
    defer client.allocator.free(url);
    return client.sendRequest(void, .PUT, url, "");
}

/// https://developer.spotify.com/documentation/web-api/reference/remove-tracks-user
pub fn removeTracks(client: *Client, ids: []const u8) !void {
    const url = try std.fmt.allocPrint(client.allocator, api_url ++ "/me/tracks?ids={s}", .{ids});
    defer client.allocator.free(url);
    return client.sendRequest(void, .DELETE, url, null);
}
