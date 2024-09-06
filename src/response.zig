/// https://developer.spotify.com/documentation/web-api/reference/get-information-about-the-users-current-playback
pub const PlaybackState = struct {
    device: ?struct {
        id: ?[]const u8 = null,
        is_active: ?bool = null,
        is_private_session: ?bool = null,
        is_restricted: ?bool = null,
        name: ?[]const u8 = null,
        type: ?[]const u8 = null,
        volume_percent: ?u64 = null,
        supports_volume: ?bool = null,
    } = null,
    repeat_state: ?[]const u8 = null,
    shuffle_state: ?bool = null,
    context: ?struct {
        type: ?[]const u8 = null,
        href: ?[]const u8 = null,
        external_urls: ?struct {
            spotify: ?[]const u8 = null,
        } = null,
        uri: ?[]const u8 = null,
    } = null,
    timestamp: ?u64 = null,
    progress_ms: ?u64 = null,
    is_playing: ?bool = null,
    // TODO: Implement for EpisodeObject
    item: ?struct {
        album: ?struct {
            album_type: []const u8,
            total_tracks: u64,
            available_markets: []const []const u8,
            external_urls: struct {
                spotify: ?[]const u8 = null,
            },
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
            artists: []const struct {
                external_urls: ?struct {
                    spotify: ?[]const u8 = null,
                } = null,
                href: ?[]const u8 = null,
                id: ?[]const u8 = null,
                name: ?[]const u8 = null,
                type: ?[]const u8 = null,
                uri: ?[]const u8 = null,
            },
        } = null,
        artists: ?[]const struct {
            external_urls: ?struct {
                spotify: ?[]const u8 = null,
            } = null,
            href: ?[]const u8 = null,
            id: ?[]const u8 = null,
            name: ?[]const u8 = null,
            type: ?[]const u8 = null,
            uri: ?[]const u8 = null,
        } = null,
        available_markets: ?[]const []const u8 = null,
        disc_number: ?u64 = null,
        duration_ms: ?u64 = null,
        explicit: ?bool = null,
        external_ids: ?struct {
            isrc: ?[]const u8 = null,
            ean: ?[]const u8 = null,
            upc: ?[]const u8 = null,
        } = null,
        external_urls: ?struct {
            spotify: ?[]const u8 = null,
        } = null,
        href: ?[]const u8 = null,
        id: ?[]const u8 = null,
        is_playable: ?bool = null,
        linked_from: ?struct {} = null,
        restrictions: ?struct {
            reason: ?[]const u8 = null,
        } = null,
        name: ?[]const u8 = null,
        popularity: ?u64 = null,
        preview_url: ?[]const u8,
        track_number: ?u64 = null,
        type: ?[]const u8 = null,
        uri: ?[]const u8 = null,
        is_local: ?bool = null,
    } = null,
    currently_playing_type: ?[]const u8 = null,
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

    pub const request = "/me/player";
};

/// https://developer.spotify.com/documentation/web-api/reference/get-the-users-currently-playing-track
pub const CurrentlyPlaying = struct {
    device: ?struct {
        id: ?[]const u8 = null,
        is_active: ?bool = null,
        is_private_session: ?bool = null,
        is_restricted: ?bool = null,
        name: ?[]const u8 = null,
        type: ?[]const u8 = null,
        volume_percent: ?u64 = null,
        supports_volume: ?bool = null,
    } = null,
    repeat_state: ?[]const u8 = null,
    shuffle_state: ?bool = null,
    context: ?struct {
        type: ?[]const u8 = null,
        href: ?[]const u8 = null,
        external_urls: ?struct {
            spotify: ?[]const u8 = null,
        } = null,
        uri: ?[]const u8 = null,
    } = null,
    timestamp: ?u64 = null,
    progress_ms: ?u64 = null,
    is_playing: ?bool = null,
    // TODO: Implement for EpisodeObject
    item: ?struct {
        album: ?struct {
            album_type: []const u8,
            total_tracks: u64,
            available_markets: []const []const u8,
            external_urls: struct {
                spotify: ?[]const u8 = null,
            },
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
            artists: []const struct {
                external_urls: ?struct {
                    spotify: ?[]const u8 = null,
                } = null,
                href: ?[]const u8 = null,
                id: ?[]const u8 = null,
                name: ?[]const u8 = null,
                type: ?[]const u8 = null,
                uri: ?[]const u8 = null,
            },
        } = null,
        artists: ?[]const struct {
            external_urls: ?struct {
                spotify: ?[]const u8 = null,
            } = null,
            href: ?[]const u8 = null,
            id: ?[]const u8 = null,
            name: ?[]const u8 = null,
            type: ?[]const u8 = null,
            uri: ?[]const u8 = null,
        } = null,
        available_markets: ?[]const []const u8 = null,
        disc_number: ?u64 = null,
        duration_ms: ?u64 = null,
        explicit: ?bool = null,
        external_ids: ?struct {
            isrc: ?[]const u8 = null,
            ean: ?[]const u8 = null,
            upc: ?[]const u8 = null,
        } = null,
        external_urls: ?struct {
            spotify: ?[]const u8 = null,
        } = null,
        href: ?[]const u8 = null,
        id: ?[]const u8 = null,
        is_playable: ?bool = null,
        linked_from: ?struct {} = null,
        restrictions: ?struct {
            reason: ?[]const u8 = null,
        } = null,
        name: ?[]const u8 = null,
        popularity: ?u64 = null,
        preview_url: ?[]const u8,
        track_number: ?u64 = null,
        type: ?[]const u8 = null,
        uri: ?[]const u8 = null,
        is_local: ?bool = null,
    } = null,
    currently_playing_type: ?[]const u8 = null,
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

    pub const request = "/me/player/currently-playing";
};

pub const GetError = struct {
    @"error": struct {
        status: u64,
        message: []const u8,
    },
};
