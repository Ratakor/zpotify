//! https://developer.spotify.com/documentation/web-api/reference

// TODO: remove dependency on Client or make it less tied to the CLI

const std = @import("std");
pub const Client = @import("Client.zig");

pub const player = @import("api/player.zig");

/// https://developer.spotify.com/documentation/web-api/concepts/api-calls#base-url
pub const base_url = "https://api.spotify.com";
pub const version = "v1";
pub const api_url = base_url ++ "/" ++ version;

/// https://developer.spotify.com/documentation/web-api/concepts/scopes
pub const Scope = enum {
    // Images
    /// Write access to user-provided images.
    ugc_image_upload,
    // Spotify Connect
    /// Read access to a user's player state.
    user_read_playback_state,
    /// Write access to a user's playback state.
    user_modify_playback_state,
    /// Read access to a user's currently playing content.
    user_read_currently_playing,
    // Playback
    /// Remote control playback of Spotify.
    /// This scope is currently available to Spotify iOS and Android SDKs.
    app_remote_control,
    /// Control playback of a Spotify track.
    /// This scope is currently available to the Web Playback SDK.
    /// The user must have a Spotify Premium Account.
    streaming,
    // Playlists
    /// Read access to user's private playlists.
    playlist_read_private,
    /// Include collaborative playlists when requesting a user's playlists.
    playlist_read_collaborative,
    /// Write access to a user's private playlists.
    playlist_modify_private,
    /// Write access to a user's private playlists.
    playlist_modify_public,
    // Follow
    /// Write/delete access to the list of artists and other users that the user follows.
    user_follow_modify,
    /// Read access to the list of artists and other users that the user follows.
    user_follow_read,
    // Listening History
    /// Read access to a user’s playback position in a content.
    user_read_playback_position,
    /// Read access to a user's top artists and tracks.
    user_top_read,
    /// Read access to a user’s recently played tracks.
    user_read_recently_played,
    // Library
    /// Write/delete access to a user's "Your Music" library.
    user_library_modify,
    /// Read access to a user's library.
    user_library_read,
    // Users
    /// Read access to user’s email address.
    user_read_email,
    /// Read access to user’s subscription details (type of user account).
    user_read_private,
    /// Get personalized content for the user.
    user_personalized,
    // Open Access
    /// Link a partner user account to a Spotify user account
    user_soa_link,
    /// Unlink a partner user account from a Spotify account
    user_soa_unlink,
    /// Modify entitlements for linked users
    soa_manage_entitlements,
    /// Update partner information
    soa_manage_partner,
    /// Create new partners, platform partners only
    soa_create_partner,

    pub fn toString(self: Scope) *const [@tagName(self).len]u8 {
        comptime {
            const tag_name = @tagName(self);
            var output: [tag_name.len]u8 = undefined;
            _ = std.mem.replace(u8, tag_name, "_", "-", &output);
            return &output;
        }
    }
};

pub const Track = struct {
    album: SimplifiedAlbum = .{},
    artists: []const SimplifiedArtist = &[_]SimplifiedArtist{},
    available_markets: []const []const u8 = &[_][]const u8{},
    disc_number: u64 = 0,
    duration_ms: u64 = 0,
    explicit: bool = false,
    external_ids: ExternalIds = .{},
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
    images: ?[]const Image = null,
    name: []const u8 = "",
    popularity: u64 = 0,
    type: []const u8 = "artist",
    uri: []const u8 = "",
};

pub const SavedAlbum = struct {
    album_type: []const u8 = "",
    total_tracks: u64 = 0,
    available_markets: []const []const u8 = &[_][]const u8{},
    external_urls: ExternalUrls = .{},
    href: []const u8 = "",
    id: []const u8 = "",
    images: ?[]const Image = null,
    name: []const u8 = "",
    release_date: []const u8 = "",
    release_date_precision: []const u8 = "",
    restrictions: struct {
        reason: []const u8 = "",
    } = .{},
    type: []const u8 = "album",
    uri: []const u8 = "",
    artists: []const SimplifiedArtist = &[_]SimplifiedArtist{},
    tracks: Tracks(.default) = .{},
    copyrights: []const struct {
        text: []const u8 = "",
        type: []const u8 = "",
    } = &.{},
    external_ids: ExternalIds = .{},
    genres: []const []const u8 = &.{}, // deprecated: the array is always empty
    label: []const u8 = "",
    popularity: u64 = 0, // between 0 and 100, with 100 being the most popular
};

pub const Album = SimplifiedAlbum;
pub const SimplifiedAlbum = struct {
    album_type: []const u8 = "",
    total_tracks: u64 = 0,
    available_markets: []const []const u8 = &[_][]const u8{},
    external_urls: ExternalUrls = .{},
    href: []const u8 = "",
    id: []const u8 = "",
    images: ?[]const Image = null,
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
    images: ?[]const Image = null,
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
    primary_color: ?[]const u8 = null,
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

pub const ExternalIds = struct {
    isrc: []const u8 = "",
    ean: []const u8 = "",
    upc: []const u8 = "",
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
        } = &.{},
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
            .default => SimplifiedAlbum,
            .saved => struct {
                album: SavedAlbum = .{},
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
    items: []const ?Playlist = &.{},
};

// care the JSON is coated in a struct, get a look at player.getDevices()
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

pub const RepeatState = enum {
    /// Repeat the current track.
    track,
    /// Repeat the current context.
    context,
    /// Don't repeat.
    off,
};

/// https://developer.spotify.com/documentation/web-api/reference/search
pub fn search(
    client: *Client,
    query: []const u8, // will be sanitized
    types: []const u8, // comma separated list of types
    limit: u64, // max num of results, 0-50 (default 20)
    offset: u64, // index of first result to return (default 0)
) !Search {
    var buf: [4096]u8 = undefined;
    const uri_component: std.Uri.Component = .{ .raw = query };
    const url = try std.fmt.bufPrint(
        &buf,
        api_url ++ "/search?q={f}&type={s}&limit={d}&offset={d}",
        .{ std.fmt.alt(uri_component, .formatQuery), types, limit, offset },
    );
    return client.sendRequest(Search, .GET, url, null);
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
