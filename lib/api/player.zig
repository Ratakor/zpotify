const std = @import("std");
const api = @import("../api.zig");
const Client = api.Client;

/// https://developer.spotify.com/documentation/web-api/reference/get-information-about-the-users-current-playback
/// scopes: user-read-playback-state
pub fn getPlaybackState(client: *Client) !api.PlaybackState {
    return client.sendRequest(api.PlaybackState, .GET, api.api_url ++ "/me/player", null);
}

// TODO: this should be removed
pub fn getPlaybackStateOwned(client: *Client, arena: std.mem.Allocator) !api.PlaybackState {
    return client.sendRequestOwned(api.PlaybackState, .GET, api.api_url ++ "/me/player", null, arena);
}

/// https://developer.spotify.com/documentation/web-api/reference/transfer-a-users-playback
/// scopes: user-modify-playback-state
// TODO: add `play` argument in body
pub fn transferPlayback(client: *Client, device_id: []const u8) !void {
    var buf: [128]u8 = undefined;
    const body = try std.fmt.bufPrint(&buf, "{{\"device_ids\":[\"{s}\"]}}", .{device_id});
    return client.sendRequest(void, .PUT, api.api_url ++ "/me/player", body);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-a-users-available-devices
/// scopes: user-read-playback-state
pub fn getDevices(client: *Client) !api.Devices {
    return (try client.sendRequest(
        struct { devices: api.Devices = &[_]api.Device{} },
        .GET,
        api.api_url ++ "/me/player/devices",
        null,
    )).devices;
}

/// https://developer.spotify.com/documentation/web-api/reference/get-the-users-currently-playing-track
/// scopes: user-read-currently-playing
pub fn getCurrentlyPlaying(client: *Client) !api.PlaybackState {
    return client.sendRequest(api.PlaybackState, .GET, api.api_url ++ "/me/player/currently-playing", null);
}

/// https://developer.spotify.com/documentation/web-api/reference/start-a-users-playback
/// scopes: user-modify-playback-state
// TODO: handle offset, position_ms
pub fn startPlayback(
    client: *Client,
    data: ?union(enum) {
        context_uri: []const u8, // for album, artist or playlist
        uris: []const []const u8, // for tracks
    },
    device_id: ?[]const u8,
) !void {
    var buf: [4096]u8 = undefined;
    var writer: std.Io.Writer = .fixed(buf[0..]);
    const body = blk: {
        if (data) |uri| {
            try writer.print("{f}", .{std.json.fmt(uri, .{})});
            break :blk writer.buffered();
        } else {
            break :blk "{}";
        }
    };

    if (device_id) |id| {
        writer = .fixed(buf[body.len..]);
        try writer.print(api.api_url ++ "/me/player/play?device_id={s}", .{id});
        const url = writer.buffered();
        return client.sendRequest(void, .PUT, url, body);
    } else {
        return client.sendRequest(void, .PUT, api.api_url ++ "/me/player/play", body);
    }
}

/// https://developer.spotify.com/documentation/web-api/reference/pause-a-users-playback
/// scopes: user-modify-playback-state
pub fn pausePlayback(client: *Client) !void {
    return client.sendRequest(void, .PUT, api.api_url ++ "/me/player/pause", "");
}

/// https://developer.spotify.com/documentation/web-api/reference/skip-users-playback-to-next-track
/// scopes: user-modify-playback-state
pub fn skipToNext(client: *Client) !void {
    return client.sendRequest(void, .POST, api.api_url ++ "/me/player/next", "");
}

/// https://developer.spotify.com/documentation/web-api/reference/skip-users-playback-to-previous-track
/// scopes: user-modify-playback-state
pub fn skipToPrevious(client: *Client) !void {
    return client.sendRequest(void, .POST, api.api_url ++ "/me/player/previous", "");
}

/// https://developer.spotify.com/documentation/web-api/reference/seek-to-position-in-currently-playing-track
/// scopes: user-modify-playback-state
pub fn seekToPosition(client: *Client, position_ms: u64) !void {
    var buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api.api_url ++ "/me/player/seek?position_ms={d}", .{position_ms});
    return client.sendRequest(void, .PUT, url, "");
}

/// https://developer.spotify.com/documentation/web-api/reference/set-repeat-mode-on-users-playback
/// scopes: user-modify-playback-state
pub fn setRepeatMode(client: *Client, state: api.RepeatState) !void {
    var buf: [64]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api.api_url ++ "/me/player/repeat?state={t}", .{state});
    return client.sendRequest(void, .PUT, url, "");
}

/// https://developer.spotify.com/documentation/web-api/reference/set-volume-for-users-playback
/// scopes: user-modify-playback-state
/// `volume` must range from 0 to 100 included.
pub fn setVolume(client: *Client, volume: u64) !void {
    var buf: [64]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api.api_url ++ "/me/player/volume?volume_percent={d}", .{volume});
    return client.sendRequest(void, .PUT, url, "");
}

/// https://developer.spotify.com/documentation/web-api/reference/get-recently-played
/// scopes: user-read-recently-played
pub fn getRecentlyPlayed(
    client: *Client,
    limit: usize,
    after: i64,
    before: i64,
) !void {
    _ = client;
    _ = limit;
    _ = after;
    _ = before;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/get-queue
/// scopes: user-read-currently-playing user-read-playback-state
pub fn getQueue(client: *Client) !api.Queue {
    return try client.sendRequest(api.Queue, .GET, api.api_url ++ "/me/player/queue", null);
}

/// https://developer.spotify.com/documentation/web-api/reference/add-to-queue
/// scopes: user-modify-playback-state
pub fn addToQueue(client: *Client, uri: std.Uri.Component) !void {
    var buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &buf,
        api.api_url ++ "/me/player/queue?uri={f}",
        .{std.fmt.alt(uri, .formatQuery)},
    );
    return client.sendRequest(void, .POST, url, "");
}
