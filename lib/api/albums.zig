const std = @import("std");
const api = @import("../api.zig");
const Client = api.Client;

/// https://developer.spotify.com/documentation/web-api/reference/get-an-album
/// scopes: none
pub fn getAlbum(client: *Client, id: []const u8, market: ?[]const u8) !api.Album {
    _ = client;
    _ = id;
    _ = market;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/get-multiple-albums
/// scopes: none
pub fn getAlbums(client: *Client, ids: []const []const u8, market: ?[]const u8) ![]api.Album {
    _ = client;
    _ = ids;
    _ = market;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/get-an-albums-tracks
/// scopes: none
pub fn getAlbumTracks(
    client: *Client,
    id: []const u8,
    limit: usize,
    offset: usize,
) !api.Tracks(.default) {
    var buf: [256]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &buf,
        api.api_url ++ "/albums/{s}/tracks?limit={d}&offset={d}",
        .{ id, limit, offset },
    );
    return client.sendRequest(api.Tracks(.default), .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-users-saved-albums
/// scopes: user-library-read
pub fn getUserAlbums(client: *Client, limit: usize, offset: usize) !api.Albums {
    var buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &buf,
        api.api_url ++ "/me/albums?limit={d}&offset={d}",
        .{ limit, offset },
    );
    return client.sendRequest(api.Albums, .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/save-albums-user
/// scopes: user-library-modify
// should ids be sent in the body instead? (this means limit 20 -> 50)
pub fn saveAlbums(client: *Client, ids: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api.api_url ++ "/me/albums?ids={s}", .{ids});
    return client.sendRequest(void, .PUT, url, "");
}

/// https://developer.spotify.com/documentation/web-api/reference/remove-albums-user
/// scopes: user-library-modify
// should ids be sent in the body instead? (this means limit 20 -> 50)
pub fn removeAlbums(client: *Client, ids: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api.api_url ++ "/me/albums?ids={s}", .{ids});
    return client.sendRequest(void, .DELETE, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/check-users-saved-albums
/// scopes: user-library-read
pub fn checkSavedAlbums(client: *Client, ids: []const u8) ![]bool {
    _ = client;
    _ = ids;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/get-new-releases
pub fn getNewReleases(client: *Client, limit: usize, offset: usize) !api.SimplifiedAlbums {
    _ = client;
    _ = limit;
    _ = offset;
    @compileError("unimplemented");
}
