const std = @import("std");
const api = @import("zpotify");

io: std.Io,
allocator: std.mem.Allocator,
arena: *std.heap.ArenaAllocator,
env_map: *std.process.Environ.Map,
args: std.process.Args.Iterator,
client: *api.Client,
