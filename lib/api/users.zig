const std = @import("std");
const api = @import("../api.zig");
const Client = api.Client;

/// https://developer.spotify.com/documentation/web-api/reference/get-current-users-profile
/// scopes: user-read-private user-read-email
pub fn getCurrentUserProfile(client: *Client) !api.User {
    _ = client;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/get-users-top-artists-and-tracks
/// scopes: user-top-read
// TODO: getUserTopTracks + getUserTopArtists
pub fn getUserTopItems(client: *Client) !void {
    _ = client;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/get-users-profile
/// scopes: none
// care the returned user doesn't have as much fields as current user
pub fn getUserProfile(client: *Client) !api.User {
    _ = client;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/follow-playlist
/// scopes: playlist-modify-public playlist-modify-private
pub fn followPlaylist(client: *Client, playlist_id: []const u8) !void {
    var buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api.api_url ++ "/playlists/{s}/followers", .{playlist_id});
    // TODO: public should be a parameter
    return client.sendRequest(void, .PUT, url, "{\"public\":false}");
}

/// https://developer.spotify.com/documentation/web-api/reference/unfollow-playlist
/// scopes: playlist-modify-public playlist-modify-private
pub fn unfollowPlaylist(client: *Client, playlist_id: []const u8) !void {
    var buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api.api_url ++ "/playlists/{s}/followers", .{playlist_id});
    return client.sendRequest(void, .DELETE, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/get-followed
/// scopes: user-follow-read
pub fn getFollowedArtists(client: *Client, limit: usize, after: ?[]const u8) !api.Artists {
    var buf: [128]u8 = undefined;
    const url = try if (after) |a| std.fmt.bufPrint(
        &buf,
        api.api_url ++ "/me/following?type=artist&limit={d}&after={s}",
        .{ limit, a },
    ) else std.fmt.bufPrint(&buf, api.api_url ++ "/me/following?type=artist&limit={d}", .{limit});
    return (try client.sendRequest(struct { artists: api.Artists = .{} }, .GET, url, null)).artists;
}

/// https://developer.spotify.com/documentation/web-api/reference/follow-artists-users
/// scopes: user-follow-modify
// should ids be in body?
pub fn followArtists(client: *Client, ids: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api.api_url ++ "/me/following?type=artist&ids={s}", .{ids});
    return client.sendRequest(void, .PUT, url, "");
}

/// https://developer.spotify.com/documentation/web-api/reference/unfollow-artists-users
/// scopes: user-follow-modify
// should ids be in body?
pub fn unfollowArtists(client: *Client, ids: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api.api_url ++ "/me/following?type=artist&ids={s}", .{ids});
    return client.sendRequest(void, .DELETE, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/check-current-user-follows
/// scopes: user-follow-read
pub fn checkUserFollow(
    client: *Client,
    kind: enum { artist, user, playlist },
    ids: []const u8,
) ![]bool {
    _ = client;
    // for playlist do calls to checkUserFollowPlaylist
    _ = kind;
    _ = ids;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/check-if-user-follows-playlist
/// scopes: none
pub fn checkUserFollowPlaylist(client: *Client, playlist_id: []const u8) !bool {
    _ = client;
    _ = playlist_id;
    @compileError("unimplemented");
}
