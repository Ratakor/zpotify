const std = @import("std");
const api = @import("../api.zig");
const Client = api.Client;

/// https://developer.spotify.com/documentation/web-api/reference/get-playlist
/// scopes: none
pub fn getPlaylist(client: *Client, playlist_id: []const u8) !api.Playlist {
    _ = client;
    _ = playlist_id;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/change-playlist-details
/// scopes: playlist-modify-public playlist-modify-private
// body: JSON struct with name, public, collaborative, description
pub fn changePlaylistDetails(client: *Client, playlist_id: []const u8, body: []const u8) !void {
    _ = client;
    _ = playlist_id;
    _ = body;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/get-playlists-tracks
/// scopes: playlist-read-private
pub fn getPlaylistTracks(
    client: *Client,
    playlist_id: []const u8,
    // fields: []const u8, // allows to filter which fields are returned
    limit: usize,
    offset: usize,
) !api.Tracks(.playlist) {
    var buf: [256]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &buf,
        api.api_url ++ "/playlists/{s}/tracks?limit={d}&offset={d}",
        .{ playlist_id, limit, offset },
    );
    return client.sendRequest(api.Tracks(.playlist), .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/reorder-or-replace-playlists-tracks
/// scopes: playlist-modify-public playlist-modify-private
// body: JSON struct with uris, range_start, insert_before, range_length, snapshot_id
pub fn updatePlaylistTracks(
    client: *Client,
    playlist_id: []const u8,
    uris: []const []const u8,
    body: []const u8,
) !void {
    _ = client;
    _ = playlist_id;
    _ = uris;
    _ = body;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/add-tracks-to-playlist
/// scopes: playlist-modify-public playlist-modify-private
pub fn addTracksToPlaylist(
    client: *Client,
    playlist_id: []const u8,
    uris: []const []const u8,
    position: usize,
) !void {
    // tracks can either be in url or body
    _ = client;
    _ = playlist_id;
    _ = uris;
    _ = position;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/remove-tracks-playlist
/// scopes: playlist-modify-public playlist-modify-private
pub fn removeTracksFromPlaylist(
    client: *Client,
    playlist_id: []const u8,
    tracks: []const []const u8,
    snapshot_id: []const u8,
) !void {
    // tracks must be in body
    _ = client;
    _ = playlist_id;
    _ = tracks;
    _ = snapshot_id;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/get-a-list-of-current-users-playlists
/// scopes: playlist-read-private
pub fn getCurrentUserPlaylists(client: *Client, limit: usize, offset: usize) !api.Playlists {
    var buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &buf,
        api.api_url ++ "/me/playlists?limit={d}&offset={d}",
        .{ limit, offset },
    );
    return client.sendRequest(api.Playlists, .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-list-users-playlists
/// scopes: playlist-read-private playlist-read-collaborative
// should user_id be sanitized?
pub fn getUserPlaylists(
    client: *Client,
    user_id: []const u8,
    limit: usize,
    offset: usize,
) !api.Playlists {
    var buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &buf,
        api.api_url ++ "/users/{s}/playlists?limit={d}&offset={d}",
        .{ user_id, limit, offset },
    );
    return client.sendRequest(api.Playlists, .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/create-playlist
/// scopes: playlist-modify-public playlist-modify-private
// is user_id always `users.getCurrentUserProfile().id`?
// body: JSON struct with name, public, collaborative, description
pub fn createPlaylist(client: *Client, user_id: []const u8, body: []const u8) !void {
    _ = client;
    _ = user_id;
    _ = body;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/get-playlist-cover
/// scopes: none
pub fn getPlaylistCover(client: *Client, playlist_id: []const u8) ![]api.Image {
    _ = client;
    _ = playlist_id;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/upload-custom-playlist-cover
/// scopes: ugc-image-upload playlist-modify-public playlist-modify-private
// body: base64 encoded jpeg image data, maximum size is 256KB
pub fn updatePlaylistCover(client: *Client, playlist_id: []const u8, body: []const u8) !void {
    _ = client;
    _ = playlist_id;
    _ = body;
    @compileError("unimplemented");
}
