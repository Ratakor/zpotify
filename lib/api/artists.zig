const std = @import("std");
const api = @import("../api.zig");
const Client = api.Client;

/// https://developer.spotify.com/documentation/web-api/reference/get-an-artist
/// scopes: none
pub fn getArtist(client: *Client, id: []const u8) !api.Artist {
    var buf: [256]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api.api_url ++ "/artists/{s}", .{id});
    return client.sendRequest(api.Artist, .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-multiple-artists
/// scopes: none
pub fn getArtists(client: *Client, ids: []const u8) ![]api.Artist {
    _ = client;
    _ = ids;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/get-an-artists-albums
/// scopes: none
pub fn getArtistAlbums(
    client: *Client,
    id: []const u8,
    // include_groups: []const u8, // album, single, appears_on, compilation
    // market: []const u8,
    limit: usize,
    offset: usize,
) !api.SimplifiedAlbums {
    var buf: [256]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &buf,
        api.api_url ++ "/artists/{s}/albums?limit={d}&offset={d}",
        .{ id, limit, offset },
    );
    return client.sendRequest(api.SimplifiedAlbums, .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-an-artists-top-tracks
/// scopes: none
// care the JSON is coated in another struct
pub fn getArtistTopTracks(client: *Client, id: []const u8) ![]api.Track {
    _ = client;
    _ = id;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/get-an-artists-related-artists
/// scopes: none
// care the JSON is coated in another struct
pub fn getRelatedArtists(client: *Client, id: []const u8) ![]api.Artist {
    _ = client;
    _ = id;
    @compileError("unimplemented");
}
