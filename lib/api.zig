//! https://developer.spotify.com/documentation/web-api/reference
// Specifying market is unhandled, it's often better to rely on user market anyway.

const std = @import("std");

// TODO: remove dependency on Client or make it less tied to the CLI
pub const Client = @import("Client.zig");

pub const albums = @import("api/albums.zig");
pub const artists = @import("api/artists.zig");
// Audiobooks are unsupported
// Categories are unsupported (as I don't understand their purpose)
// Chapters are unsupported
// Episodes are unsupported
// Genres are unsupported (because it's deprecated)
pub const markets = @import("api/markets.zig");
pub const player = @import("api/player.zig");
pub const playlists = @import("api/playlists.zig");
pub const search = @import("api/search.zig").search;
// Shows are unsupported
pub const tracks = @import("api/tracks.zig");
pub const users = @import("api/users.zig");

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

pub const Album = struct {
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
    /// deprecated: the array is always empty
    genres: []const []const u8 = &.{},
    label: []const u8 = "",
    /// between 0 and 100, with 100 being the most popular
    popularity: u64 = 0,
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

// used for Tracks()
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
    items: []const SimplifiedArtist = &.{},
};

pub const Artists = struct {
    href: []const u8 = "",
    limit: u64 = 0,
    next: ?[]const u8 = null,
    cursors: struct {
        after: ?[]const u8 = null,
        before: ?[]const u8 = null,
    } = .{},
    total: u64 = 0,
    items: []const Artist = &.{},
};

pub const SimplifiedAlbums = struct {
    href: []const u8 = "",
    limit: u64 = 0,
    next: ?[]const u8 = null,
    offset: u64 = 0,
    previous: ?[]const u8 = null,
    total: u64 = 0,
    items: []const SimplifiedAlbum = &.{},
};

pub const Albums = struct {
    href: []const u8 = "",
    limit: u64 = 0,
    next: ?[]const u8 = null,
    offset: u64 = 0,
    previous: ?[]const u8 = null,
    total: u64 = 0,
    items: []const struct {
        album: Album = .{},
        added_at: []const u8 = "",
    } = &.{},
};

pub const Playlists = struct {
    href: []const u8 = "",
    limit: u64 = 0,
    next: ?[]const u8 = null,
    offset: u64 = 0,
    previous: ?[]const u8 = null,
    total: u64 = 0,
    items: []const ?Playlist = &.{},
};

pub const Devices = []const Device;

pub const PlaybackState = struct {
    device: ?Device = null,
    repeat_state: []const u8 = "off",
    shuffle_state: bool = false,
    /// undocumented
    smart_shuffle: ?bool = null,
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
        /// undocumented
        disallows: ?struct {
            resuming: ?bool = null,
        } = null,
    } = null,
};

pub const SearchType = enum {
    album,
    artist,
    playlist,
    track,
    // show,
    // episode,
    // audiobook,
};

pub const Search = struct {
    tracks: ?Tracks(.default) = null,
    artists: ?Artists = null,
    albums: ?SimplifiedAlbums = null,
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

pub const User = struct {
    country: []const u8 = "",
    display_name: []const u8 = "",
    email: []const u8 = "",
    explicit_content: struct {
        filter_enabled: bool = false,
        filter_locked: bool = false,
    } = .{},
    external_urls: ExternalUrls,
    followers: struct {
        href: ?[]const u8 = null,
        total: usize = 0,
    } = .{},
    href: []const u8 = "",
    id: []const u8 = "",
    images: ?[]const Image = null,
    product: ?[]const u8 = null,
    type: []const u8 = "user",
    uri: []const u8 = "",
};
