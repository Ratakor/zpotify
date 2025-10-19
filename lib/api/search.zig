const std = @import("std");
const api = @import("../api.zig");
const Client = api.Client;

/// https://developer.spotify.com/documentation/web-api/reference/search
/// scopes: none
pub fn search(
    client: *Client,
    query: std.Uri.Component,
    /// The list of item types to search across.
    /// Asserts that the list is not empty.
    types: []const api.SearchType,
    /// The maximum number of results to return in each item type.
    /// Default: 20
    /// Range: 0-50
    limit: usize,
    /// The index of the first result to return.
    /// Default: 0
    /// Range: 0 - 1000
    offset: usize,
) !api.Search {
    std.debug.assert(types.len > 0);

    var buf: [4096]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);

    try writer.print(api.api_url ++ "/search?q={f}&type={t}", .{ std.fmt.alt(query, .formatQuery), types[0] });
    for (types[1..]) |t| {
        // %2C is ,
        try writer.print("%2C{t}", .{t});
    }
    try writer.print("&limit={d}&offset={d}", .{ limit, offset });

    const url = writer.buffered();

    return client.sendRequest(api.Search, .GET, url, null);
}
