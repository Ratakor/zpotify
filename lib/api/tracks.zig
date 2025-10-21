const std = @import("std");
const api = @import("../api.zig");
const Client = api.Client;

/// https://developer.spotify.com/documentation/web-api/reference/get-track
/// scopes: none
pub fn getTrack(client: *Client, id: []const u8) !api.Track {
    _ = client;
    _ = id;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/get-several-tracks
/// scopes: none
pub fn getTracks(client: *Client, ids: []const u8) ![]api.Track {
    _ = client;
    _ = ids;
    @compileError("unimplemented");
}

/// https://developer.spotify.com/documentation/web-api/reference/get-users-saved-tracks
/// scopes: user-library-read
pub fn getUserTracks(client: *Client, limit: usize, offset: usize) !api.Tracks(.saved) {
    var buf: [128]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &buf,
        api.api_url ++ "/me/tracks?limit={d}&offset={d}",
        .{ limit, offset },
    );
    return client.sendRequest(api.Tracks(.saved), .GET, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/save-tracks-user
/// scopes: user-library-modify
// TODO: ids should be in body, also see timestamped_ids
pub fn saveTracks(client: *Client, ids: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api.api_url ++ "/me/tracks?ids={s}", .{ids});
    return client.sendRequest(void, .PUT, url, "");
}

/// https://developer.spotify.com/documentation/web-api/reference/remove-tracks-user
/// scopes: user-library-modify
// should ids be in body?
pub fn removeTracks(client: *Client, ids: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, api.api_url ++ "/me/tracks?ids={s}", .{ids});
    return client.sendRequest(void, .DELETE, url, null);
}

/// https://developer.spotify.com/documentation/web-api/reference/check-users-saved-tracks
/// scopes: user-library-read
pub fn checkSavedTracks(client: *Client, ids: []const u8) ![]bool {
    _ = client;
    _ = ids;
    @compileError("unimplemented");
}
