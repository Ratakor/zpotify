//! https://developer.spotify.com/documentation/web-api/reference

const std = @import("std");
pub const Client = @import("Client.zig");

const api_url = "https://api.spotify.com/v1";

/// https://developer.spotify.com/documentation/web-api/concepts/scopes
pub const scopes = [_][]const u8{
    "user-read-currently-playing",
    "user-read-playback-state",
    "user-modify-playback-state",
    "user-library-modify",
    "user-library-read",
    "user-follow-read",
    "user-follow-modify",
    "playlist-read-private",
    "playlist-modify-public",
    "playlist-modify-private",
};

pub const Track = struct {
    album: Album = .{},
    artists: []const SimplifiedArtist = &[_]SimplifiedArtist{},
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
    followers: Followers = .{},
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
    album_group: []const u8 = "",
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
        followers: Followers = .{},
        href: []const u8 = "",
        id: []const u8 = "",
        type: []const u8 = "user",
        uri: []const u8 = "",
        display_name: ?[]const u8 = null,
    } = .{},
    // primary_color: ?[]const u8 = null,
    public: ?bool = null, // nullable but not in the docs :D
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

pub const Followers = struct {
    href: ?[]const u8 = null,
    total: u64 = 0,
};

// used for Tracks() and Albums()
const Kind = enum { default, saved, playlist };

pub fn Tracks(comptime kind: Kind) type {
    return struct {
        href: []const u8 = "",
        limit: u64 = 0,
        next: ?[]const u8 = null,
        offset: u64 = 0,
        previous: ?[]const u8 = null,
        total: u64 = 0,
        items: []const switch (kind) {
            .default => Track,
            .saved => struct {
                track: Track = .{},
                added_at: []const u8,
            },
            .playlist => struct {
                added_at: []const u8,
                added_by: ?struct { // nullable on very old playlists
                    external_urls: ExternalUrls = .{},
                    followers: Followers = .{},
                    href: []const u8 = "",
                    id: []const u8 = "",
                    type: []const u8 = "user",
                    uri: []const u8 = "",
                } = null,
                is_local: bool = false,
                track: Track = .{}, // can be an Episode
                // primary_color: ?[]const u8 = null,
                // video_thumbnail: struct {
                //     url: ?[]const u8 = null,
                // } = .{},
            },
        },
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

pub fn Albums(comptime kind: Kind) type {
    return struct {
        href: []const u8 = "",
        limit: u64 = 0,
        next: ?[]const u8 = null,
        offset: u64 = 0,
        previous: ?[]const u8 = null,
        total: u64 = 0,
        items: []const switch (kind) {
            .default => Album,
            .saved => struct {
                album: Album = .{},
                added_at: []const u8 = "",
            },
            else => unreachable,
        },
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

// care the JSON is coated in a struct, get a look at getDevices()
pub const Devices = []const Device;

pub const PlaybackState = struct {
    device: ?Device = null,
    repeat_state: []const u8 = "off",
    shuffle_state: bool = false,
    context: ?struct {
        type: []const u8 = "",
        href: []const u8 = "",
        external_urls: ExternalUrls = .{},
        uri: []const u8 = "",
    } = null,
    timestamp: u64 = 0,
    progress_ms: u64 = 0,
    is_playing: bool = false,
    item: ?Track = null,
    currently_playing_type: []const u8 = "",
    // actions...
    // smart_shuffle: ?bool = null,
};

pub const Search = struct {
    tracks: ?Tracks(.default) = null,
    artists: ?Artists = null,
    albums: ?Albums(.default) = null,
    playlists: ?Playlists = null,
};

pub const Queue = struct {
    currently_playing: ?Track = null,
    queue: []const Track = &[_]Track{},
};

/// https://developer.spotify.com/documentation/web-api/reference/get-information-about-the-users-current-playback
pub fn getPlaybackState(client: *Client) !PlaybackState {
    return client.sendRequest(PlaybackState, .GET, api_url ++ "/me/player", null);
}

pub fn getPlaybackStateOwned(client: *Client, arena: std.mem.Allocator) !PlaybackState {
    return client.sendRequestOwned(PlaybackState, .GET, api_url ++ "/me/player", null, arena);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-a-users-available-devices
pub fn getDevices(client: *Client) !Devices {
    return (try client.sendRequest(
        struct { devices: Devices = &[_]Device{} },
        .GET,
        api_url ++ "/me/player/devices",
        null,
    )).devices;
}

/// https://developer.spotify.com/documentation/web-api/reference/search
pub fn search(
    client: *Client,
    query: []const u8, // will be sanitized
    types: []const u8, // comma separated list of types
    limit: u64, // max num of results, 0-50 (default 20)
    offset: u64, // index of first result to return (default 0)
) !Search {
    var buf: [4096]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &buf,
        api_url ++ "/search?q={query}&type={s}&limit={d}&offset={d}",
        .{ std.Uri.Component{ .raw = query }, types, limit, offset },
    );
    return client.sendRequest(Search, .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/start-a-users-playback
pub fn startPlayback(
    client: *Client,
    data: ?union(enum) {
        context_uri: []const u8, // for album, artist or playlist
        uris: []const []const u8, // for tracks
    },
    device_id: ?[]const u8,
) !void {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(buf[0..]);
    const body = blk: {
        if (data) |uri| {
            try std.json.stringify(uri, .{}, fbs.writer());
            break :blk fbs.getWritten();
        } else {
            break :blk "{}";
        }
    };

    if (device_id) |id| {
        fbs = std.io.fixedBufferStream(buf[body.len..]);
        try fbs.writer().print(api_url ++ "/me/player/play?device_id={s}", .{id});
        const url = fbs.getWritten();
        return client.sendRequest(void, .PUT, url, body);
    } else {
        return client.sendRequest(void, .PUT, api_url ++ "/me/player/play", body);
    }
}

/// https://developer.spotify.com/documentation/web-api/reference/pause-a-users-playback
pub fn pausePlayback(client: *Client) !void {
    return client.sendRequest(void, .PUT, api_url ++ "/me/player/pause", "");
}

/// https://developer.spotify.com/documentation/web-api/reference/transfer-a-users-playback
pub fn transferPlayback(client: *Client, device_id: []const u8) !void {
    var buf: [128]u8 = undefined;
    const body = try std.fmt.bufPrint(&buf, "{{\"device_ids\":[\"{s}\"]}}", .{device_id});
    return client.sendRequest(void, .PUT, api_url ++ "/me/player", body);
}

/// https://developer.spotify.com/documentation/web-api/reference/add-to-queue
pub fn addToQueue(client: *Client, uri: []const u8) !void {
    var buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api_url ++ "/me/player/queue?uri={s}", .{uri});
    return client.sendRequest(void, .POST, url, "");
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
pub fn getUserPlaylists(client: *Client, limit: u64, offset: u64) !Playlists {
    var buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &buf,
        api_url ++ "/me/playlists?limit={d}&offset={d}",
        .{ limit, offset },
    );
    return client.sendRequest(Playlists, .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-users-saved-tracks
pub fn getUserTracks(client: *Client, limit: u64, offset: u64) !Tracks(.saved) {
    var buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &buf,
        api_url ++ "/me/tracks?limit={d}&offset={d}",
        .{ limit, offset },
    );
    return client.sendRequest(Tracks(.saved), .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-users-saved-albums
pub fn getUserAlbums(client: *Client, limit: u64, offset: u64) !Albums(.saved) {
    var buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &buf,
        api_url ++ "/me/albums?limit={d}&offset={d}",
        .{ limit, offset },
    );
    return client.sendRequest(Albums(.saved), .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-followed
pub fn getUserArtists(client: *Client, limit: u64, after: ?[]const u8) !Artists {
    var buf: [128]u8 = undefined;
    const url = try if (after) |a| std.fmt.bufPrint(
        &buf,
        api_url ++ "/me/following?type=artist&limit={d}&after={s}",
        .{ limit, a },
    ) else std.fmt.bufPrint(&buf, api_url ++ "/me/following?type=artist&limit={d}", .{limit});
    return (try client.sendRequest(struct { artists: Artists = .{} }, .GET, url, null)).artists;
}

/// https://developer.spotify.com/documentation/web-api/reference/save-tracks-user
pub fn saveTracks(client: *Client, ids: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api_url ++ "/me/tracks?ids={s}", .{ids});
    return client.sendRequest(void, .PUT, url, "");
}

/// https://developer.spotify.com/documentation/web-api/reference/remove-tracks-user
pub fn removeTracks(client: *Client, ids: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api_url ++ "/me/tracks?ids={s}", .{ids});
    return client.sendRequest(void, .DELETE, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/save-albums-user
pub fn saveAlbums(client: *Client, ids: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api_url ++ "/me/albums?ids={s}", .{ids});
    return client.sendRequest(void, .PUT, url, "");
}

/// https://developer.spotify.com/documentation/web-api/reference/remove-albums-user
pub fn removeAlbums(client: *Client, ids: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api_url ++ "/me/albums?ids={s}", .{ids});
    return client.sendRequest(void, .DELETE, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/follow-artists-users
pub fn followArtists(client: *Client, ids: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api_url ++ "/me/following?type=artist&ids={s}", .{ids});
    return client.sendRequest(void, .PUT, url, "");
}

/// https://developer.spotify.com/documentation/web-api/reference/unfollow-artists-users
pub fn unfollowArtists(client: *Client, ids: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api_url ++ "/me/following?type=artist&ids={s}", .{ids});
    return client.sendRequest(void, .DELETE, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/follow-playlist
pub fn followPlaylist(client: *Client, id: []const u8) !void {
    var buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api_url ++ "/playlists/{s}/followers", .{id});
    return client.sendRequest(void, .PUT, url, "{\"public\":false}");
}

/// https://developer.spotify.com/documentation/web-api/reference/unfollow-playlist
pub fn unfollowPlaylist(client: *Client, id: []const u8) !void {
    var buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api_url ++ "/playlists/{s}/followers", .{id});
    return client.sendRequest(void, .DELETE, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-an-artist
pub fn getArtist(client: *Client, id: []const u8) !Artist {
    var buf: [256]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api_url ++ "/artists/{s}", .{id});
    return client.sendRequest(Artist, .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-an-albums-tracks
pub fn getAlbumTracks(
    client: *Client,
    id: []const u8,
    limit: usize,
    offset: usize,
) !Tracks(.default) {
    var buf: [256]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &buf,
        api_url ++ "/albums/{s}/tracks?limit={d}&offset={d}",
        .{ id, limit, offset },
    );
    return client.sendRequest(Tracks(.default), .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-playlists-tracks
pub fn getPlaylistTracks(
    client: *Client,
    id: []const u8,
    limit: usize,
    offset: usize,
) !Tracks(.playlist) {
    var buf: [256]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &buf,
        api_url ++ "/playlists/{s}/tracks?limit={d}&offset={d}",
        .{ id, limit, offset },
    );
    return client.sendRequest(Tracks(.playlist), .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-an-artists-albums
pub fn getArtistAlbums(
    client: *Client,
    id: []const u8,
    // include_groups: []const u8, // album, single, appears_on, compilation
    limit: usize,
    offset: usize,
) !Albums(.default) {
    var buf: [256]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &buf,
        api_url ++ "/artists/{s}/albums?limit={d}&offset={d}",
        .{ id, limit, offset },
    );
    return client.sendRequest(Albums(.default), .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-queue
pub fn getQueue(client: *Client) !Queue {
    return try client.sendRequest(Queue, .GET, api_url ++ "/me/player/queue", null);
}
