const std = @import("std");
const api = @import("../api.zig");
const Client = api.Client;

/// https://developer.spotify.com/documentation/web-api/reference/get-available-markets
/// scopes: none
pub fn getAvailableMarkets(client: *Client) ![]const u8 {
    return (try client.sendRequest(
        struct { markets: []const u8 = "" },
        .GET,
        api.api_url ++ "/markets",
        null,
    )).markets;
}
